# Deployment

CI/CD 流程與目標主機(VM)上的部署操作。

## 全流程(trunk-based, build once promote many)

```
本機開發 → make local 驗證 → feature branch → PR 合進 main(CI:test)
    → 打 Release tag:git tag v0.1.0 && git push origin v0.1.0
    → CI:test → build(推 :v0.1.0 到 GHCR)
    → VM:make deploy ENV=<env> TAG=v0.1.0 拉指定版本啟動
```

三個環境跑的是**同一顆 image**,環境差異只在主機上 `.env.<env>` 的設定(12-factor)。
只有 Release(`vX.Y.Z` tag)會 build image,tag 原樣就是 image tag;PR 與 main 只跑測試,
其他形狀的 tag(`latest`、`wip`)不觸發 CI。

image 同時含 **amd64 與 arm64**(arm64 那半在 CI 上用 QEMU 模擬 build,慢幾分鐘,只在 Release 時付這個時間),
`docker pull` 會自動挑主機的架構。

backend 的 runtime stage 要到打 tag 才會被 build(PR 與 main 只 build dev stage 跑測試):
改了 `backend/Dockerfile` 或相依,打 tag 前在本機跑一次 `docker compose build` 確認。

## 在 VM 上部署

前置:VM 是 Linux(amd64 或 arm64 都可以;Apple Silicon 的 Mac 也拉得到,可以拿來試部署流程),裝好 docker + compose plugin;package 不是 public 的話,
用有 `read:packages` 權限的 PAT 登入 GHCR 一次:

```bash
echo <PAT> | docker login ghcr.io -u <你的帳號> --password-stdin
```

再 clone 這個 repo(要的只是 compose 檔,不會在 VM 上 build),並建好該環境的 `.env.<env>`(見下節)。

```bash
make deploy ENV=qas TAG=v0.1.0   # 拉該 Release 並啟動
make down ENV=qas                # 停止該環境
make ps                          # 看跑了什麼
```

`TAG` 沒有預設值,要拉哪個 Release 得寫出來。image 位置是 `Makefile` 的 `IMAGE`
(`ghcr.io/aj006600/<APP_NAME>`);repo 名與 `APP_NAME` 不同時改那一行。

**Promote** = 在下一個環境的主機帶同一個 `TAG` 再跑一次 `make deploy`,人工執行,沒有 CI job。

### Rollback

帶舊的 Release 重跑(`git tag --list 'v*'` 看有哪些):

```bash
make deploy ENV=prd TAG=v0.1.0
```

無狀態時才這麼單純:有了資料庫 migration 之後,舊版可能認不得新版的 schema 而起不來,
這時回到舊行為要發一個修正版 Release。

## Host configuration

`.env.<env>` **不進版控**(`.gitignore` 排除 `.env*`),由每台主機自己建——非機密與機密都放這裡,
compose 直接把它注入 backend。以進版控的 `.env.example` 當起點:

```bash
# 例:VM 上
cp .env.example .env.prd
$EDITOR .env.prd     # APP_ENV 改成 prd、LOG_LEVEL 改 info、設好 HTTP_PORT、填該環境的機密
```

`APP_ENV` 只影響 app 自報的環境名;載哪個檔由 `make deploy` 的 `ENV` 決定,不會因為忘了改而載錯檔。

變數名與本機 `.env` 完全一致,程式不必為環境分支。

## 對外埠

`compose.deploy.yaml` 把 frontend 綁到 `.env.<env>` 裡的 `HTTP_PORT`(建議 dev=3000、qas=3001、prd=3002,
同機並存不撞埠)。某環境獨佔一台主機時,把那台主機上的 `HTTP_PORT` 改成 80,網址就不必帶埠。

## Logs

```bash
docker logs -f fullstack-prd-backend-1    # container 名 = <APP_NAME>-<env>-<service>-1,make ps 查
```

部署的兩個 container 都設了 log 輪替(`compose.deploy.yaml`:單檔 10 MB、最多 3 檔),長期運行不會填滿磁碟。

## GitHub 前置設定(每個新專案一次)

1. **不用設任何 secret**:CI 用內建的 `GITHUB_TOKEN` 推 GHCR。
2. **GHCR 不會自動清舊版本**:只有 Release 才產生 image,量少;要清時到 GitHub 個人頁的 Packages 刪掉不要的版本。
3. **GitHub Free 的 private repo 沒有 branch protection**:「`main` 只經由 PR 進入」靠人維持
   (trunk-based:feature branch → PR → main)。
