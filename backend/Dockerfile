FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS base
WORKDIR /app
COPY pyproject.toml uv.lock ./
ENV PATH="/app/.venv/bin:$PATH"

# dev:測試用(pytest、ruff),永不部署;「dev stage」與「APP_ENV=dev 環境」是兩個維度
FROM base AS dev
RUN uv sync --frozen
COPY app ./app
COPY tests ./tests
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]

# runtime:出貨用,三環境共用同一顆。必須留在最後:CI build 與 compose base 都沒指定 target,
# Docker 建「最後一個」stage,調換順序會把含測試工具的 dev image 推上 production
FROM base AS runtime
RUN uv sync --frozen --no-dev
COPY app ./app
RUN useradd --create-home --uid 1000 appuser
USER appuser
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
