from typing import Literal

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_env: str = "dev"
    # Literal 而非 str：打錯字要在啟動時就炸，不能靜默退回預設值
    log_level: Literal["debug", "info", "warning", "error"] = "info"
    # 部署一律 json；console 只由 compose.dev.yaml 覆寫，env/.env.* 刻意不寫這個值
    log_format: Literal["json", "console"] = "json"


settings = Settings()
