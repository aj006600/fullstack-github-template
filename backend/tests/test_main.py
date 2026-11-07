from fastapi.testclient import TestClient

from app.config import settings
from app.main import app

client = TestClient(app)


def test_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_message_reports_configured_env(monkeypatch):
    # 改 settings 而非環境變數:settings 是 import 時就建立的單例,不會重讀 env
    monkeypatch.setattr(settings, "app_env", "qas")
    assert client.get("/api/message").json()["env"] == "qas"
