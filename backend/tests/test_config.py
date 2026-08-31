import pytest
from pydantic import ValidationError

from app.config import Settings


def test_unknown_log_level_is_rejected(monkeypatch):
    """LOG_LEVEL 打錯字要在建立設定時就失敗，不能靜默退回預設值。"""
    monkeypatch.setenv("LOG_LEVEL", "verbose")
    with pytest.raises(ValidationError):
        Settings()
