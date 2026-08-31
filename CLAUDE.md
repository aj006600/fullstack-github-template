# fullstack-github-template

## Conventions

- **Commit 前先跑 `make lint`**。CI 也會把關(ruff check + format --check),本機先跑省一輪紅燈。
- **Commit message**:輕量 Conventional Commits,英文——`<type>: <description>`,type 取 `feat/fix/docs/test/refactor/chore`,scope 選用(`feat(api): ...` 也可)。
- **PR 標題與內文**:英文,**不用 emoji**(commit message 同樣不用)。標題即 Conventional Commit(squash 後成為 main 的 commit)。body 只有兩節:`## Summary`(為什麼+做了什麼,1-3 個 bullet)、`## Testing`(怎麼驗證的)——**十行內**,不重述 diff,審計報告與過程敘事留在對話與 commit message。
- **文件語言**:章節標題英文(`## Quick Start`)、內文繁體中文、技術術語保留英文(fixture、endpoint 不翻譯)。
- **文檔同步**:user-facing 變更(指令、架構、安裝步驟)在**同一個 PR** 內同步 README/docs——文檔更新是變更的一部分,不是事後待辦。
- **程式碼註釋**:繁體中文(術語英文),**不用 emoji**。只寫 code 讀不出來的**約束、陷阱、非顯然理由**(why not what);不敘述下一行做什麼;概念解說住 `docs/`,註釋需要時用一行連結指向,不重述。
- **Log**:structured——事件名 `名詞.動詞`、欄位 key=value,用專案既有 logger 不用 `print`。等級:`debug` 只給開發者、`info` 業務動作完成、`warning` 異常已自行處理、`error` 需人介入且帶 exception。不記 secrets/PII;例外只在最外層記一次。
- **規則提議**:同類糾正或卡關**第二次**發生(或一次但代價高:不可逆操作、部署事故級),主動提議把教訓寫進來——先展示擬新增的那一行與觸發原因,我同意才寫。歸位優先序:能用工具強制的進工具/CI → 綁定單檔的進該檔註釋 → 概念進 `docs/` → 決策進 `docs/adr/` → 都不是且每個 session 都適用,才進 CLAUDE.md。
- **測試品質**:單元測試目錄鏡射 `app/` 模組結構;fixture 先用 conftest 既有的,重複自建即違規;測試名稱與 docstring 必須與實際行為一致;每個測試驗證一個真實行為——斷言偶然字串(使用者可見的契約訊息除外)、恆真斷言、與既有測試重複覆蓋的,一律刪除。
- **技術調研**:用到不熟悉或版本敏感的 API/框架時,**先查證再寫**——context7 查 library 文檔、WebSearch/WebFetch 查一手來源、`gh search` 找官方範例與成熟專案;大題目啟用 `/research`(背景 agent、只認一手來源、產出帶引用的 Markdown 進 repo)。外部資訊一律**驗證(實測或對照官方文檔)後才採用**。

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues in this repo, managed with the `gh` CLI.
See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each label string equal to its name.
See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` at the repo root, ADRs under `docs/adr/`.
See `docs/agents/domain.md`.
