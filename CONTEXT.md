# Fullstack GitHub Template

Fullstack 專案模板的交付語彙:trunk-based、build once promote many,CI 在 GitHub Actions、image 在 GHCR、部署在目標主機。

## Language

**Release**:
形如 `vX.Y.Z` 的 git tag。只有 Release 會 build image,tag 原樣就是 image tag(backend、frontend 兩顆同 tag);
promote、rollback、追溯都以它為錨點。merge 到 main 只跑測試,不產生 image。
_Avoid_: version、版本號(單講分不出是 git tag 還是套件版本)

**Promote**:
把同一個 Release 帶到下一個環境:在該環境的主機帶同一個 `TAG` 再跑一次 `make deploy`,不重新 build。人工執行,沒有 CI job。
_Avoid_: release(Release 專指 tag)

**Deploy**:
在目標主機上拉某個 Release 的 image 並啟動,只拉不 build。

**local**:
開發機上 `make dev` 跑起來的那套:讀 `.env.local`,`APP_ENV=local`。不是部署環境,與部署出去的 `dev` 區分。
_Avoid_: 本機的 dev
