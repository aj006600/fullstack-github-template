# CI/CD and Deployment

[← README](../README.md) ｜ 詞彙：[CONTEXT.md](../CONTEXT.md)

## Flow (trunk-based, build once promote many)

只有一個長期分支 `main`，所有改動走「短命 feature branch → PR → merge main」；要出貨時打 Release tag：

```
feature branch → PR（CI：test-backend、build-frontend）
  → merge main（CI：再測一次，不 build）
  → git tag v0.1.0 && git push origin v0.1.0（CI：測試 + build backend/frontend 的 :v0.1.0 推到 GHCR）
  → 人在目標主機上 make deploy ENV=<env> TAG=v0.1.0
```

- **只有 Release（`vX.Y.Z` tag）會 build image**，tag 原樣就是 image tag。其他形狀的 tag（`latest`、`wip`）
  不觸發 CI，所以 registry 上只會有正式的 Release。
- 三個 environment 跑的是**同一個** Release，差別只在主機上的 `.env.<env>`。promotion = 把 qas 驗過的
  tag 帶到 prd 主機再跑一次 `make deploy`，人工執行。
- pipeline 不連線任何主機。`build` job 的 run summary 會印出填好 tag 的 `make deploy` 指令，複製到主機上跑。
- **壞掉的 Dockerfile 要到打 tag 時才會被抓到**——PR 與 main 不 build image。改了 Dockerfile 或相依，
  打 tag 前在本機跑一次 `docker compose build`（建的就是出貨的 runtime stage）。

> GitHub Free 的 private repo 沒有 branch protection：「`main` 只經由 PR 進入」與「綠燈才 merge」
> 都沒有機制擋，靠人維持。

Image 位置（`Makefile` 的 `IMAGE` 預設指向這裡，repo 名與 `APP_NAME` 不同時改那一行）：

```
ghcr.io/<your-account>/<your-repo>-backend:<vX.Y.Z>
ghcr.io/<your-account>/<your-repo>-frontend:<vX.Y.Z>
```

GHCR 不會自動清舊版本。只有 Release 才產生 image，量很少；真的要清時，到 GitHub 個人頁的
Packages 刪掉不再需要的版本——正在跑的 container 不受影響，但那個版本就不能再部署。

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
make deploy ENV=qas TAG=v0.1.0
make down   ENV=qas      # 停止該環境
make ps                  # 看跑了什麼
```

**Rollback** = 帶舊的 Release 重跑 `make deploy`，不需重新 build（`git tag --list 'v*'` 看有哪些）。
無狀態時才這麼單純：有了資料庫 migration 之後，舊版可能認不得新版的 schema 而起不來，
這時回到舊行為要發一個修正版 Release。

> 「哪個環境跑哪一版」的唯一真相是主機上 `docker ps` 的 image tag——pipeline 不部署，GitHub 上沒有部署紀錄。

## Host configuration

`.env.<env>` **不進版控**（`.gitignore` 排除 `.env*`），由每台主機自己建——非機密與機密都放這裡，
compose 直接把它注入 backend。以進版控的 `.env.example` 當起點：

```bash
cp .env.example .env.prd
$EDITOR .env.prd      # APP_ENV 改成 prd、LOG_LEVEL 改 info、設好 HTTP_PORT、填該環境的機密
```

`APP_ENV` 只影響 app 自報的環境名；載哪個檔由 `make deploy` 的 `ENV` 決定，不會因為忘了改而載錯檔。

| 變數 | 值 | 說明 |
|------|----|------|
| `HTTP_PORT` | 例：dev 3000、qas 3001、prd 3002 | frontend 對外埠，**必填**（漏填 `make deploy` 直接失敗） |
| `LOG_LEVEL` | `debug` ｜ `info` ｜ `warning` ｜ `error`（小寫） | 對 app 與 uvicorn 都生效；打錯字或大寫時 container 啟動就失敗，不會靜默退回預設值 |
| `LOG_FORMAT` | 預設 `json`，**env 檔不寫** | 部署一律一行一筆 JSON 到 stdout；`console` 只給 `make dev`，由 `compose.dev.yaml` 覆寫 |

---

## How it is exposed

frontend 綁到主機的 `HTTP_PORT`。三個 environment 同機並存時各用不同的埠（撞埠的話 `make deploy`
會報 `port is already allocated`，見下方 Troubleshooting）：

```bash
make deploy ENV=dev TAG=v0.2.0                 # http://<host>:3000
make deploy ENV=qas TAG=v0.2.0                 # http://<host>:3001
make deploy ENV=prd TAG=<在 qas 驗過的 tag>     # http://<host>:3002
```

每個 environment 是**獨立的 compose project**（`fullstack-dev` / `fullstack-qas` / `fullstack-prd`，
各自獨立的 network 與 container），dev 的前端只連 dev 的後端，互不干擾。

**獨佔主機**：把該主機上 `.env.<env>` 的 `HTTP_PORT` 改成 `80`，網址就是 `http://<host>`。
同機並存時沒有故障與安全隔離——prd 若重要，讓它獨佔一台主機。

**改埠**：改 `.env.<env>` 的 `HTTP_PORT`，再重跑 `make deploy ENV=<env> …`
（env 檔是主機上的本機檔案，不在映像裡，改完不需要重新 build）。

> 要 domain 導流或 TLS？在前面加一層 reverse proxy（Traefik / Caddy / nginx）是那台主機的事，
> 不在本 repo 的範圍。

---

## Reading logs

```bash
make logs ENV=<dev|qas|prd>                    # tail 該 environment 的 backend + frontend
make logs ENV=<dev|qas|prd> SERVICE=backend    # 只看單一服務（backend | frontend）
make logs ENV=<dev|qas|prd> TAIL=all           # 從頭回看（預設只回看最後 100 行再 follow）
```

它帶上 project 名與 env 檔，等同 `docker compose -p fullstack-<env> -f compose.yaml -f compose.deploy.yaml --env-file .env.<env> logs -f --tail=100`——
手打時漏掉 `-p` 會看到別的環境（或什麼都看不到），`ENV` 打錯字會得到與 `make deploy` 相同的錯誤訊息。

backend 的每一行 log 都是一筆 JSON（`LOG_FORMAT` 預設 `json`，見上方 [Host configuration](#host-configuration)）：

```json
{"event": "Application startup complete.", "logger": "uvicorn.error", "level": "info", "timestamp": "2026-08-31T05:39:46.104734Z"}
```

可直接接 `jq`，例如只看 warning 以上：

```bash
make logs ENV=prd SERVICE=backend 2>&1 | grep -o '{.*}' | jq -c 'select(.level != "info")'
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
