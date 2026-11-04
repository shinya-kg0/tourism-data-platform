# Cloud Run Job「dbt」のイメージ（仕様書 7.5）
# 実行のたびに外部からパッケージを取りに行かないよう、dbt deps はイメージを作るときに済ませる
FROM ghcr.io/astral-sh/uv:0.9-python3.12-bookworm-slim

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    PYTHONUNBUFFERED=1 \
    PATH=/app/.venv/bin:$PATH \
    DBT_PROFILES_DIR=/app \
    DBT_SEND_ANONYMOUS_USAGE_STATS=false \
    DBT_TARGET_PATH=/tmp/dbt/target \
    DBT_LOG_PATH=/tmp/dbt/logs

WORKDIR /app

COPY pyproject.toml uv.lock ./
# uv のダウンロードキャッシュはイメージに残さない（キャッシュマウント）
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev

COPY packages.yml package-lock.yml dbt_project.yml ./
RUN dbt deps && rm -rf /tmp/dbt

COPY . .

USER nobody
ENTRYPOINT ["dbt"]
CMD ["build", "--target", "prod"]
