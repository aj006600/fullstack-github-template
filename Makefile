# 專案名:compose project 名與本機 image 名都從這裡來(README 的改名指令會一起換)
APP_NAME := fullstack

# CI 推到 ghcr.io/<owner>/<repo>:repo 名與 APP_NAME 不同時改這行
IMAGE ?= ghcr.io/aj006600/$(APP_NAME)

LOCAL := -f compose.yaml -f compose.local.yaml
# shell 裡殘留的 COMPOSE_PROJECT_NAME 會蓋掉「project 名取目錄名」:所有 worktree 擠進同一組 container,
# worktree-rm 也收不到正確的那組。一律不帶給 compose(deploy / down 在 recipe 裡自己明寫)
unexport COMPOSE_PROJECT_NAME

# 本機 build 的 image tag 帶 checkout 目錄名:多個 worktree 同時 make local / make test 才不會搶同一個名字、
# 跑到別人的程式碼。container 與 network 本來就各自分開(compose project 名取目錄名)
LOCAL_TAG := local-$(notdir $(CURDIR))

# 專案 label 只寫在 Dockerfile,這裡解析:make clean 以它劃定範圍,刪不到別的專案的東西
PROJECT_LABEL := $(shell sed -n 's/^LABEL *\(org\.opencontainers\.image\.title=[^ ]*\).*/\1/p' $(wildcard */Dockerfile) | tr -d '"' | sort -u)

# 註解勿寫同行:Make 會把 # 前的空白吃進變數值
ENV ?= dev

ENVS    := dev qas prd
# 由主機自備、不進版控。同一個變數同時餵 compose 插值(HTTP_PORT)與 backend 的 env_file,
# 兩邊不可能指到不同檔案。
ENV_FILE := .env.$(ENV)
STACK   := -f compose.yaml -f compose.deploy.yaml --env-file $(ENV_FILE)
PROJECT := COMPOSE_PROJECT_NAME=$(APP_NAME)-$(ENV) APP_NAME=$(APP_NAME) ENV_FILE=$(ENV_FILE)

guard = @test -n "$(filter $(ENV),$(ENVS))" || { echo "ENV=$(ENV) 無效。可用:dev | qas | prd"; exit 1; }
# TAG 不給預設值:要拉哪個 Release 得寫出來
guard-tag = @test -n "$(TAG)" || { echo "TAG 必填。例:make deploy ENV=$(ENV) TAG=v1.2.0"; exit 1; }

.PHONY: help local local-down compose test lint format deploy down ps clean worktree worktree-rm

help:
	@echo "Local(在你的開發機上)"
	@echo "  make local                        hot reload、localhost:3000 / :8000(前景執行;撞埠時 PORT / FRONTEND_PORT 從 shell 換)"
	@echo "  make local-down                   停止並清理 make local 的 container 與 network"
	@echo "  make compose ARGS=\"...\"           對 make local 那組 container 下任何 compose 子命令(logs -f backend、exec backend sh …)"
	@echo "  make test [ARGS=\"...\"]           pytest,跑在 backend dev stage 容器裡(與 CI 同一套環境);ARGS 只跑一部分,例 ARGS=\"tests/test_main.py\" 或 ARGS=\"-k health\""
	@echo "  make lint | format                ruff check / ruff format(就地改檔)"
	@echo "  make clean                        回收本專案的 container / volume / network、image 與 build cache"
	@echo ""
	@echo "Deployment(在目標主機上,需自備 .env.<env>)"
	@echo "  make deploy ENV=<dev|qas|prd> TAG=<vX.Y.Z> 拉該 Release 並啟動(不重 build,TAG 必填)"
	@echo "  make down   ENV=<env>                      停止該環境"
	@echo ""
	@echo "Inspection"
	@echo "  make ps                           正在跑的 container(名稱 / 狀態 / 埠)"
	@echo ""
	@echo "Worktrees(一個 issue 一個,從主 checkout 跑)"
	@echo "  make worktree ISSUE=<n> BRANCH=<feat/slug>   開在 .claude/worktrees/<app>-issue-<n>,並複製 .env"
	@echo "  make worktree-rm ISSUE=<n>                   刪掉該 worktree 與本地 branch(有未 commit 或未 push 的就拒絕)"

# ── Local ──
# .env 不進版控:乾淨 clone 首次跑起來不必先手動建檔
.env:
	cp .env.example $@

# 這些 target 都會讓 compose 解析 backend 的 env_file(= .env),缺檔就直接報錯
local local-down compose test lint format: .env

local:
	APP_NAME=$(APP_NAME) TAG=$(LOCAL_TAG) docker compose $(LOCAL) up --build

local-down:
	docker compose $(LOCAL) down

# 帶同一組 -f 與 TAG:手打 docker compose 少了 TAG 會 build 成 :latest,跟 make local 用的不是同一顆 image
compose:
	APP_NAME=$(APP_NAME) TAG=$(LOCAL_TAG) docker compose $(LOCAL) $(ARGS)

