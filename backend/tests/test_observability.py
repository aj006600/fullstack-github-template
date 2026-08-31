import json
import logging
import re

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _records(out: str, event: str) -> list[dict]:
    return [r for r in map(json.loads, out.splitlines()) if r["event"] == event]


def test_stdlib_log_is_rendered_as_json_line(capfd):
    """uvicorn 走 stdlib logging；它的 log 也要以一行 JSON 寫到 stdout。"""
    logging.getLogger("uvicorn.error").warning("Something %s", "happened")
    record = json.loads(capfd.readouterr().out)
    assert record["event"] == "Something happened"
    assert record["level"] == "warning"


def test_response_carries_generated_request_id():
    """沒帶 X-Request-ID 時 backend 自產一個（uuid4 hex）回在 header。"""
    response = client.get("/api/message")
    assert re.fullmatch(r"[0-9a-f]{32}", response.headers["X-Request-ID"])


def test_response_echoes_valid_request_id():
    """帶了合法的 X-Request-ID 就沿用，原值回在 header。"""
    response = client.get("/api/message", headers={"X-Request-ID": "abc-123"})
    assert response.headers["X-Request-ID"] == "abc-123"


@pytest.mark.parametrize("bad_id", ["", "x" * 65])
def test_invalid_request_id_is_replaced(bad_id):
    """空的或超過 64 字元的 X-Request-ID 被丟棄，改為自產。"""
    response = client.get("/api/message", headers={"X-Request-ID": bad_id})
    assert re.fullmatch(r"[0-9a-f]{32}", response.headers["X-Request-ID"])


def test_request_log_line_matches_response(capfd):
    """request 結束時 stdout 有一行 JSON 的 request log，request_id 等於回應 header。"""
    response = client.get("/api/message")
    (record,) = _records(capfd.readouterr().out, "request.completed")
    assert record["request_id"] == response.headers["X-Request-ID"]
    assert record["method"] == "GET"
    assert record["path"] == "/api/message"
    assert record["status_code"] == 200
    assert isinstance(record["duration_ms"], float)


def test_app_log_during_request_carries_same_request_id(capfd):
    """request 期間 app 自己發的 log（示範的 message.served）自動帶同一 request_id。"""
    response = client.get("/api/message")
    (served,) = _records(capfd.readouterr().out, "message.served")
    assert served["request_id"] == response.headers["X-Request-ID"]


def test_health_produces_no_request_log(capfd):
    """/health 是 healthcheck 的目標，不產生 request log。"""
    client.get("/health")
    # stdout 上仍可能有 httpx（TestClient 端）的 log，只看 backend 的 request log
    assert _records(capfd.readouterr().out, "request.completed") == []
