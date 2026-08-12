# 執行期的名字都從這行流出去：compose project 名、本機 image 名、proxy router 名、DOMAIN。
# 但 README 標題、頁面 title、pyproject description 沒有插值能力，是寫死的——改這行動不到，
# 要 make init 才會一起換。
APP_NAME := fullstack

DEV := -f compose.yaml -f compose.dev.yaml

# 註解不可寫在同一行：Make 會把 # 之前的空白一起吃進變數值
EXPOSE ?= ports
ENV    ?= dev

STACK   := -f compose.yaml -f deploy/compose.$(EXPOSE).yaml --env-file env/.env.$(ENV)
# APP_NAME 必須進到 compose 的插值環境：漏了只是 warning、退出碼 0，DOMAIN 會靜默變成 "dev..localhost"
PROJECT := COMPOSE_PROJECT_NAME=$(APP_NAME)-$(ENV) APP_NAME=$(APP_NAME)

# 可用值一律從檔案系統推導，不手寫清單：新增 env 檔或 deploy override 後漏改清單不會報錯，
# check 只會安靜地少驗一個組合。.local 是覆蓋層，不是一個 environment。
ENVS    := $(patsubst env/.env.%,%,$(filter-out %.local,$(wildcard env/.env.*)))
EXPOSES := $(patsubst deploy/compose.%.yaml,%,$(wildcard deploy/compose.*.yaml))
ENVS_TXT    := $(shell echo "$(ENVS)" | sed 's/ / | /g')
EXPOSES_TXT := $(shell echo "$(EXPOSES)" | sed 's/ / | /g')

# 打錯 EXPOSE/ENV 時給明確訊息，而不是 compose 的 "no such file" 或靜靜載入到別的環境。
# 比對推導出的清單而非 test -f：否則 ENV=dev.local 這種 check 從不驗證的組合會過關。
guard = @test -n "$(filter $(EXPOSE),$(EXPOSES))" || { echo "EXPOSE=$(EXPOSE) 無效。可用：$(EXPOSES_TXT)"; exit 1; }; \
	test -n "$(filter $(ENV),$(ENVS))" || { echo "ENV=$(ENV) 無效。可用：$(ENVS_TXT)"; exit 1; }

.PHONY: help init dev dev-down test lint format check down deploy ps

help:
	@echo "Setup（從 template 開新專案時做一次）"
	@echo "  make init APP_NAME=my-app         把專案改名成你的，並移除這個 target 自己"
	@echo ""
	@echo "Development（在你的開發機上）"
	@echo "  make dev                          hot reload、localhost:3000 / :8000（前景執行）"
	@echo "  make dev-down                     停止並清理 make dev 的 container 與 network"
	@echo "  make test | lint | format         跑在 dev stage 容器裡（CI 走 runner，共用 uv.lock）"
	@echo "  make check                        驗證部署設定（不啟動容器，幾秒）"
	@echo ""
	@echo "Deployment（在目標主機上）"
	@echo "  make deploy  EXPOSE=… ENV=… IMAGE=… TAG=…   拉 CI 測過的映像，不重 build"
	@echo "  make down    EXPOSE=… ENV=…                 停止該環境"
	@echo ""
	@echo "  EXPOSE = $(EXPOSES_TXT)      怎麼對外曝露：綁主機埠 / 掛共用 reverse proxy   (預設 $(EXPOSE))"
	@echo "  ENV    = $(ENVS_TXT)                                                 (預設 $(ENV))"
	@echo ""
	@echo "Inspection"
	@echo "  make ps                           正在跑的 container（名稱 / 狀態 / 埠）"

# >>> init（make init 會刪掉這整段，不要移除這兩行標記）
# ── Project init（一次性）──
# 對 git 追蹤的檔案全跑，不維護檔案清單——之後新增的檔案自動涵蓋，不會靜默漏改。
# 兩條規則的順序不能反：先換長的，否則 "fullstack-github-template" 會先被短規則
# 切成 "my-app-github-template"。
# 長規則寫死 template 名：repo 改名時漏改這裡不會報錯，只會在新專案裡留下舊名。
# /i 不分大小寫：展示用的 "Fullstack Multi-env"（頁面 title、<h1>、pyproject description）
# 只比對小寫會漏掉。
# perl 而非 sed：BSD 要 -i ''、GNU 要 -i，語法不相容；perl -pi 兩邊一致且都內建。
# 要求工作區乾淨：這會改十幾個檔案，保住「反悔就 git checkout .」這條退路。
init:
	@test "$(APP_NAME)" != "fullstack" || { echo "用法：make init APP_NAME=my-app"; exit 1; }
	@echo "$(APP_NAME)" | grep -qE '^[a-z][a-z0-9-]*$$' || { echo "APP_NAME 只能是小寫英數與連字號、開頭為字母——它會用在 image 名、compose project 名與 domain。"; exit 1; }
	@git diff --quiet && git diff --cached --quiet || { echo "工作區有未提交的改動。請先 commit 或 stash——init 會改動多個檔案，乾淨的工作區才能用 git checkout . 還原。"; exit 1; }
	@git ls-files -z | xargs -0 perl -pi -e 's/fullstack-github-template/$(APP_NAME)/gi; s/fullstack/$(APP_NAME)/gi'
	@rm -rf CLAUDE.md CONTEXT.md docs/agents docs/adr docs/cicd.md docs/concepts.md docs/roadmap.md
	@perl -0777 -pi -e 's/^# >>> init.*?^# <<< init.*?\n\n//ms' Makefile
	@perl -0777 -pi -e 's/^\t\@echo "Setup.*?\n\t\@echo ""\n//ms; s/^\.PHONY: help init /.PHONY: help /m' Makefile
	@printf '# $(APP_NAME)\n\n- 本機開發：[docs/development.md](docs/development.md)\n- 部署：[docs/deployment.md](docs/deployment.md)\n' > README.md
	@echo "已更名為 $(APP_NAME)，並移除 init target、agent 設定檔與 template 專用文檔。"
	@echo "請 git diff 檢查後 commit。"
