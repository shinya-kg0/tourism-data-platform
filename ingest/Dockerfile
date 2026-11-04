# Cloud Run Job「ingest」のイメージ（仕様書 5.6）
# 引数（オブジェクト名・世代番号）は Workflows が実行のたびに上書きして渡す
FROM ghcr.io/astral-sh/uv:0.9-python3.12-bookworm-slim

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    PYTHONUNBUFFERED=1 \
    HEADER_DEFS_DIR=/app/header_defs

WORKDIR /app

# 依存ライブラリだけを先に入れ、コードの変更でキャッシュが無効にならないようにする。
# uv のダウンロードキャッシュはイメージに残さない（キャッシュマウント）
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev --no-install-project

COPY src ./src
COPY header_defs ./header_defs
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev --no-editable

USER nobody
ENTRYPOINT ["/app/.venv/bin/ingest"]
