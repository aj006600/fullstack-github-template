import structlog
from fastapi import FastAPI

from app.config import settings
from app.observability import RequestLogMiddleware, configure_logging

configure_logging(settings)

app = FastAPI(title="fullstack-github-template backend", version="0.1.0")
app.add_middleware(RequestLogMiddleware)

log = structlog.get_logger()


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.get("/api/message")
def message():
    # demo 用：前端顯示這個 env，證明同一顆 image 的設定隨 environment 變；
    # 這行 log 是寫 app log 的範本，慣例見 docs/development.md「Reading logs」
    log.info("message.served", env=settings.app_env)
    return {"message": "Hello from the backend", "env": settings.app_env}
