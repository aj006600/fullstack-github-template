# Development

本機開發的日常操作。所有指令在 repo 根目錄執行。

## Quickstart

```bash
make local       # 前後端起來,後端 hot reload(前景執行,Ctrl+C 停止)
make local-down  # 停止並清理:container、network,以及不會再用到的舊 image 與 anonymous volume
```

乾淨 clone 不必先建任何檔案:`make local` 發現缺 `.env` 時會從 `.env.example` 複製一份。

- 前端 → http://localhost:3000(頁面會顯示 backend 回傳的環境 `local`,證明接通了)
- 後端 → http://localhost:8000/health

兩個埠只發佈到 loopback(`127.0.0.1`),同一個網路上的別台機器連不到。在遠端主機上開發時,用 SSH 或 VS Code 把埠轉接到自己的電腦。

前後端怎麼溝通:瀏覽器只打 frontend,`/api/*` 由 frontend 的 nginx 反向代理到 backend(同源、免 CORS)。

```
瀏覽器 → frontend(nginx:80) ──/api/──▶ backend(uvicorn:8000)
                          └─ 其他路徑 = SPA 靜態檔
```

## Configuration

設定一律走環境變數,本機的來源是 `.env`:

| 檔案 | 進版控 | 用途 |
|------|--------|------|
| `.env.example` | 是 | 範本:列出所有變數,非機密給可用的本機預設值,機密給 placeholder |
| `.env` | 否 | 你這台機器實際讀的值;缺檔時 `make local` 自動從 example 複製 |

變數名與部署主機上 `.env.<env>` 的一致,程式不必為環境分支。
新增變數:先加進 `.env.example`,再到自己的 `.env` 填值。

本機的 `APP_ENV` 是 **`local`**,刻意與部署出去的 `dev` 環境區分——頁面顯示 `local` 就表示你看的是本機。

## Hot reload 的範圍

`make local` 掛載 `backend/app/` 與 `backend/tests/`,改 Python 檔立即生效。
**改 `pyproject.toml` / `uv.lock` 要重跑 `make local`**(相依烤在 image 裡,掛載蓋不到)。

前端在 `make local` 下是 build 好的靜態檔,改 jsx 不會即時反映;要前端 hot reload 就直接
`cd frontend && npm install && npm run dev`(vite dev server 會把 `/api` 代理到 localhost:8000)。

## 測試與品質

```bash
make test                             # 完整套 pytest,跟 CI 一樣
make test ARGS="tests/test_main.py"   # 只跑一個檔
make test ARGS="-k health"            # 只跑名字符合的測試
make lint                             # ruff check
make format                           # ruff format(就地改檔)
```

都跑在 backend 的 dev stage 容器裡,跟 CI 的 `test-backend` job 同一顆 image——本機過了 CI 就會過。

### Testing workflow

本機跑一次、CI 再跑一次是刻意的,兩次回答的問題不同:本機答「我剛改的有沒有弄壞」,
CI 在乾淨的機器上對**合併後的結果**跑完整套,答「合進 main 能不能用」——CI 不信任本機的結果,那次不能省。
能省的是本機那次的**範圍**:

1. **開發中**只跑跟改動相關的測試,幾秒一輪。`tests/` 鏡射 `app/` 的結構,改 `app/x.py` 就跑
   `make test ARGS="tests/test_x.py"`;修一個紅的測試就 `ARGS="-k <測試名>"`。
2. **commit 前**跑 `make lint`,幾秒。
3. **push、開 PR**,CI 跑完整套,不用等它,繼續做別的;紅了再回來修。

只有改到共用的東西(相依、設定、conftest / 共用 fixture、跨多個模組)或不確定影響範圍時,才在 push 前跑一次完整的 `make test`。

## 常用檢查

```bash
make ps                                  # 正在跑的 container(名稱 / 狀態 / 埠)
make compose ARGS="logs -f backend"       # 追後端 log
make compose ARGS="exec backend sh"       # 進容器
```

`make compose` 對 `make local` 那組 container 下任何 compose 子命令,帶的是同一組 compose 檔與 image tag。

```bash
PORT=8001 FRONTEND_PORT=3001 make local   # 撞埠時換埠(只從 shell 給,不寫進 .env)
```

## Cleanup

Docker 留在機器上的東西分三層收,每一層動到的範圍不同:

| 指令 | 清什麼 | 範圍 |
|------|--------|------|
| `make local-down` | `make local` 的 container 與 network、沒名字的舊 image(`<none>`)、anonymous volume | 只有本專案 |
| `make clean` | 上面那些,加上有名字的 image 與 named volume | 只有本專案 |
| `make clean-cache` | Docker build cache | **整台機器的所有專案**,會先問過 |

```bash
make local-down    # 日常收工
make clean         # 把本專案佔的空間還回去(設定檔 .env 不會被碰)
make clean-cache   # 磁碟還是不夠時,接在 make clean 之後跑
```