# <<< init

# ── Development ──
dev:
	APP_ENV=dev APP_NAME=$(APP_NAME) docker compose $(DEV) up --build

dev-down:
	docker compose $(DEV) down

# ── Tests and quality ──
# 跑在 dev stage 容器裡；CI 直接在 runner 上用 uv，兩邊只共用 uv.lock（省 CI 分鐘數）。
# 代價：dev stage 從沒被 CI 建過，它壞掉時 CI 全綠，要本機 make dev 才會發現。
#
# --build：pyproject / uv.lock 烤在 image 裡（掛載只蓋 app/ 與 tests/），不重建會用到舊設定。
# --user：dev stage 以 root 跑，ruff format 會把掛載的檔案寫成 root 所有，Linux 上之後編輯不了
#         （macOS 的 Docker Desktop 會轉譯所有權，看不出問題）。
# 快取改到 /tmp：換成你的 uid 後，寫不進映像裡 root 擁有的 /app。
RUNDEV = docker compose $(DEV) run --build --rm \
	--user $(shell id -u):$(shell id -g) \
	-e RUFF_CACHE_DIR=/tmp/.ruff_cache \
	-e PYTEST_ADDOPTS="-p no:cacheprovider" \
	backend

test:
	$(RUNDEV) pytest

lint:
	$(RUNDEV) ruff check .

format:
	$(RUNDEV) ruff format .

# ── Config check ──
# 渲染每種 EXPOSE × ENV（不啟動容器），只驗兩件「錯了不會當場報錯」的事：
#   1. 各 environment 的 HTTP_PORT 互異——撞埠要到部署當下才炸。
#   2. 沒有未解析的變數——漏傳 APP_NAME 會讓 DOMAIN 變成 "dev..localhost"，而 compose
#      只給 warning、退出碼 0。
# 刻意不斷言 project 名與 router 名：它們是 $(APP_NAME)-$(ENV) 串接出來的，測了等於測串接。
# 先擋清單為空：否則 sed 會讀 stdin 卡住，而 for 迴圈跑零次卻報綠燈。
check:
	@test -n "$(ENVS)" && test -n "$(EXPOSES)" || { \
	  echo "FAIL: 找不到 env/.env.* 或 deploy/compose.*.yaml"; exit 1; }
	@dup=$$(sed 's/#.*//' $(addprefix env/.env.,$(ENVS)) | grep '^HTTP_PORT=' | tr -d ' ' | sort | uniq -d); \
	test -z "$$dup" || { \
	  echo "FAIL: 多個 environment 用了同一個 HTTP_PORT，同機並存時會撞埠："; \
	  echo "  $$dup"; exit 1; }
	@fail=0; \
	for e in $(EXPOSES); do for v in $(ENVS); do \
	  out=$$(COMPOSE_PROJECT_NAME=$(APP_NAME)-$$v APP_NAME=$(APP_NAME) docker compose \
	         -f compose.yaml -f deploy/compose.$$e.yaml --env-file env/.env.$$v config 2>&1); \
	  if [ $$? -ne 0 ]; then \
	    echo "FAIL $$e/$$v: compose config 失敗"; echo "$$out" | tail -3; fail=1; \
	  elif echo "$$out" | grep -q 'variable is not set'; then \
	    echo "FAIL $$e/$$v: 有未解析的變數"; \
	    echo "$$out" | grep -oE 'The [^ ]+ variable is not set' | sort -u | sed 's/^/  /'; fail=1; \
	  else \
	    echo "ok   $$e/$$v"; \
	  fi; \
	done; done; \
	test $$fail -eq 0

# ── Deployment ──
# 刻意沒有「本機 build 後部署」的 target：在主機上重 build 會破壞「dev 測過的就是上 prod 的那顆」。
deploy:
	$(guard)
	@test -n "$(IMAGE)" && test -n "$(TAG)" || { echo "需要 IMAGE 與 TAG，例：make deploy EXPOSE=proxy ENV=dev IMAGE=ghcr.io/<帳號>/<repo> TAG=<sha>"; exit 1; }
	IMAGE=$(IMAGE) TAG=$(TAG) $(PROJECT) docker compose $(STACK) pull
	IMAGE=$(IMAGE) TAG=$(TAG) $(PROJECT) docker compose $(STACK) up -d --no-build

down:
	$(guard)
	$(PROJECT) docker compose $(STACK) down

ps:
	docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
