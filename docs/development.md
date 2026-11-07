# Development

本機開發的日常操作。所有指令在 repo 根目錄執行。

## Quickstart

```bash
make dev       # 前後端起來,後端 hot reload(前景執行,Ctrl+C 停止)
make dev-down  # 停止並清理 container 與 network
```

乾淨 clone 不必先建任何檔案:`make dev` 發現缺 `.env.local` 時會從 `.env.example` 複製一份。

- 前端 → http://localhost:3000(頁面會顯示 backend 回傳的環境 `local`,證明接通了)
- 後端 → http://localhost:8000/health

前後端怎麼溝通:瀏覽器只打 frontend,`/api/*` 由 frontend 的 nginx 反向代理到 backend(同源、免 CORS)。

```
瀏覽器 → frontend(nginx:80) ──/api/──▶ backend(uvicorn:8000)
                          └─ 其他路徑 = SPA 靜態檔
```

## Configuration

設定一律走環境變數,本機的來源是 `.env.local`:

| 檔案 | 進版控 | 用途 |
|------|--------|------|
| `.env.example` | 是 | 範本:列出所有變數,非機密給可用的本機預設值,機密給 placeholder |
| `.env.local` | 否 | 你這台機器實際讀的值;缺檔時 `make dev` 自動從 example 複製 |

變數名與部署主機上 `.env.<env>` 的一致,程式不必為環境分支。
新增變數:先加進 `.env.example`,再到自己的 `.env.local` 填值。

本機的 `APP_ENV` 是 **`local`**,刻意與部署出去的 `dev` 環境區分——頁面顯示 `local` 就表示你看的是本機。

## Hot reload 的範圍

`make dev` 掛載 `backend/app/` 與 `backend/tests/`,改 Python 檔立即生效。
**改 `pyproject.toml` / `uv.lock` 要重跑 `make dev`**(相依烤在 image 裡,掛載蓋不到)。

前端在 `make dev` 下是 build 好的靜態檔,改 jsx 不會即時反映;要前端 hot reload 就直接
`cd frontend && npm install && npm run dev`(vite dev server 會把 `/api` 代理到 localhost:8000)。

## 測試與品質

```bash
make test      # pytest
make lint      # ruff check
make format    # ruff format(就地改檔)
```

都跑在 backend 的 dev stage 容器裡,跟 CI 的 `test-backend` job 同一顆 image——本機過了 CI 就會過。

## 常用檢查

```bash
make ps                                  # 正在跑的 container(名稱 / 狀態 / 埠)
docker compose -f compose.yaml -f compose.dev.yaml logs -f backend   # 追後端 log
docker compose -f compose.yaml -f compose.dev.yaml exec backend sh   # 進容器
```
