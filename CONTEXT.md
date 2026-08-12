# fullstack-github-template

多環境容器範本的共用詞彙。這個 repo 有幾個詞天生一詞多義（尤其 `dev`），這份表是唯一定義處——
其他文檔只連過來，不重述定義。

## Language

### Environment and configuration

**Environment**:
dev / qas / prod 三者之一。「是哪個環境」= 載入了哪份 `env/.env.<env>`，不是哪顆 image。
由 `ENV` 參數選定。
_Avoid_: 階段、stage（`stage` 專指 Dockerfile 的建置階段）

**APP_ENV**:
寫在 `env/.env.*` 裡的變數，值等於該檔對應的 environment。compose 用它解析要載入哪份 env 檔。

**dev**:
依上下文有三個意思，不可混用——
`ENV=dev` 是 **environment**；`make dev` 是**本機開發指令**；Dockerfile 的 `dev` 是 **stage**。
提到後兩者時一律寫全（`make dev` / dev stage），不要單寫 dev。

**stage**:
Dockerfile 的建置階段（`base` / `dev` / `runtime`）。決定 image **內容**，與 environment 無關。
runtime stage 出貨、非 root；dev stage 含 pytest 與 ruff，只給本機用，永不部署。

### Deployment

**Deployment**:
在**目標主機**上讓某個 environment 跑起來，用的一定是 CI 測過的 registry 映像（`make deploy`）。
在主機上從原始碼 build **不算** deployment，也刻意沒有對應的指令。
_Avoid_: preview、部署到本機（`make dev` 是開發，不是 deployment）

**EXPOSE**:
`make deploy` / `make down` 的參數，決定這個 environment 怎麼對外曝露。二選一：
`ports`（container 綁到主機的某個埠）、`proxy`（不綁埠，接上整台機器共用的 reverse proxy，
由它依 domain 導流）。對應 `deploy/compose.<值>.yaml`。

**與 Dockerfile 的 `EXPOSE` 無關**——那個是宣告 container 監聽哪個埠。同名不同義，
需要區分時說「`make` 的 `EXPOSE`」，或直接說值（`ports` / `proxy`）。

「某個 environment 獨佔一台主機」**不是第三個值**，是 `ports` 把該主機的 `HTTP_PORT` 設成 80。

`EXPOSE` 與 environment 是兩個維度，但**設定上不正交**：曝露用的參數（`ports` 用的 `HTTP_PORT`、
`proxy` 用的 `DOMAIN`）住在 environment 的 env 檔裡。這是刻意的——把它們拆到第三個地方，
只為了兩個變數多一層檔案。
_Avoid_: topology（曾經的概念名，與 `EXPOSE` 重複而移除）、mode（舊參數名 `MODE`）、部署方式

**Promotion**:
把**同一顆**已測過的 image 往下一個 environment 送，不重新 build。
本 repo 用 tag 層級的 promotion：`:sha` 給 dev/qas，發版時重新標籤成 `:vX.Y.Z` 給 prod。
_Avoid_: 重新部署、rebuild

**Rollback**:
把某個 environment 部署回**先前的 image tag**。目前是**對稱**操作——換個 `TAG` 重跑 `make deploy`
就回去了，因為系統無狀態。一旦有了資料庫 schema，rollback 就不再對稱：程式碼回得去，
migration 過的資料回不去（見 `docs/roadmap.md`）。
_Avoid_: 復原、還原（那些是資料層的事；rollback 只講 image 版本）

### Images and versions

**`:sha`**:
以 git commit SHA 為標籤的映像，由 CI 在每個 main commit 上建立。這是版本的**真相來源**——
promotion、rollback、稽核都靠它。慣例上不可變。

**latest**:
本 repo 的 registry 上**不存在** `latest`。CI 只推 `:sha` 與 `:vX.Y.Z`。
`compose.yaml` 的 `${TAG:-latest}` 是 Docker 對本機 build 的預設標籤，與 registry 無關。

**IMAGE / TAG**:
`make deploy` 的兩個必填參數，決定要拉哪顆映像。environment 不「知道」自己該跑哪一版——
版本永遠是傳入的，由 promotion 流程或人工 rollback 決定。
