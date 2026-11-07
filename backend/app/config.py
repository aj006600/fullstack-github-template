from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_env: str = "local"
    log_level: str = "info"


settings = Settings()
