# Deployment

[← README](../README.md)

部署 = 在某台主機上讓某個 environment 跑起來。一個旋鈕：

| 旋鈕 | 決定什麼 | 值 |
|------|---------|----|
| `ENV` | **Environment**——載入哪份設定 | `dev` ｜ `qas` ｜ `prod` |

部署在**目標主機**上執行，拉 CI 測過的不可變映像，不重 build：

```bash
make deploy ENV=<dev|qas|prod> IMAGE=… TAG=…   # 拉指定版本並啟動
make down   ENV=<dev|qas|prod>                 # 停止
```

`TAG` 是該 commit 的 git SHA；rollback 就換回舊的 sha——無狀態時才這麼單純：
一旦有了資料庫 schema，程式碼回得去，migration 過的資料回不去。

> **主機必須是 amd64 Linux。** CI 只建 amd64——在 Apple Silicon 的開發機上 `make deploy` 會失敗
> （`no matching manifest for linux/arm64`）。開發機請用 `make dev`。

## Common steps

### 1. Create your repo from this template

GitHub 上按「Use this template」（或 clone 本 repo），改成你的 app。

### 2. Configure each environment

每個 environment 的設定分兩層：

| 檔案 | 進版控 | 放什麼 |
|------|-------|-------|
| `env/.env.<env>` | 是 | **非機密**：`APP_ENV`、`LOG_LEVEL`、`HTTP_PORT` |
| `env/.env.<env>.local` | **否**（`.gitignore` 擋掉） | **機密**：DB 連線字串、API key。每台主機自己建 |

`.local` 疊在前者之上，**同名變數以 `.local` 為準**；沒有 `.local` 的機器照常啟動。

| 變數 | 值 | 說明 |
|------|----|------|
| `LOG_LEVEL` | `debug` ｜ `info` ｜ `warning` ｜ `error`（小寫） | 對 app 與 uvicorn 都生效；打錯字或大寫時 container 啟動就失敗，不會靜默退回預設值 |
| `LOG_FORMAT` | 預設 `json`，**env 檔不寫** | 部署一律一行一筆 JSON 到 stdout；`console` 只給 `make dev`，由 `compose.dev.yaml` 覆寫 |

三個 environment 的 log 設定只差 `LOG_LEVEL`，格式一致。

```bash
# 在目標主機上，例如 prod
cat > env/.env.prod.local <<'EOF'
DATABASE_URL=postgresql://...
EOF
```

> `.local` 只注入 **container 內的環境變數**，不參與 compose 檔自身的插值——`HTTP_PORT`
> 走 Makefile 的 `--env-file`，寫進 `.local` 不會生效。它本來也不是機密。

### 3. Push and let CI build

`make deploy` 拉的是 registry 裡的映像，所以要先 merge 到 `main`、讓 CI 建出該 commit 的 `:sha`。
之後在主機上帶那個 sha 部署。

### 4. Log in to the registry

GHCR 的 package 預設跟著 repo 的可見性走，而這個 template 假設 repo 是 private，所以 package 也是——
目標主機要先登入**一次**（這是主機的 bootstrap，不是每次部署的參數）。
（repo 若是 public，package 也會是 public，這步可以跳過。）

```bash
echo <PAT> | docker login ghcr.io -u <你的帳號> --password-stdin
```

PAT 需要 `read:packages` 權限。沒登入的話 `make deploy` 會停在 `pull` 這步，錯誤訊息是
`denied` 或 `unauthorized`。

> 之後 CD 真的連上主機時同樣要處理這件事。

---

## How it is exposed

frontend 綁到主機的 `HTTP_PORT`。三個 environment 同機並存時各用不同的埠：

| Environment | `HTTP_PORT`（在 `env/.env.*`） | 網址 |
|------|------------------------------|------|
| dev  | 3000 | `http://<host>:3000` |
| qas  | 3001 | `http://<host>:3001` |
| prod | 3002 | `http://<host>:3002` |

同機並存時三個埠**必須不同**（`make check` 會驗）。

```bash
make deploy ENV=dev  IMAGE=ghcr.io/<your-account>/<your-repo> TAG=<git-sha>
make deploy ENV=qas  IMAGE=… TAG=…
make deploy ENV=prod IMAGE=… TAG=<在 qas 驗過的 git-sha>
make ps              # 看狀態
```

每個 environment 是**獨立的 compose project**（`fullstack-dev` / `fullstack-qas` / `fullstack-prod`，
各自獨立的 network 與 container），dev 的前端只連 dev 的後端，互不干擾。

**連上**：

- 你自己：`http://localhost:3000` / `:3001` / `:3002`
- 團隊（同網路）：`http://<你的機器IP>:3000` 等——不需要 domain，直接 IP:port
  ```bash
  ipconfig getifaddr "$(route get default | awk '/interface:/{print $2}')"   # macOS
  hostname -I | awk '{print $1}'                                            # Linux
  ```

