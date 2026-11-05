# 執行期的名字都從這行流出去：compose project 名、本機 image 名。
# README 標題、頁面 title 沒有插值能力，是寫死的——開新專案時用 README「Make it yours」的指令一起換。
APP_NAME := fullstack

DEV := -f compose.yaml -f compose.dev.yaml

# 註解不可寫在同一行：Make 會把 # 之前的空白一起吃進變數值
ENV ?= dev

ENVS := dev qas prod
# 由主機自備、不進版控。同一個變數同時餵 compose 插值（HTTP_PORT）與 backend 的 env_file，
# 兩邊不可能指到不同檔案。
ENV_FILE := .env.$(ENV)
STACK    := -f compose.yaml -f compose.deploy.yaml --env-file $(ENV_FILE)
PROJECT  := COMPOSE_PROJECT_NAME=$(APP_NAME)-$(ENV) APP_NAME=$(APP_NAME) ENV_FILE=$(ENV_FILE)

# 打錯 ENV 時給明確訊息，而不是 compose 的 "no such file"
guard = @test -n "$(filter $(ENV),$(ENVS))" || { echo "ENV=$(ENV) 無效。可用：$(ENVS)"; exit 1; }

.PHONY: help dev dev-down test lint format down deploy ps logs

help:
	@echo "Development（在你的開發機上）"
	@echo "  make dev                          hot reload、localhost:3000 / :8000（前景執行）"
	@echo "  make dev-down                     停止並清理 make dev 的 container 與 network"
	@echo "  make test | lint | format         跑在 dev stage 容器裡（CI 走 runner，共用 uv.lock）"
	@echo ""
	@echo "Deployment（在目標主機上，需自備 .env.<env>）"
	@echo "  make deploy  ENV=… IMAGE=… TAG=…  拉 CI 測過的映像，不重 build"
	@echo "  make down    ENV=…                停止該環境"
	@echo ""
	@echo "  ENV = dev | qas | prod            （預設 $(ENV)）"
	@echo ""
	@echo "Inspection"
	@echo "  make ps                           正在跑的 container（名稱 / 狀態 / 埠）"
	@echo "  make logs    ENV=… [SERVICE=…]    tail 該環境的 log（SERVICE = backend | frontend，預設兩者；TAIL=all 回看全部）"

# ── Development ──
# .env.local 不進版控：乾淨 clone 首次跑起來不必先手動建檔
.env.local:
	cp .env.example $@

# 這些 target 都會讓 compose 解析 backend 的 env_file（= .env.local），缺檔就直接報錯
dev dev-down test lint format: .env.local

dev:
	APP_NAME=$(APP_NAME) docker compose $(DEV) up --build

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
# LOG_FORMAT=json：測試斷言 stdout 上的 JSON 行，而 run 會繼承 compose.dev.yaml 給 make dev 的 console 覆寫。
RUNDEV = docker compose $(DEV) run --build --rm \
	--user $(shell id -u):$(shell id -g) \
	-e RUFF_CACHE_DIR=/tmp/.ruff_cache \
	-e PYTEST_ADDOPTS="-p no:cacheprovider" \
	-e LOG_FORMAT=json \
	backend

test:
	$(RUNDEV) pytest

lint:
	$(RUNDEV) ruff check .

format:
	$(RUNDEV) ruff format .

# ── Deployment ──
# 刻意沒有「本機 build 後部署」的 target：在主機上重 build 會破壞「dev 測過的就是上 prod 的那顆」。
deploy:
	$(guard)
	@test -n "$(IMAGE)" && test -n "$(TAG)" || { echo "需要 IMAGE 與 TAG，例：make deploy ENV=dev IMAGE=ghcr.io/<帳號>/<repo> TAG=<sha>"; exit 1; }
	IMAGE=$(IMAGE) TAG=$(TAG) $(PROJECT) docker compose $(STACK) pull
	IMAGE=$(IMAGE) TAG=$(TAG) $(PROJECT) docker compose $(STACK) up -d --no-build

down:
	$(guard)
	$(PROJECT) docker compose $(STACK) down

ps:
	docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# 帶 project 名與 env 檔：手打會漏掉 -p 而看到別的環境（或什麼都看不到）。
# SERVICE 留空時 compose 顯示 stack 內全部服務。
# TAIL=all 給「拿 Request ID 撈某次請求」用：預設只回看 100 行，較早的請求會安靜地撈不到。
TAIL ?= 100
logs:
	$(guard)
	$(PROJECT) docker compose $(STACK) logs -f --tail=$(TAIL) $(SERVICE)
