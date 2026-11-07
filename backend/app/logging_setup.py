"""設定 log 的格式與層級,讓所有進入點印出來的 log 長得一樣。"""

import logging

from app.config import Settings


def configure_logging(settings: Settings) -> None:
    logging.basicConfig(
        level=settings.log_level.upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    # LOG_LEVEL 設成 debug 時,httpx 與 httpcore 會為每一個請求各印一則 log,
    # 把 worker 自己的訊息淹掉
    for name in ("httpx", "httpcore"):
        logging.getLogger(name).setLevel(logging.WARNING)
