# fullstack-github-template

前後端分離 + 多環境(dev / qas / prd)的 GitHub 容器範本:React(Vite) 前端 + FastAPI 後端,
以 docker compose 編排,GitHub Actions 遵循 trunk-based +「build 一次、依序 promote」。

> 核心原則(12-factor):**一份程式碼、一組 image、設定隨環境變**。設定契約一律是環境變數:
> 本機讀 `.env`(從 `.env.example` 複製,不進版控),目標主機讀自備的 `.env.<env>`。

## Docs

| 想做的事 | 看這份 |
|----------|--------|
| **本機開發**(quickstart、hot reload、測試、清理、worktree) | [docs/development.md](docs/development.md) |
| **CI/CD 與部署**(Release、promote、rollback、機密、GitHub 設定) | [docs/deployment.md](docs/deployment.md) |

## Make it yours

從這個 template 開新專案:

1. **建 repo 並 clone**——GitHub 上按 **Use this template**,clone 下來。新 repo 的 Actions 預設啟用,不用設定。
2. **改名**——在 repo 根目錄執行,`<your-app>` 換成你的專案名(小寫英數與連字號;repo 名用同一個,
   `Makefile` 的 `IMAGE` 才對得上 CI 推的位置):
   ```bash
   NAME=<your-app>
   git ls-files -z | xargs -0 perl -pi -e "s/fullstack-github-template/$NAME/g; s/fullstack/$NAME/g"
   ```
3. **加自己的設定變數**:`.env.example` 是變數清單(進版控),新增變數先加在這裡;本機實際讀的 `.env` 由 `make local` 自動建立,不必手動處理。
4. **換上自己的 README**——`rm README.md` 後為專案寫專屬的。
5. **commit、push**。第一次出貨:`git tag v0.1.0 && git push origin v0.1.0`,見 [docs/deployment.md](docs/deployment.md)。

> 這個 template repo 本身**停用了 GitHub Actions**:`.github/workflows/` 是給開出來的新專案用的,
> 改 template 時在本機跑 `make test`、`make lint` 驗證。

## Structure

```
.
├── backend/                # FastAPI + uv(多階段:dev 含測試工具、runtime 出貨非 root)
│   ├── app/main.py         # /health、/api/message(回傳目前環境)
│   ├── app/config.py       # pydantic-settings:從環境變數讀設定
│   ├── app/logging_setup.py # log 格式與層級(LOG_LEVEL)
│   └── tests/ · pyproject.toml · uv.lock · Dockerfile
├── frontend/               # React + Vite(node→nginx 多階段)
│   ├── src/App.jsx · nginx.conf(供靜態檔 + 反向代理 /api)
│   └── package.json · package-lock.json · Dockerfile
├── compose.yaml            # base:只定義服務與內部接線
├── compose.local.yaml        # 本機開發覆寫:開 localhost 埠 + 後端 hot reload
├── compose.deploy.yaml     # 部署覆寫:frontend 綁主機 HTTP_PORT + log 輪替
├── .env.example            # 本機設定範本(進版控);make local 會複製成 .env
├── Makefile                # dev / test·lint·format / clean / deploy·down / ps / worktree
├── .github/workflows/ci-cd.yml  # test → Release tag(vX.Y.Z)才 build 推 GHCR
└── docs/                   # development.md · deployment.md
```
