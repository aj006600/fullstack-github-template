# CI/CD and Deployment

[← README](../README.md) ｜ 詞彙：[CONTEXT.md](../CONTEXT.md)

## Flow (trunk-based, build once promote many)

只有一個長期分支 `main`，所有改動走「短命 feature branch → PR → merge main」：

```
feature branch → PR（CI：test-backend、build-frontend）
  → merge main（CI：再測一次 + build backend/frontend 的 :sha 推到 GHCR）
  → 人在目標主機上 make deploy ENV=<env> IMAGE=… TAG=<sha>
```

- main 上**每個** commit 都會 build 出 `:sha`（含純文件 commit）——promotion、rollback 都靠這個不變量，
  所以 CI 不設 `paths-ignore`，重複建置的成本由 build cache 吸收。
- pipeline 不連線任何主機。`build` job 的 run summary 會印出填好 sha 的 `make deploy` 指令，複製到主機上跑。
- 三個 environment 跑的是**同一顆** `:sha`，差別只在主機上的 `.env.<env>`。promotion = 帶 qas 驗過的 sha
  到 prod 主機再跑一次 `make deploy`。

> GitHub Free 的 private repo 沒有 branch protection：「`main` 只經由 PR 進入」與「綠燈才 merge」
> 都沒有機制擋，靠人維持。

Image 位置：

```
ghcr.io/<your-account>/<your-repo>-backend:<git-sha>
ghcr.io/<your-account>/<your-repo>-frontend:<git-sha>
```

**Image cleanup**：`.github/workflows/cleanup.yml` 每週一跑一次，兩個 service 各只留最近 20 個 `:sha`、
刪 untagged。這個數字就是**所有環境（含 prod）**能 rollback 回多舊：prod 停在某顆 sha 期間 main 前進超過
20 個 commit，那顆 sha 會被清（正在跑的 container 不受影響，但無法再從 registry 部署）。不夠用時調大
`keep-n-tagged`。

## Deploy on a host

每台主機的一次性前置：

1. **amd64 Linux**，裝好 docker 與 compose plugin。CI 只建 amd64——Apple Silicon 上 `make deploy` 會失敗
   （`no matching manifest for linux/arm64`），開發機請用 `make dev`。
2. **clone 這個 repo**——要的只是 compose 檔與 Makefile，不會在主機上 build。
3. **登入 GHCR**（package 不是 public 的話）：
   ```bash
   echo <PAT> | docker login ghcr.io -u <你的帳號> --password-stdin   # PAT 需要 read:packages
   ```
   沒登入的話 `make deploy` 會停在 `pull`，錯誤訊息是 `denied` 或 `unauthorized`。
4. **建該環境的 `.env.<env>`**（見下方 [Host configuration](#host-configuration)）。

```bash
make deploy ENV=qas IMAGE=ghcr.io/<your-account>/<your-repo> TAG=<git-sha>
make down   ENV=qas      # 停止該環境
make ps                  # 看跑了什麼
```

**Rollback** = 帶舊的 sha 重跑 `make deploy`，不需重新 build（`git log --oneline` 找 sha）。
無狀態時才這麼單純：有了資料庫 schema 之後，程式碼回得去，migration 過的資料回不去。

> 「哪個環境跑哪一版」的唯一真相是主機上 `docker ps` 的 image tag——pipeline 不部署，GitHub 上沒有部署紀錄。

## Host configuration

`.env.<env>` **不進版控**（`.gitignore` 排除 `.env*`），由每台主機自己建——非機密與機密都放這裡，
compose 直接把它注入 backend。以進版控的 `.env.example` 當起點：

```bash
cp .env.example .env.prod
$EDITOR .env.prod     # APP_ENV 改成 prod、LOG_LEVEL 改 info、設好 HTTP_PORT、填該環境的機密
```

`APP_ENV` 只影響 app 自報的環境名；載哪個檔由 `make deploy` 的 `ENV` 決定，不會因為忘了改而載錯檔。

| 變數 | 值 | 說明 |
|------|----|------|
| `HTTP_PORT` | 例：dev 3000、qas 3001、prod 3002 | frontend 對外埠，**必填**（漏填 `make deploy` 直接失敗） |
| `LOG_LEVEL` | `debug` ｜ `info` ｜ `warning` ｜ `error`（小寫） | 對 app 與 uvicorn 都生效；打錯字或大寫時 container 啟動就失敗，不會靜默退回預設值 |
| `LOG_FORMAT` | 預設 `json`，**env 檔不寫** | 部署一律一行一筆 JSON 到 stdout；`console` 只給 `make dev`，由 `compose.dev.yaml` 覆寫 |

---

## How it is exposed

frontend 綁到主機的 `HTTP_PORT`。三個 environment 同機並存時各用不同的埠（撞埠的話 `make deploy`
會報 `port is already allocated`，見下方 Troubleshooting）：

```bash
make deploy ENV=dev  IMAGE=ghcr.io/<your-account>/<your-repo> TAG=<git-sha>   # http://<host>:3000
make deploy ENV=qas  IMAGE=… TAG=…                                            # http://<host>:3001
make deploy ENV=prod IMAGE=… TAG=<在 qas 驗過的 git-sha>                       # http://<host>:3002
```

每個 environment 是**獨立的 compose project**（`fullstack-dev` / `fullstack-qas` / `fullstack-prod`，
各自獨立的 network 與 container），dev 的前端只連 dev 的後端，互不干擾。

**獨佔主機**：把該主機上 `.env.<env>` 的 `HTTP_PORT` 改成 `80`，網址就是 `http://<host>`。
同機並存時沒有故障與安全隔離——prod 若重要，讓它獨佔一台主機。

**改埠**：改 `.env.<env>` 的 `HTTP_PORT`，再重跑 `make deploy ENV=<env> …`
（env 檔是主機上的本機檔案，不在映像裡，改完不需要重新 build）。

> 要 domain 導流或 TLS？在前面加一層 reverse proxy（Traefik / Caddy / nginx）是那台主機的事，
> 不在本 repo 的範圍。

---

## Reading logs

```bash
make logs ENV=<dev|qas|prod>                    # tail 該 environment 的 backend + frontend
make logs ENV=<dev|qas|prod> SERVICE=backend    # 只看單一服務（backend | frontend）
make logs ENV=<dev|qas|prod> TAIL=all           # 從頭回看（預設只回看最後 100 行再 follow）
```

它帶上 project 名與 env 檔，等同 `docker compose -p fullstack-<env> -f compose.yaml -f compose.deploy.yaml --env-file .env.<env> logs -f --tail=100`——
手打時漏掉 `-p` 會看到別的環境（或什麼都看不到），`ENV` 打錯字會得到與 `make deploy` 相同的錯誤訊息。

backend 的每一行 log 都是一筆 JSON（`LOG_FORMAT` 預設 `json`，見上方 [Host configuration](#host-configuration)）：

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
接集中式 log 平台（Loki 或 hosted 服務），不是把上限調大。

---

## Troubleshooting

### `Bind for 0.0.0.0:<port> failed: port is already allocated`

```bash
lsof -nP -iTCP:<port> -sTCP:LISTEN      # 看什麼程式占用
docker ps --filter publish=<port>        # 或看是哪個 container
```

解法：停掉占用者，或改 `.env.<env>` 的 `HTTP_PORT` 再重跑。

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