# ── Tests and quality ──
# 與 CI test-backend 同一顆 dev stage image。--build:pyproject / uv.lock 烤在 image 裡,不重建會用舊設定。
# --user + 快取改 /tmp:root 跑 ruff format 會把掛載檔寫成 root 所有(Linux 上之後編輯不了),
# 換成你的 uid 後又寫不進 root 擁有的 /app。
RUNDEV = TAG=$(LOCAL_TAG) docker compose $(LOCAL) run --build --rm \
	--user $(shell id -u):$(shell id -g) \
	-e RUFF_CACHE_DIR=/tmp/.ruff_cache \
	-e PYTEST_ADDOPTS="-p no:cacheprovider" \
	backend

# ARGS 原樣交給 pytest:開發中只跑跟改動相關的那幾個,完整套交給 CI(docs/development.md 的 Testing workflow)
test:
	$(RUNDEV) pytest $(ARGS)

lint:
	$(RUNDEV) ruff check .

format:
	$(RUNDEV) ruff format .

# ── Cleanup ──
# 何時該跑:docs/development.md 的 Cleanup 一節。刻意不用 docker system prune:會掃到別的專案。
# ENV_FILE 指向進版控的 .env.example:清理不該因為缺 .env 而失敗,也不該為了清理生一個檔出來。
# label 解析不出唯一值時擋下:空值會讓 --filter label= 掃到全機的 dangling image
# builder prune 一定要在刪 image 之後:本專案的 build cache 這時才沒有 image 在用,會被回收;
# 別的專案同樣沒人用的 cache 也會一起丟,它們下次 build 慢一點,不會壞
clean:
	@[ $(words $(PROJECT_LABEL)) = 1 ] || { echo "*/Dockerfile 的 image.title LABEL 解析不出唯一值:'$(PROJECT_LABEL)'" >&2; exit 1; }
	ENV_FILE=.env.example docker compose $(LOCAL) down --volumes --remove-orphans
	docker image ls --filter label=$(PROJECT_LABEL) --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>' | xargs -r docker image rm
	docker image prune -f --filter label=$(PROJECT_LABEL)
	docker builder prune --force

# ── Deployment ──
# 刻意沒有「本機 build 後部署」的 target:在主機上重 build 會破壞「dev 測過的就是上 prod 的那顆」。
deploy:
	$(guard)
	$(guard-tag)
	IMAGE=$(IMAGE) TAG=$(TAG) $(PROJECT) docker compose $(STACK) pull
	IMAGE=$(IMAGE) TAG=$(TAG) $(PROJECT) docker compose $(STACK) up -d --no-build

down:
	$(guard)
	$(PROJECT) docker compose $(STACK) down

ps:
	docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# ── Worktrees ──
# 一個 issue 一個 worktree,開在 .claude/worktrees/<APP_NAME>-issue-<n>(與 Claude Code 的 worktree 同一處,已在 .gitignore)。
# 目錄名帶 APP_NAME:compose project 名取目錄名,只叫 issue-<n> 的話,兩個專案同號 issue 的 container 會撞在一起
WORKTREE = .claude/worktrees/$(APP_NAME)-issue-$(ISSUE)

# --no-track 不能省:從 origin/main 開的 branch 預設以 origin/main 為 upstream,不帶 refspec 的 push 可能推進 main。
# origin 已有該 branch 就接著它開。.env 從主 checkout 複製:機密才跟得過去(make local 自動建的只有範例值)
worktree:
	@[ -n "$(ISSUE)" ] && [ -n "$(BRANCH)" ] || { echo "用法:make worktree ISSUE=<n> BRANCH=<feat/slug>" >&2; exit 1; }
	git fetch origin
	if git rev-parse --verify -q refs/remotes/origin/$(BRANCH) >/dev/null; then \
		git worktree add $(WORKTREE) $(BRANCH); \
	else \
		git worktree add --no-track -b $(BRANCH) $(WORKTREE) origin/main; \
	fi
	@[ ! -f .env ] || cp .env $(WORKTREE)/.env

# 要從主 checkout 跑:刪的若是自己的 cwd,之後的指令都會失效。
# 未 push 以「不在任何 origin ref 上」判斷:剛開還沒 commit 的、已 merge 且 origin branch 已刪的都算乾淨。
# 最後連該 worktree 的 compose project 一起收,不留 container 與 network
worktree-rm:
	@[ -n "$(ISSUE)" ] || { echo "用法:make worktree-rm ISSUE=<n>(從主 checkout 跑)" >&2; exit 1; }
	@[ -d $(WORKTREE) ] || { echo "找不到 $(WORKTREE);要從主 checkout 跑" >&2; exit 1; }
	@branch=$$(git -C $(WORKTREE) symbolic-ref --short HEAD) || exit 1; \
	if [ -n "$$(git -C $(WORKTREE) status --porcelain)" ]; then \
		echo "$(WORKTREE) 有未 commit 的改動,先 commit 並 push(或丟棄)再刪:" >&2; \
		git -C $(WORKTREE) status --short >&2; exit 1; \
	fi; \
	unpushed=$$(git rev-list --oneline $$branch --not --remotes=origin); \
	if [ -n "$$unpushed" ]; then \
		echo "$$branch 有 origin 上沒有的 commit,先 push 再刪:" >&2; \
		echo "$$unpushed" >&2; exit 1; \
	fi; \
	ENV_FILE=.env.example docker compose -p $(notdir $(WORKTREE)) $(LOCAL) down --remove-orphans && \
	git worktree remove $(WORKTREE) && git branch -D $$branch
