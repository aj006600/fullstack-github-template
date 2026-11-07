from fastapi import FastAPI

from app.config import settings
from app.logging_setup import configure_logging

configure_logging(settings)

app = FastAPI(title="fullstack-github-template backend", version="0.1.0")


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.get("/api/message")
def message():
    # demo 用:前端顯示這個 env,證明同一顆 image 的設定隨 environment 變
    return {"message": "Hello from the backend", "env": settings.app_env}
