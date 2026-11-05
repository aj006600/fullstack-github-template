# syntax=docker/dockerfile:1
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS base
WORKDIR /app
COPY pyproject.toml uv.lock ./
ENV PATH="/app/.venv/bin:$PATH"

# dev：含 dev 相依（pytest、ruff），只給本機用，永不部署。
# 「dev stage」與「ENV=dev 環境」是兩個維度：前者決定 image 內容，後者決定主機載入哪份 .env.<env>
FROM base AS dev
RUN uv sync --frozen
COPY app ./app
COPY tests ./tests
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]

# runtime：出貨用，dev/qas/prod 三環境共用同一顆。
# 必須留在最後：CI 的 build job 與 compose.yaml 的 base build 都沒指定 target，
# Docker 會建「最後一個」stage；調換順序會讓裝了測試工具的 dev image 被推上 production。
# （只有 compose.dev.yaml 明確指定 target: dev。）
FROM base AS runtime
RUN uv sync --frozen --no-dev
COPY app ./app
RUN useradd --create-home --uid 1000 appuser
USER appuser
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
