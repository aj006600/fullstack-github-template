# 模組名刻意不叫 logging：與 stdlib 同名會讓 import 混淆讀者。
import logging
import sys

import structlog

from app.config import Settings

# uvicorn 啟動時用自己的 dictConfig 給這三個 logger 各掛 handler、關 propagate、
# 設 INFO。不逐一清掉，就會出現兩種格式混雜，且 LOG_LEVEL 對 uvicorn 無效。
_UVICORN_LOGGERS = ("uvicorn", "uvicorn.error", "uvicorn.access")


def configure_logging(settings: Settings) -> None:
    """讓 structlog 與 stdlib logging（uvicorn）共用同一條 renderer，全部寫到 stdout。

    必須在 uvicorn 套用自己的 logging 設定之後執行——uvicorn 在 import app 之前就做了，
    所以在 app.main 建立 app 前呼叫即可；--reload 的 worker process 也是同樣順序。
    """
    # structlog 自己的 log 與 stdlib 進來的 log 都走這段，欄位才會一致
    shared_processors: list[structlog.typing.Processor] = [
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso", utc=True),
    ]
    if settings.log_format == "json":
        # JSONRenderer 不會處理 exc_info tuple，得先轉成字串；ConsoleRenderer 自己會印
        render: list[structlog.typing.Processor] = [
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ]
    else:
        render = [structlog.dev.ConsoleRenderer()]

    formatter = structlog.stdlib.ProcessorFormatter(
        foreign_pre_chain=shared_processors,
        processors=[
            structlog.stdlib.ProcessorFormatter.remove_processors_meta,
            *render,
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
