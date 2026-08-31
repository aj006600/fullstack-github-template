import json
import logging

import app.main  # noqa: F401  logging 設定在建立 app 時完成，這裡只驗設定後的可觀察行為


def test_stdlib_log_is_rendered_as_json_line(capfd):
    """uvicorn 走 stdlib logging；它的 log 要和 app 的一樣是 stdout 上一行 JSON。"""
    logging.getLogger("uvicorn.error").warning("Something %s", "happened")
    record = json.loads(capfd.readouterr().out)
    assert record["event"] == "Something happened"
    assert record["level"] == "warning"
