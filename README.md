# fullstack-github-template

前後端分離 + 多環境（dev / qas / prod）的容器範本：React(Vite) 前端 + FastAPI 後端，
用 docker compose 兜起來，GitHub Actions 遵循「build 一次、依序 promote」。

> 核心原則（12-factor）：**一份程式碼、一組 image、設定隨環境變**。設定一律是環境變數：
> 本機讀 `.env.local`（從 `.env.example` 複製，不進版控），目標主機讀自備的 `.env.<env>`。

## Docs

| 想做的事 | 看這份 |
|----------|--------|
| **本機開發**（quickstart、設定、hot reload、測試、log、docker exec） | [docs/development.md](docs/development.md) |
| **CI/CD 與部署**（promotion、rollback、主機設定、log、troubleshooting） | [docs/deployment.md](docs/deployment.md) |
| **術語**（`dev` 的三個意思、Request ID…） | [CONTEXT.md](CONTEXT.md) |

## Make it yours

1. GitHub 上按 **Use this template** 開新 repo，clone 下來。
2. **改名**——在 repo 根目錄執行，`<your-app>` 換成你的專案名（小寫英數與連字號，會用在 image 名與 compose project 名）：
   ```bash
   NAME=<your-app>
   git ls-files -z | xargs -0 perl -pi -e "s/fullstack-github-template/$NAME/gi; s/fullstack/$NAME/gi"
   ```
   兩條規則的順序不能反：先換長的，否則 `fullstack-github-template` 會被切成 `<your-app>-github-template`。
3. **換上自己的 README 與 CONTEXT.md**——刪掉後為專案寫專屬的：`rm README.md CONTEXT.md`。
4. `git diff` 檢查一遍，commit、push。

之後新專案與這個 template 各走各的，template 日後的修正不會自動流過去。

## Quickstart

```bash
make dev       # 前後端起來，後端 hot reload（前景執行）；缺 .env.local 時自動從 .env.example 複製
# 前端 → http://localhost:3000（會顯示 backend 回傳的環境 local）
# 後端 → http://localhost:8000/health
make dev-down  # 停止並清理（或直接 Ctrl+C 停止；詳見 docs/development.md）

make help      # 所有指令與參數
```

前後端怎麼溝通：瀏覽器只打 frontend，`/api/*` 由 frontend 的 nginx 反向代理到 backend（同源、免 CORS）。

```
瀏覽器 → frontend(nginx:80) ──/api/──▶ backend(uvicorn:8000)
                          └─ 其他路徑 = SPA 靜態檔
```

## Deployment

merge 到 `main` 後 CI 會 build 出該 commit 的 `:sha` 推到 GHCR；部署在**目標主機**（amd64 Linux）上執行，
拉這顆測過的映像，不重 build。主機要自備該環境的 `.env.<env>`：

```bash
make deploy ENV=<dev|qas|prod> IMAGE=ghcr.io/<your-account>/<your-repo> TAG=<git-sha>   # 拉指定版本並啟動
make down   ENV=<dev|qas|prod>                                                        # 停止
```

> 刻意只有這一條部署路徑：在主機上從原始碼 build 會破壞「dev 測過的就是上 prod 的那顆」。
> 開發機請用 `make dev`。

流程、rollback、主機設定與 troubleshooting 見 [docs/deployment.md](docs/deployment.md)。

## Structure

```
.
├── backend/                    # FastAPI + uv（多階段：dev 含測試工具、runtime 出貨非 root）
│   ├── app/main.py             # /health、/api/message（回傳目前環境）
│   ├── app/config.py           # pydantic-settings：從環境變數讀設定
│   ├── app/observability.py    # structlog：log 同一格式寫 stdout；Request ID 與 request log 的 middleware
│   ├── tests/  ·  pyproject.toml · uv.lock  ·  Dockerfile
├── frontend/                   # React + Vite（node→nginx 多階段）
│   ├── src/App.jsx  ·  nginx.conf（供靜態檔 + 反向代理 /api + 產生 Request ID）
│   ├── package.json · package-lock.json  ·  Dockerfile
├── compose.yaml                # base：只定義服務與內部接線（不決定對外曝露）
├── compose.dev.yaml            # 本機開發覆寫：開 localhost 埠 + 後端 hot reload + console log（唯一可偏離部署行為的檔案）
├── compose.deploy.yaml         # 部署覆寫：frontend 綁主機的 HTTP_PORT + log 輪替（10m × 3）
├── .env.example                # 設定變數清單（進版控）；make dev 會複製成 .env.local
├── Makefile                    # dev / test·lint·format / deploy·down / ps·logs
├── CONTEXT.md                  # 術語表（唯一定義處）
├── .github/workflows/
│   ├── ci-cd.yml               # PR 跑測試；merge→build :sha（部署由人在主機上執行）
│   └── cleanup.yml             # 每週清理舊 image
└── docs/                       # development.md · deployment.md
```