**`make local-down` 留下什麼**:有名字的 image、build cache 與 named volume。前兩樣下次 `make local` 會直接重用,
起得快;named volume 是你的開發資料。

**它清掉的是不會再被用到的東西**:

| 東西 | 怎麼來的 |
|------|---------|
| 沒名字的舊 image | 重 build 同一個 tag,新 image 拿走名字,舊的變成 `<none>` 卻沒被刪 |
| anonymous volume | compose 檔裡只寫容器內路徑、沒取名字的 volume,或 image 自己宣告了資料目錄而你沒掛東西上去。container 刪掉後它還在,下次 `make local` 卻另建一個新的 |
| 沒 down 的 container | `make local` 按 Ctrl+C 只是停下來,container 與 network 都還在 |
| 改名前的 container | compose 檔裡把服務改名或拿掉,舊 container 還掛在同一個 project 名下 |

沒名字的舊 image 不必等到收工:`make local`、`make test`、`make lint`、`make format` 每次都會順手清。
`make local` 還在跑的時候跑 `make test`,被取代的那顆 image 仍有 container 在用,會留到 `make local-down` 才清。

**怎麼認出這個專案的東西**:每個 Dockerfile 都有一行專案 label(`org.opencontainers.image.title`),
build 出來的每顆 image 都帶著它,連重 build 後沒名字(`<none>`)的舊 image 也是。清 image 的指令只刪帶這個 label 的,
不比對 image 名字——`shop` 與 `shop-admin` 這種名字相近的專案才不會互刪。

**`make clean` 會刪掉 named volume 裡的開發資料**。模板本身沒有 volume;專案加了資料庫這類 named volume 之後,
`make clean` 會把它連同裡面的資料一起刪掉,之後得重新建資料。日常收工用 `make local-down`,它不碰 named volume。
`make clean` 之後的第一次 `make local` 要重新 build image。

**build cache 沒有 label**,沒辦法按專案挑,所以獨立成 `make clean-cache`。它清掉整台機器上沒有 image 在用的 cache:
先跑 `make clean` 把本專案的 image 刪掉,本專案的 cache 才會落在這個範圍內。別的專案同樣沒有 image 在用的 cache
也會一起清掉——它們下次 build 要重新下載套件,慢幾分鐘,不會壞。build cache 通常是最佔空間的一塊,磁碟告警時才需要動它。

**想確認從乾淨狀態 build 得起來**(改完 `Dockerfile` / `uv.lock` 之後)不必清任何東西,叫這一次 build 不用 cache 就好:

```bash
make compose ARGS="build --no-cache"
```

同一台機器上還有 `make deploy` 起的環境時,先 `make down ENV=<env>`:那些 image 也帶 label,
container 還在就刪不掉,`make clean` 會停在那一步。`make down` 之後再跑一次就好。

**checkout 目錄不要取名 `<app>-dev`、`<app>-qas`、`<app>-prd`**:compose project 名取目錄名,這幾個名字與
`make deploy` 起的環境相同,本機用的指令會直接動到部署中的 container 與 volume。目錄叫這些名字時,
`make local`、`make local-down`、`make compose`、`make test`、`make lint`、`make format`、`make clean` 都會拒絕執行。

## Parallel development (worktree)

一個 issue 一個 worktree,多個 worktree 可以同時開發、同時跑 `make local` / `make test`。指令都從主 checkout 跑:

```bash
make worktree ISSUE=12 BRANCH=feat/login   # 開在 .claude/worktrees/<app>-issue-12,並複製主 checkout 的 .env
cd .claude/worktrees/<app>-issue-12
make test                                  # 與其他 worktree 同時跑也不會互相干擾
PORT=8001 FRONTEND_PORT=3001 make local      # 另一個 make local 已佔用 8000 / 3000 時換埠
cd - && make worktree-rm ISSUE=12          # 收工:有未 commit 或未 push 的東西會拒絕
```

為什麼不會互相干擾:

- **container 與 network**:compose project 名取目錄名,每個 worktree 一套。
- **image**:本機 build 的 tag 帶目錄名(`<app>-backend:local-<目錄名>`),同時 build 不會搶同一個名字。
- **設定**:`.env` 從主 checkout 複製,機密跟得過去。

branch 從 `origin/main` 開且不追蹤它(`--no-track`),不帶參數的 `git push` 不會推進 main;第一次 push 寫明
`git push -u origin <branch>`。origin 上已有同名 branch 時,`make worktree` 接著它開。

`make worktree-rm` 連該 worktree 的 container、network、volume 與它 build 的 image 一起收。它只檢查程式碼有沒有 commit 與 push,
volume 裡的資料會直接刪掉:要留的資料在主 checkout 跑。

`make clean` 以專案 label 清 image,會連其他 worktree build 的一起清;正在跑的刪不掉,會停在那一步。
沒名字的舊 image 也是以專案 label 認,任何一個 checkout 清的時候,其他 worktree 留下的會一起清掉。
