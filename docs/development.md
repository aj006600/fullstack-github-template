# Local Development

[← README](../README.md)

前後端怎麼溝通：瀏覽器只打 frontend，`/api/*` 由 nginx
反向代理到 backend（同源、後端免處理 CORS）。`/api/message` 回傳 backend 讀到的 `APP_ENV`——本機是 `local`，
部署後是該 environment 的名字。

## Quickstart

`make dev` 用於**本機開發**：起前後端、掛載後端 source code 並開啟 hot reload，直接連 `localhost`。

```bash
make dev          # 前後端起來、後端 hot reload（前景執行，佔住終端機）
# 前端 → http://localhost:3000（會顯示 backend 回傳的環境 local）
# 後端 → http://localhost:8000/health

make dev-down     # 停止並清理：移除本機開發的 container 與 network
```

乾淨 clone 不必先建任何檔案：`make dev` 發現缺 `.env.local` 時會從 `.env.example` 複製一份。
`make dev` 用 `compose.dev.yaml`：前端開 3000、後端開 8000，並掛載後端 source code + hot reload。

> 收工用 **`make dev-down`** 停止並清理。`make dev` 是前景執行，也可直接按 **`Ctrl+C`** 停止——但 `Ctrl+C` 只是停止 container（仍殘留為 exited 狀態），`make dev-down` 會進一步**移除**殘留的 container 與 network。

## Configuration

設定一律走環境變數，本機的來源是 `.env.local`：

| 檔案 | 進版控 | 用途 |
|------|--------|------|
| `.env.example` | 是 | 範本：列出所有變數，非機密給可用的本機預設值，機密給 placeholder |
| `.env.local` | 否 | 你這台機器實際讀的值；缺檔時 `make dev` 自動從 example 複製 |

