# 模組名刻意不叫 logging：與 stdlib 同名會讓 import 混淆讀者。
import logging
import sys
import time
from uuid import uuid4

import structlog
from starlette.datastructures import Headers, MutableHeaders
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.config import Settings

# uvicorn 啟動時用自己的 dictConfig 給這三個 logger 各掛 handler、關 propagate、
# 設 INFO。不逐一清掉，就會出現兩種格式混雜，且 LOG_LEVEL 對 uvicorn 無效。
_UVICORN_LOGGERS = ("uvicorn", "uvicorn.error", "uvicorn.access")

# 沿用外部傳入 X-Request-ID 的長度上限：超過就當垃圾丟掉改自產，免得有人往 log 塞東西
_REQUEST_ID_MAX_LEN = 64

# healthcheck（頻率見 compose.yaml）會淹沒真正的訊號
_UNLOGGED_PATHS = frozenset({"/health"})


def configure_logging(settings: Settings) -> None:
    """讓 structlog 與 stdlib logging（uvicorn）共用同一條 renderer，全部寫到 stdout。

    必須在 uvicorn 套用自己的 logging 設定之後執行——uvicorn 在 import app 之前就做了，
    所以在 app.main 建立 app 前呼叫即可；--reload 的 worker process 也是同樣順序。
    """
    # structlog 自己的 log 與 stdlib 進來的 log 都走這段，欄位才會一致；
    # merge_contextvars 放最前面，request 期間 uvicorn 的 log 才也帶 request_id
    shared_processors: list[structlog.typing.Processor] = [
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso", utc=True),
    ]
    if settings.log_format == "json":
        # JSONRenderer 不會處理 exc_info tuple，得先轉成字串；ConsoleRenderer 自己會印
        renderers: list[structlog.typing.Processor] = [
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ]
    else:
        renderers = [structlog.dev.ConsoleRenderer()]

    formatter = structlog.stdlib.ProcessorFormatter(
        foreign_pre_chain=shared_processors,
        processors=[
            structlog.stdlib.ProcessorFormatter.remove_processors_meta,
            *renderers,
        ],
    )
    # sys.__stdout__ 而非 sys.stdout：pytest 在收集階段就把 sys.stdout 換成自己的物件，
    # handler 若在 import 時抓住它，之後 capfd 就抓不到任何 log
    handler = logging.StreamHandler(sys.__stdout__)
    handler.setFormatter(formatter)

    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(settings.log_level.upper())

    for name in _UVICORN_LOGGERS:
        logger = logging.getLogger(name)
        logger.handlers.clear()
        logger.propagate = True
        logger.setLevel(logging.NOTSET)
    # 內建 access log 由 RequestLogMiddleware 的 request log 取代，留著會一個 request
    # 兩行。在程式裡停用而非靠 --no-access-log：不管 uvicorn 怎麼被啟動都一致
    logging.getLogger("uvicorn.access").disabled = True

    structlog.configure(
        processors=[
            structlog.stdlib.filter_by_level,
            *shared_processors,
            structlog.stdlib.PositionalArgumentsFormatter(),
            structlog.processors.StackInfoRenderer(),
            structlog.stdlib.ProcessorFormatter.wrap_for_formatter,
        ],
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )


class RequestLogMiddleware:
    """Request ID 與 request log（詞條定義見 CONTEXT.md「Observability」）。

    pure ASGI 而非 Starlette 的 BaseHTTPMiddleware：後者把 request 包成另一個 task，
    contextvars 綁定不會跟著回到 endpoint，且 streaming response 有已知問題。
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app
        self.log = structlog.get_logger("app.request")

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        incoming = Headers(scope=scope).get("x-request-id", "")
        if 1 <= len(incoming) <= _REQUEST_ID_MAX_LEN:
            request_id = incoming
        else:
            request_id = uuid4().hex
        structlog.contextvars.bind_contextvars(request_id=request_id)
        status_code = 500
        started = time.perf_counter()

        async def send_with_request_id(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
                MutableHeaders(scope=message).append("X-Request-ID", request_id)
            await send(message)

        def log_completed() -> None:
            if scope["path"] in _UNLOGGED_PATHS:
                return
            self.log.info(
                "request.completed",
                method=scope["method"],
                path=scope["path"],
                status_code=status_code,
                duration_ms=round((time.perf_counter() - started) * 1000, 2),
            )

        try:
            await self.app(scope, receive, send_with_request_id)
        except Exception:
            # 未捕捉例外：外層 ServerErrorMiddleware 用原始 send 回 500，所以那個回應
            # 沒有 X-Request-ID header（瀏覽器端由 nginx 補）；uvicorn 再於 middleware
            # 之外記 traceback。這裡刻意不清 contextvars，那行才帶得到 request_id；
            # 不會漏到下一個 request——ASGI server 每個 request 開新 task，context 是副本
            log_completed()
            raise
        log_completed()
        # 正常路徑仍清掉：不依賴 server 的 task 模型，TestClient 之類的 portal 也安全
        structlog.contextvars.clear_contextvars()