**獨佔主機**：把該主機上 `env/.env.<env>` 的 `HTTP_PORT` 改成 `80`，網址就是 `http://<host>`。
同機並存時沒有故障與安全隔離——prod 若重要，讓它獨佔一台主機。

**改埠**：改 `env/.env.<env>` 的 `HTTP_PORT`，再重跑 `make deploy ENV=<env> …`。
（env 檔是主機上的本機檔案，不在映像裡，所以改完不需要重新 build。）

> 要 domain 導流或 TLS？在前面加一層 reverse proxy 是那台主機的事，不在本 repo 的範圍
> （見 [roadmap.md](roadmap.md)）。

---

## Reading logs

```bash
make logs ENV=<dev|qas|prod>                    # tail 該 environment 的 backend + frontend
make logs ENV=<dev|qas|prod> SERVICE=backend    # 只看單一服務（backend | frontend）
make logs ENV=<dev|qas|prod> TAIL=all           # 從頭回看（預設只回看最後 100 行再 follow）
```

它帶上 project 名與 env 檔，等同 `docker compose -p fullstack-<env> -f compose.yaml -f compose.deploy.yaml --env-file env/.env.<env> logs -f --tail=100`——
手打時漏掉 `-p` 會看到別的環境（或什麼都看不到），`ENV` 打錯字會得到與 `make deploy` 相同的錯誤訊息。

backend 的每一行 log 都是一筆 JSON（`LOG_FORMAT` 預設 `json`，見上方 [Configure each environment](#2-configure-each-environment)）：

```json
{"event": "Application startup complete.", "logger": "uvicorn.error", "level": "info", "timestamp": "2026-08-31T05:39:46.104734Z"}
```

可直接接 `jq`，例如只看 warning 以上：

```bash
make logs ENV=prod SERVICE=backend 2>&1 | grep -o '{.*}' | jq -c 'select(.level != "info")'
```

frontend（nginx）維持 nginx 原生的文字格式 access log，只在**行尾多一欄 Request ID**：

```
172.18.0.1 - - [31/Aug/2026:11:41:09 +0000] "GET /api/message HTTP/1.1" 200 48 "-" "Mozilla/5.0 ..." "-" 5e42513496b80c57139a820ce1fe16ef
```

同一個 id 也在 backend 該次請求每一行 log 的 `request_id` 欄位，以及回給瀏覽器的 `X-Request-ID` header——
用法見下方 [Troubleshooting](#a-user-reports-that-something-failed)，詞條定義見 [CONTEXT.md](../CONTEXT.md#observability)。

**輪替**：部署的兩個 container 都用 `json-file` driver、單檔 10 MB、最多 3 檔（`compose.deploy.yaml`），
每個 container 的 log 上限 **30 MB**，超過就丟最舊的——長期運行不會填滿磁碟。需要更長的保存期，
接集中式 log 平台（見 [roadmap.md](roadmap.md)），不是把上限調大。

---

## Troubleshooting

### `Bind for 0.0.0.0:<port> failed: port is already allocated`

```bash
lsof -nP -iTCP:<port> -sTCP:LISTEN      # 看什麼程式占用
docker ps --filter publish=<port>        # 或看是哪個 container
```

解法：停掉占用者，或改 `env/.env.<env>` 的 `HTTP_PORT` 再重跑。

### A user reports that something failed

請使用者開 devtools → Network → 點那個失敗的 `/api/*` 請求 → Response Headers，抄下 `X-Request-ID`。
每個 `/api/*` 請求都有：它由 nginx 在第一跳產生，連 backend 沒回應時 nginx 自己回的 502 也帶。
拿到 id 後在主機上：

```bash
make logs ENV=<env> TAIL=all 2>&1 | grep <id>     # 該次請求在兩個 container 的所有 log；Ctrl+C 結束
```

同一個 id 出現在兩層，**哪一層有它**就說明錯在哪：

| 使用者看到 | frontend access log | backend log | 意思 |
|-----------|--------------------|-------------|------|
| **502** | 有（status 502） | **通常沒有** | 請求沒到 backend——nginx 連不上它：container 掛了、還在啟動、或剛重建。看 `make ps` 的狀態與 `make logs ENV=<env> SERVICE=backend` 最後幾行（啟動失敗的 traceback 在那裡） |
| **500** | 有（status 500） | 有 | backend 收到了但炸了——同一 id 的那幾行裡有 `request.completed`（`status_code=500`）與 traceback |
| 其他 4xx/5xx | 有 | 有 | backend 自己回的錯誤；看該 id 的 `request.completed` 與其前後的 app log |

> 使用者若沒抄 id，退而求其次用時間：access log 的 `[時間]` 與 backend log 的 `timestamp` 都是 UTC。