新增變數：先加進 `.env.example`，再到自己的 `.env.local` 填值。部署主機上的 `.env.<env>` 用同一組變數名，
程式不必為環境分支（見 [deployment.md](deployment.md#host-configuration)）。

本機的 `APP_ENV` 是 **`local`**，刻意與部署出去的 dev environment 區分——頁面顯示 `local` 就表示你看的是本機。

## Testing changes (hot reload)

`make dev` 已掛載後端 source code 並開啟 `uvicorn --reload`，所以測試一個改動**不需進 container、也不需 rebuild**：

1. 在**本機**編輯 `backend/app/*.py`（用你的編輯器）。
2. Container 內的 uvicorn 偵測到變更、**自動 reload**。
3. 直接打 API 驗證：

```bash
curl http://localhost:8000/api/message      # 或開瀏覽器 http://localhost:3000
```

注意：

- **Hot reload 只適用「後端 + `make dev`」**（只有這個組合掛載了 source code + `--reload`）。
- **前端在 `make dev` 不會 hot reload**（它是 build 好的 nginx image）；前端要即時開發請用下方「Working without containers」的 `npm run dev`（Vite HMR，`:5173`，跑一次讓它開著、存檔即自動更新）。
- **部署（`make deploy`）不掛載 source code**，跑的是 CI 建好的映像——改本機程式碼不會反映。

## Tests & lint

```bash
make test      # pytest（後端）
make lint      # ruff check
make format    # ruff format
```

都跑在 Dockerfile 的 **dev stage** 容器裡（含 pytest / ruff）；`--build` 已內建，改了 `pyproject.toml` / `uv.lock` 會自動生效。CI 以同樣的檢查把關，本機先跑省一輪紅燈。

## Reading logs

backend 的每一行 log——app 自己的、uvicorn 的啟動訊息、未捕捉例外的 traceback——都寫到 stdout、同一種格式。
`make dev` 前景看到的是彩色的 `key=value` 格式（`LOG_FORMAT=console`，只在 `compose.dev.yaml` 覆寫）：

```
2026-08-31T05:50:49.892358Z [info     ] Application startup complete.  [uvicorn.error]
2026-08-31T05:50:51.604395Z [info     ] message.served                 [app.main] env=local request_id=cf4d3f541d2444ba9391360fb991fb94
2026-08-31T05:50:51.604746Z [info     ] request.completed              [app.request] duration_ms=4.4 method=GET path=/api/message request_id=cf4d3f541d2444ba9391360fb991fb94 status_code=200
```

依序是時間、等級、事件名、logger 名，之後是該行的欄位。部署時同一批 log 是一行一筆的 JSON
（預設值，見 [deployment.md](deployment.md#host-configuration)）。

- **Request log**：每個 request 結束時一行 `request.completed`，帶 `method`、`path`、`status_code`、`duration_ms`——看哪個 endpoint 慢或錯就看這行。uvicorn 內建的 access log 已停用，`/health`（healthcheck 每 3 秒一次）不產生 request log。詞條定義見 [CONTEXT.md](../CONTEXT.md#observability)。
- **Request ID**：request 期間 backend 的每一行 log 都帶 `request_id`，且以 `X-Request-ID` 回在 response header。瀏覽器裡某個操作失敗時，開 devtools → Network → 點那個 `/api/*` 請求 → Response Headers 抄下 `X-Request-ID`，到 `make dev` 的終端機搜這個值，就是那次請求的全部 log。詞條定義見 [CONTEXT.md](../CONTEXT.md#observability)。
  - 經 `:3000`：id 由 nginx 產生，nginx access log 行尾也有同一個 id。
  - 直接打 `:8000`、或 `npm run dev` 的 Vite 代理：不經 nginx，backend 沿用請求自帶的 `X-Request-ID`（1–64 字元），沒有就自產。
- **自己寫 log**：照 `app/main.py` 的 `message.served`——`structlog.get_logger()` 取 logger、事件名用 `名詞.動詞`、欄位用 kwargs 而不是塞進字串；`request_id` 會自動帶上，不用自己傳。
- **等級**由 `.env.local` 的 `LOG_LEVEL` 決定（`debug` ｜ `info` ｜ `warning` ｜ `error`），對 app 與 uvicorn 都生效；打錯字時服務啟動就失敗。
- `uvicorn --reload` 的 **reloader 行**例外（`Will watch for changes` / `Uvicorn running on` / `Started reloader process` / `WatchFiles detected changes`）：它們來自不載入 app 的監看 process，仍是 uvicorn 原生的 `INFO:` 格式。

## Entering containers (docker exec)

承上，改程式碼靠 hot reload 即可、**不需進 container**；跑測試 / lint 用上方的 `make test` / `make lint` 也免進。進 container 是為了「在 container 內執行指令 / 檢查 / 除錯」——例如查看環境變數、執行一次性腳本、確認相依安裝。

用 compose 的 **service 名**進入（免查容器名，在專案根目錄執行）：

```bash
docker compose -f compose.yaml -f compose.dev.yaml exec backend bash   # 後端（Debian 基底，有 bash）
docker compose -f compose.yaml -f compose.dev.yaml exec frontend sh    # 前端（nginx:alpine，用 sh）
```

或用容器名（先以 `docker ps` / `make ps` 查名稱）：

```bash
docker exec -it <容器名> bash    # 後端；前端用 sh
```

Container 內：後端工作目錄為 `/app`、程式在 `/app/app`、venv 在 `/app/.venv`（`uvicorn`、`pytest` 等已在 PATH）。`make dev` 的後端容器跑 Dockerfile 的 **dev stage、以 root 執行**（開發便利、可直接裝系統套件）；部署用的 **runtime stage 才以非 root `appuser` 執行**（前端 nginx 則一律預設 root）。

> 上述指令針對 `make dev`。若跑的是部署（`make deploy`，runtime stage），各 environment 的 project 名不同（`fullstack-dev` / `fullstack-qas` / `fullstack-prd`），用 `docker ps` 查容器名後以 `docker exec -it <容器名> …` 進入；容器內是 `appuser`，需要 root 時加 `-u root`。

## Working without containers

更快的內層迴圈（inner loop），前端並有 Vite HMR：

```bash
# 後端
cd backend && uv sync --dev
LOG_FORMAT=console uv run uvicorn app.main:app --reload   # :8000（LOG_FORMAT 不設則是 JSON）
uv run pytest -q

# 前端（另開終端機）
cd frontend && npm install && npm run dev           # :5173，/api 已由 Vite 代理到 :8000
```

## Inspecting what's running

```bash
docker compose ls        # 有哪些 compose project 在跑（一眼看出起了哪些環境）
make ps                  # 模板內建：正在跑的 container（名稱 / 狀態 / 埠）
docker ps                # 同上，未美化
```

看更完整（含停掉殘留、network）：

```bash
docker ps -a             # 連「停掉但殘留」的 container 也列（exited 狀態）
docker compose ls -a     # 連停掉的 compose project 也列
docker network ls        # 有哪些 network（各 project 一個）
```

> `docker compose ls` 列出的 project 名就是「哪個 environment 正開著」——`make deploy` 用 `fullstack-<env>`，`make dev` 用資料夾名，兩者互不干擾。
