# fullstack-github-template

這個 repo 裡容易混淆的詞（尤其 `dev`）。這份表是唯一定義處——其他文檔只連過來，不重述定義。

## Language

### Environment and configuration

**Environment**:
dev / qas / prd 三者之一，由 `make deploy` 的 `ENV` 選定。「是哪個環境」= 主機上載入了哪份 `.env.<env>`，
不是哪顆 image。本機 `make dev` 不屬於任何 environment：它讀 `.env.local`，`APP_ENV=local`。
_Avoid_: 階段、stage（`stage` 專指 Dockerfile 的建置階段）

**dev**:
依上下文有三個意思，不可混用——
`ENV=dev` 是 **environment**；`make dev` 是**本機開發指令**；Dockerfile 的 `dev` 是 **stage**。
提到後兩者時一律寫全（`make dev` / dev stage），不要單寫 dev。

**stage**:
Dockerfile 的建置階段（`base` / `dev` / `runtime`）。決定 image **內容**，與 environment 無關。
runtime stage 出貨、非 root；dev stage 含 pytest 與 ruff，只給本機用，永不部署。

### Deployment and versions

**Release**:
形如 `vX.Y.Z` 的 git tag。只有 Release 會 build image，tag 原樣就是 image tag，一次 Release 是
backend 與 frontend 兩顆同 tag 的 image。merge 到 main 只跑測試，不產生 image。
registry 上**沒有** `latest`——`compose.yaml` 的 `${TAG:-latest}` 只是本機 build 的預設標籤。
_Avoid_: 發版號、version（單講 version 分不出是 git tag 還是 package 版本）

**Deployment**:
在**目標主機**上拉某個 Release 的 image 並啟動（`make deploy`），不在主機上從原始碼 build。
_Avoid_: 部署到本機（`make dev` 是開發，不是 deployment）

**Promotion**:
把**同一個** Release 帶到下一個 environment 再跑一次 `make deploy`，不重新 build。人工執行，沒有 CI job。
_Avoid_: 重新部署、rebuild

**Rollback**:
帶先前的 Release 重跑 `make deploy`。系統無狀態時才這麼對稱——有了資料庫 migration 之後，
舊版可能認不得新版的 schema 而起不來，這時回到舊行為要發一個修正版 Release。
_Avoid_: 復原、還原（那些是資料層的事；rollback 只講 image 版本）

### Observability

**Request ID**:
一次 HTTP 請求的識別碼，由 nginx 在第一跳產生並覆蓋外部傳入值，backend 沿用、每行 log 都帶著、
以 `X-Request-ID` 回給瀏覽器。是「把某次請求的所有 log 撈出來」的唯一鍵。
_Avoid_: correlation id、trace id（trace id 是日後 OpenTelemetry 的概念，屆時再對應）

**Request log**:
每個 HTTP 請求**結束時**由 backend 發出的那一行（事件名 `request.completed`），含 status、耗時與 Request ID。
`/health` 不產生 request log。
_Avoid_: access log（那專指 nginx 的那行，以及已停用的 uvicorn 內建行）
