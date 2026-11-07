# 專案名:compose project 名與本機 image 名都從這裡來(README 的改名指令會一起換)
APP_NAME := fullstack

# CI 推到 ghcr.io/<owner>/<repo>:repo 名與 APP_NAME 不同時改這行
IMAGE ?= ghcr.io/aj006600/$(APP_NAME)

DEV := -f compose.yaml -f compose.dev.yaml

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

.PHONY: help dev dev-down test lint format deploy down ps

help:
	@echo "Development(在你的開發機上)"
	@echo "  make dev                          hot reload、localhost:3000 / :8000(前景執行)"
	@echo "  make dev-down                     停止並清理 make dev 的 container 與 network"
	@echo "  make test | lint | format         跑在 backend dev stage 容器裡(與 CI 同一套環境)"
	@echo ""
	@echo "Deployment(在目標主機上,需自備 .env.<env>)"
	@echo "  make deploy ENV=<dev|qas|prd> TAG=<vX.Y.Z> 拉該 Release 並啟動(不重 build,TAG 必填)"
	@echo "  make down   ENV=<env>                      停止該環境"
	@echo ""
	@echo "Inspection"
	@echo "  make ps                           正在跑的 container(名稱 / 狀態 / 埠)"

# ── Development ──
# .env.local 不進版控:乾淨 clone 首次跑起來不必先手動建檔
.env.local:
	cp .env.example $@

# 這些 target 都會讓 compose 解析 backend 的 env_file(= .env.local),缺檔就直接報錯
dev dev-down test lint format: .env.local

dev:
	APP_NAME=$(APP_NAME) docker compose $(DEV) up --build

dev-down:
	docker compose $(DEV) down

# ── Tests and quality ──
# 與 CI test-backend 同一顆 dev stage image。--build:pyproject / uv.lock 烤在 image 裡,不重建會用舊設定。
# --user + 快取改 /tmp:root 跑 ruff format 會把掛載檔寫成 root 所有(Linux 上之後編輯不了),
# 換成你的 uid 後又寫不進 root 擁有的 /app。
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
