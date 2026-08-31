# fullstack-github-template

前後端分離 + 多環境（dev / qas / prod）的容器範本：React(Vite) 前端 + FastAPI 後端，
用 docker compose 兜起來，CI/CD 遵循「build 一次、依序 promote」的業界最佳實踐。

> 核心原則（12-factor）：**一份程式碼、一組 image、設定隨環境變**。絕不複製程式碼，環境差異只在設定。

## Docs

| 想做的事 | 看這份 |
|----------|--------|
| **搞懂核心觀念**（一顆 image 多環境、build vs registry、本機 vs CI/CD） | [docs/concepts.md](docs/concepts.md) |
| **本機開發**（quickstart、hot reload、docker exec、查看跑了什麼） | [docs/development.md](docs/development.md) |
| **部署**（多環境同機並存、怎麼連上、troubleshooting） | [docs/deployment.md](docs/deployment.md) |
| **CI/CD 與發版**（promotion、rollback、GitHub 設定、image 清理） | [docs/cicd.md](docs/cicd.md) |
| **上 production 前還要加什麼**（Secrets/TLS/DB/健康檢查…） | [docs/roadmap.md](docs/roadmap.md) |
| **術語**（`dev` 的三個意思、up vs deploy…） | [CONTEXT.md](CONTEXT.md) |

## Make it yours

從這個 template 開了新 repo 之後，先跑一次：

```bash
make init APP_NAME=my-app
```

它會把 template 的名字換成 `my-app`——container 與 network 名、本機 build 的 image 名，
以及 README 標題、頁面 title 這些沒有插值能力的地方。
同時移除 `make init` 自己，以及只服務於「蓋這個 template」的東西——`CLAUDE.md`、`docs/agents/`、
`CONTEXT.md`、`docs/{concepts,cicd,roadmap}.md`、`docs/adr/`，並把這份 README 換成指向 `docs/` 的骨架
（`docs/development.md` 與 `docs/deployment.md` 留著）。

> 需要乾淨的工作區——它會改動十幾個檔案，這樣你隨時可以 `git checkout .` 反悔。
> 跑完 `git diff` 檢查一遍再 commit。

這是**單向**的：跑完之後你的專案與這個 template 永久分岔，上游日後的修正不會流過來。
理由與代價見 [ADR-0001](docs/adr/0001-one-way-fork-from-template.md)。

## Quickstart

> 需要 **Docker Compose 2.24+**（`env_file` 的 `required: false` 疊加語法，機密設定靠它）。
> `docker compose version` 確認；太舊的話錯誤訊息是 `env_file.1 must be a string`。

```bash
make dev       # 前後端起來，後端 hot reload（前景執行）
# 前端 → http://localhost:3000（會顯示 backend 回傳的環境）
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

部署在**目標主機**（amd64 Linux）上執行，拉 CI 測過的不可變映像，不重 build：

```bash
make deploy ENV=<dev|qas|prod> IMAGE=… TAG=…   # 拉指定版本並啟動
make down   ENV=<dev|qas|prod>                 # 停止
```

> 刻意只有這一條部署路徑：在主機上從原始碼 build 會破壞「dev 測過的就是上 prod 的那顆」。
> 開發機請用 `make dev`。

frontend 綁到主機的 `HTTP_PORT`（各 environment 不同埠，可同機並存）。
怎麼連上、troubleshooting 見 [docs/deployment.md](docs/deployment.md)。

## Structure

```
.
├── backend/                    # FastAPI + uv（多階段：dev 含測試工具、runtime 出貨非 root）
│   ├── app/main.py             # /health、/api/message（回傳目前環境）
│   ├── app/config.py           # pydantic-settings：從環境變數讀設定
│   ├── app/observability.py    # structlog：log 同一格式寫 stdout；Request ID 與 request log 的 middleware
│   ├── tests/  ·  pyproject.toml · uv.lock  ·  Dockerfile
├── frontend/                   # React + Vite（node→nginx 多階段）
│   ├── src/App.jsx  ·  nginx.conf（供靜態檔 + 反向代理 /api）
│   ├── package.json · package-lock.json  ·  Dockerfile
├── compose.yaml                # base：只定義服務與內部接線（不決定對外曝露）
├── compose.dev.yaml            # 本機開發覆寫：開 localhost 埠 + 後端 hot reload + console log（唯一可偏離部署行為的檔案）
├── compose.deploy.yaml         # 部署覆寫：frontend 綁主機的 HTTP_PORT + log 輪替（10m × 3）
├── env/{.env.dev,.env.qas,.env.prod}   # 各環境的非機密設定（機密走同名 .local，不進版控）
├── Makefile                    # init / dev / test·lint·format·check / deploy·down / ps·logs
├── CONTEXT.md                  # 術語表（唯一定義處）
├── .github/
│   ├── workflows/
│   │   ├── ci-cd.yml           # merge→build :sha（部署由人在主機上執行）
│   │   └── cleanup.yml         # 每週清理舊 image
│   └── dependabot.yml          # 每週開 PR 更新相依（後端 uv、前端 npm、Actions）
└── docs/                       # 詳細文檔（見上方 Docs）
```
