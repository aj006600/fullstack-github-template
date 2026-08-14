# CI/CD & Release

[← README](../README.md) ｜ 觀念先修：[concepts.md](concepts.md) ｜ 詞彙：[CONTEXT.md](../CONTEXT.md)

## Development flow (trunk-based)

只有一個長期分支 `main`。所有改動走「短命 feature branch → PR → merge main」：

```bash
git checkout -b fix/xxx
# 改、commit、git push -u origin fix/xxx
gh pr create --fill
gh pr merge --squash    # CI 綠燈後 merge（沒有任何機制擋你提早按，見 What nothing enforces）
```

- PR 觸發測試；merge 到 main 才 build 出 `:sha`；打 `v*` tag 才把 `:sha` 加上版本標籤
- **部署由人在目標主機上執行**，pipeline 不連線任何主機（理由見 [One-time GitHub setup](#one-time-github-setup)）
- main 上**每個** commit 都會 build 出 `:sha`（含純文件 commit）——promote、rollback、`git bisect` 都依賴這個不變量。重複建置的成本由 build cache 吸收

### Working in parallel

多人同時從 `main` 開分支**沒有問題**：每個 PR 的 base 都是 `main`，每個都會跑 CI，而且跑的不是
你的分支本身，是 GitHub 現算的 merge commit（**你的改動 + 當下的 main**）——所以別人先 merge 了，
你也不必為了讓 CI 正確而先 rebase。

兩條紀律，都是因為沒有任何機制會提醒你（見 [What nothing enforces](#what-nothing-enforces)）：

1. **PR 的 base 永遠是 `main`。** 把 base 指到另一個 PR 的分支（stacked PR），**CI 完全不會跑**——
   `pull_request` 的 `branches: [main]` filter 比對的是 base 而非 head。分支間有依賴時，
   從上游分支繼續寫，但等它 merge 了再開 PR。
2. **綠燈會過期。** 那個勾是對「跑 CI 那一刻的 main」算的；之後別人 merge 了東西，GitHub 會重算
   merge ref 但**不重跑 CI**（`synchronize` 只在 PR 的 head 更新時觸發）。所以 PR 開著一陣子、
   期間 main 前進過的話，merge 前先把 main 併回自己的分支並 push，讓 CI 重跑一次。

## Build-once promotion

**Build 一次 → 兩個 service 各打不可變的 git SHA tag → 同一組 image promote。** 各環境跑的都是**同一組 image**（用 SHA 指定），不重 build、不靠 `latest`。

```
merge main ─▶ test ─▶ build(backend+frontend :sha) ─┐
                                                    ├─▶ 人在目標主機上 make deploy
git tag v* ─▶ test ─▶ release(:sha → :vX.Y.Z)      ─┘
```

pipeline 的職責到「建置與標籤」為止。兩個 job 的 run summary 都會把該執行的 `make deploy` 指令
連同 tag 一起印出來，直接複製到主機上跑。

Image 位置（兩個）：

```
ghcr.io/<your-account>/<your-repo>-backend:<git-sha>
ghcr.io/<your-account>/<your-repo>-frontend:<git-sha>
```

## Deploy execution: make deploy

Deployment = 在**目標主機**上「拉 CI 測過的不可變 image + `up -d`」，**不在主機重 build**（在主機重 build 會破壞 build-once 的保證）：

```bash
make deploy ENV=<dev|qas|prod> \
    IMAGE=ghcr.io/<your-account>/<your-repo> TAG=<git-sha 或 vX.Y.Z>
```

職責分工：

```
CI（自動）       ＝ 建置與標籤：測試綠燈才 build、main 每個 commit 一顆 :sha、
                   打 v* tag 才把該 :sha 標成 :vX.Y.Z
make deploy      ＝ 執行原語：在目標主機上拉指定 TAG + up。由人執行，pipeline 只印指令
```

## Release to prod (git tag)

```bash
git checkout main && git pull          # 1. 要發的 commit 已在 main、dev/qas 驗過（:sha 已 build）
git tag v1.2.0                         # 2. 打版本 tag
git push origin v1.2.0                 # 3. 推 tag → 觸發 prod 發版
```

會把測試過的 `:sha` **加上版本 tag `:v1.2.0`（不重 build）**。接著在 prod 主機上部署那個 tag
（`release` job 的 run summary 會把這行填好印出來）：

```bash
make deploy ENV=prod IMAGE=ghcr.io/<your-account>/<your-repo> TAG=v1.2.0
```

**tag 必須指向已經 build 完成的 commit。** `release` job 是把既有的 `:sha` 重新貼標籤，所以那顆映像要先存在。
merge 之後**立刻**打 tag 有可能搶在 main 的 build 完成之前（tag 與 main 是不同的 ref，concurrency 不會讓它們排隊），
此時 job 會以 `manifest unknown` 失敗。

這個失敗是**安全**的——沒有任何東西被發布。等 main 的 build 跑完，在 Actions 頁面 re-run 該 job 即可，不必重打 tag。

> 反過來說，`:sha` 存在本身就證明那個 commit 上過 main 且測試綠燈（`build` job 的前提就是這兩件事），
> 所以指向未經 CI 的 commit 的 tag 也會在這一步失敗，不會漏出去。

## Which version is running

Image 用 **git SHA** 當 tag，所以「哪個環境跑哪一版」= 「跑哪個 SHA」。

```bash
git log --oneline -10                 # 看最近的 commit 與其 SHA
git show <sha>                        # 看某個 SHA 改了什麼
git checkout <sha>                    # 切過去看該版 code（看完 git switch - 回來）
git checkout v1.0.0                   # 或用版本 tag 切到某次發版的 code

docker ps --format '{{.Image}}'       # 看正在跑的 container 用哪顆 image
```

> 「哪個環境跑哪一版」的唯一真相是主機上的 `docker ps`。pipeline 不部署，所以 GitHub 那邊沒有
> 任何部署紀錄可查——要有可信的部署歷史，得先讓 CD 真的連上主機（見 [roadmap.md](roadmap.md)）。

## Rollback

Image 不可變且都留在 registry，所以 **rollback = 重新部署上一組好的 SHA，不需重新 build**：

```bash
git log --oneline                     # 1. 找出要回到的舊 SHA

# 2. 在目標主機上把該環境部署回舊 SHA（一行）
make deploy ENV=prod \
    IMAGE=ghcr.io/<your-account>/<your-repo> TAG=<old-sha>
```

## Image cleanup

`.github/workflows/cleanup.yml` 每週跑一次——兩個 service 的 `:sha` 建置各**只留最近 20 個**、**保護 `v*` 正式版**（永不刪除，rollback 才有得回）、刪 untagged。避免 image 無限累積。

> 這個數字就是 dev/qas 的 rollback 視窗有多深（main 每個 commit 建一顆），也是 Packages 儲存
> 額度的主要旋鈕（見下方 [Billing](#billing)）。package 名由 `GITHUB_REPOSITORY` 推導，
> fork 或改名都不必改那個檔案。

## One-time GitHub setup

這個 template 假設 repo 是 **private**、方案是 **GitHub Free**。這個組合決定了哪些機制根本不存在，
先讀完再去設定，免得對著設不起來的畫面找原因。

### Why there is no deploy job

Free 方案的私有 repo **不支援 Environments**（[官方文件](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)：
私有 repo 要 GitHub Pro 或 Team 以上），連帶沒有 environment secrets，也沒有 prod 的 required reviewers。

一個既連不上主機、又拿不到核准閘門的 deploy job，留著只是每次 merge 白付一分鐘
（Actions 以 **job** 為單位無條件進位計費），所以這個 pipeline 直接沒有 deploy job——
部署指令由 `build` / `release` 的 run summary 提供，人複製到主機上跑。

閘門其實還在，只是不在 GitHub 上：打 `v*` tag 是人主動做的，`make deploy` 也是人在主機上跑的。
上 prod 本來就要經過兩個獨立的人為動作。

### Billing

| 資源 | Free 額度 | 這個 repo 的用量 |
|------|----------|----------------|
| Actions 分鐘數 | 2,000 分/月，**帳號共用**（非每 repo） | merge 到 main 約 8 分鐘（5 個 job）；每個 PR run 約 3 分鐘 |
| Packages 儲存 | 500MB | 由 `cleanup.yml` 的 `keep-n-tagged` 控制 |

分鐘數是帳號層級共用的，所以這個 template 開到第四、五個專案時就會逼近額度——「template 的成本
要乘上專案數」在這裡有了具體形態。真的撞到時最省的一刀是調低 `keep-n-tagged` 與清理頻率，
**不是**加 `paths-ignore`：那會破壞「main 每個 commit 都有 `:sha`」這個 promote / rollback / bisect
全都依賴的不變量。

> 專案若不需要保密，轉 public 是最便宜的解——兩項計費歸零，並一併拿回 Environments 與
> branch protection。

### What nothing enforces

Free + private 也拿不到 branch protection 與 rulesets——`Protected branches`、
`Required pull request reviewers` 都在 Pro 才有的清單裡
（[GitHub's plans](https://docs.github.com/en/get-started/learning-about-github/githubs-plans)）。
具體來說，這三件事**沒有任何機制在擋**：

| 應該成立的事 | 實際上誰在維持 |
|-------------|--------------|
| `main` 只經由 PR 進入 | 沒有機制——`git push origin main` 直接就進去了 |
| 綠燈才 merge | 沒有機制——CI 還在跑、甚至紅燈，merge 按鈕都是綠的 |
| 綠燈是對**當下**的 main 算的 | 沒有機制——見 [Working in parallel](#working-in-parallel) 第 2 條 |

這是**刻意接受的留白**：以這個 template 的規模（一到數人、自己的專案），付費換這三道閘門不一定划算。
但要留得明白——「main 的每個 commit 都測過」這個不變量目前**完全靠人維持**，而 build-once、
promotion、rollback 全都建立在它之上。它破掉的時候不會報錯，只會有某個 `:sha` 其實沒被測過。

要買回來就升級到 GitHub Pro，到 **Settings → Branches** 對 `main` 加規則：

- **Require a pull request before merging**（單人可把 required approvals 設 0）
- **Require status checks to pass** → 勾 `test-backend`、`build-frontend`、`check-compose`
- **Require branches to be up to date before merging** → 這條治的是上表第三列
- **Do not allow bypassing the above settings**（連 owner 也受限）

> Pro 同時讓 Environments 可用，[為什麼沒有 deploy job](#why-there-is-no-deploy-job) 的前提就變了：
> `deploy-prod` 的 required reviewers 會成為真的閘門，屆時值得把那個 job 加回來（只加 prod，
> dev/qas 仍然沒有閘門、不值得那一分鐘）。

## Side note: dual hosting on GitLab + GitHub (deferred)

CI 設定檔是**平台專屬**的，兩份可並存、各讀各的；`backend/`、`frontend/`、`compose.yaml` 完全共用：

| 平台 | CI 設定檔 |
|------|----------|
| GitHub Actions | `.github/workflows/*.yml`（現有） |
| GitLab CI | `.gitlab-ci.yml`（放根目錄，之後再加） |

真的要做時，先決定三件事（避免常見陷阱）：

1. **選一邊當真相來源**，用倉庫鏡像（mirror）自動同步另一邊——避免兩邊各自 push 造成分岔。
2. **避免兩邊都跑 CI／都部署**（除非故意，例如各部署到不同雲）。
3. **Secrets 與 registry 各平台各設**（GHCR vs GitLab Container Registry）。
