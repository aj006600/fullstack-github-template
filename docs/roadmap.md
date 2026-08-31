# Roadmap

這個範本刻意保持精簡——給你正確的**骨架與流程**，production 細節按你的 app 再長上去。
以下項目是**刻意留白**的（不是缺陷，是「minimal，需要再加」的範圍選擇），需要時再補。

## Known limitations

這一節與其他節不同：**不是「還沒做」，是已經決定不做**，因為它們的成本會轉嫁給每個使用這個範本的人。

- **映像只有 amd64**：CI 在 GitHub 的預設機器（amd64）上建，不做多平台建置。
  **後果：Apple Silicon 的開發機無法用 `make deploy`**（會出現 `no matching manifest for linux/arm64`）——
  開發機請用 `make dev`，部署目標請用 amd64 Linux 主機。
  之所以不補：QEMU 模擬會讓每個 fork 的人每次 merge 都多等數分鐘（即使他從不碰 arm64），
  改用原生 arm64 runner 則要多一組 build matrix 與 manifest 合併 job。
  真的要部署到 arm64 主機（AWS Graviton）時再加，改的只有 `build` job。

## Deployment

- **讓 CD 連上目標主機**：部署指令 `make deploy`（pull tested `:sha` + `up -d`）已就緒，但 pipeline
  **沒有** deploy job——Free 方案的私有 repo 拿不到 Environments，一個既不連線主機、又拿不到核准閘門的
  job 只是每次 merge 白付分鐘數（理由見 [cicd.md](cicd.md#why-there-is-no-deploy-job)）。要自動化得同時補兩件事：
  連線方式（SSH + secrets、docker context 或 self-hosted runner），以及 prod 的核准閘門——後者要先升級到 GitHub Pro。
- **改用 digest 部署**：目前用 `:sha` tag 指定版本。tag 理論上可被覆寫，digest（`@sha256:…`）不行——
  供應鏈保證要求最嚴時，部署與稽核都應記錄 digest 而非 tag。

## Common production needs

- **Secrets 送到主機的路徑**：機密本身已經有位置——`env/.env.<env>.local`，不進版控、每台主機自己建
  （見 [deployment.md](deployment.md#2-configure-each-environment)）。人工部署到此為止就夠了。
  等 CD 真的連上主機，才需要決定那個檔怎麼產生：GitHub Secrets 隨部署寫入、或改接 Vault / 雲端 secrets manager。
- **TLS / HTTPS**：目前純 HTTP。要 TLS 就在前面加一層 reverse proxy（Traefik / Caddy / nginx），
  憑證歸它管（對外真域名可自動申請 Let's Encrypt；內網用內部 CA / mkcert）——那是主機層的事，
  本 repo 不需要改動。
- **可觀測性**：**已內建**結構化 log（backend 一行一筆 JSON 到 stdout）、Request ID（定義見
  [CONTEXT.md](../CONTEXT.md#observability)）、log 輪替——用法見 [deployment.md](deployment.md#reading-logs)。**待加**：
  - **Metrics**：backend 曝露 Prometheus endpoint（請求數 / 延遲 / 錯誤率），主機層由 cAdvisor 或 node exporter 補。
  - **Tracing（OpenTelemetry）**：跨服務追蹤。加上之後 `request_id` 可對應 trace_id——log 與 trace 用同一把鍵互查，
    Request ID 的用法不變。
  - **集中式 log 平台**（Loki / hosted 服務）：兩個 container 都已把 log 寫到 stdout，接法是 docker log driver
    或主機上的 agent 收走，**app code 不用改**；保存期在那邊設，不是調大本機輪替上限。
- **安全掃描**：映像漏洞掃描（Trivy）、SBOM、映像簽章（cosign）。

## Adding a database

整個 stack 目前無狀態。要加 Postgres / Redis 時這五處都得處理——前四項是新增，第五項是
**既有保證失效**，最容易漏：

1. **`compose.yaml`**：新增 db 服務與 named volume。volume 跟著 `COMPOSE_PROJECT_NAME`
   （`<app>-<env>`）自動隔離，三個 environment 同機並存不會互相汙染資料。
2. **`env/.env.<env>.local`**：連線字串與密碼放這裡，不進版控
   （見 [deployment.md](deployment.md#2-configure-each-environment)）。
3. **Migration 的執行點**：建議放進 backend container 的 entrypoint（`alembic upgrade head`
   成功才起 uvicorn），這樣 `make deploy` 維持單一指令。拆成獨立的 compose job 會讓部署變兩步。
4. **備份**：`make down` 不帶 `-v`，停止不會刪資料——但也沒有任何東西在備份它。
5. **Rollback 不再對稱**（見 [CONTEXT.md](../CONTEXT.md) 的 Rollback 條目）：`TAG` 換回舊 sha 只把
   **程式碼**帶回去，schema 還停在新版。要維持可回滾，migration 必須**向後相容**——新增欄位可為
   NULL、不在同一版刪舊欄位、移除分兩次發版。否則 rollback 這條路等於不存在。

## Developer tooling

後端已有 ruff（lint + format，select E/F/I/UP/N/B/PT）、跑在 dev stage 容器裡的 `make test`，
與 Dependabot 週更相依（`.github/dependabot.yml`）。以下刻意延後：

- **前端品質把關**：`frontend/` **刻意**不設 lint / format / 測試——後端有 ruff（含 CI 的 `format --check`）
  與 pytest，前端 CI 只跑 `npm run build`。這個不對稱是有意識的取捨：前端目前只有一個展示用元件，
  等它長出真正的邏輯，再一次導入 eslint + vitest 比較划算（導入時記得同步 CI 與本機 `make` target）。
- **前端 build-time 設定**：目前前端沒有任何自己的設定——環境是跟 backend 要的（`/api/message`），
  所以三個 environment 共用同一顆前端映像。一旦前端需要 `VITE_*` 這類**建置時**注入的設定，
  build-once promotion 就會被打破（每個 environment 都得各建一顆）。屆時的方向是改成 **runtime 注入**
  （啟動時產生設定檔、或由 backend 提供），而不是每環境建一顆。
- **前端 TypeScript**：目前純 JS。若前端會發展成真正的 Web UI，越早轉換成本越低。
- **後端型別檢查**：目前無 mypy。code 量還小時導入 `strict` 模式最便宜。

