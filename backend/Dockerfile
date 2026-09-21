# syntax=docker/dockerfile:1

# pinned to match local `uv --version` (0.12.15)
FROM ghcr.io/astral-sh/uv:0.12.15@sha256:62f8c047d0a0e9ece6b53fc63df902585a67a47a7f318ddec4a37db586edc8e3 AS uv

FROM python:3.12-slim-bookworm@sha256:782412e85d0f0984994c290652577d4018aff08145c85b262bb63dc0c7522254 AS builder

COPY --from=uv /uv /uvx /usr/local/bin/

WORKDIR /app

# copy mode avoids uv's default hardlinking, which doesn't survive across Docker layers;
# compiling bytecode up front trades a slightly slower build for a faster cold start
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

# dependencies first, app code after — this layer only rebuilds when the lockfile changes
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY app/ ./app/
COPY alembic/ ./alembic/
COPY alembic.ini ./


# same base (and digest) as the builder, so glibc/library versions match exactly
FROM python:3.12-slim-bookworm@sha256:782412e85d0f0984994c290652577d4018aff08145c85b262bb63dc0c7522254 AS final

LABEL org.opencontainers.image.source=https://github.com/charlieparker/profolio

RUN groupadd --system app \
    && useradd --system --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=builder --chown=app:app /app/.venv ./.venv
COPY --from=builder --chown=app:app /app/app ./app
COPY --from=builder --chown=app:app /app/alembic ./alembic
COPY --from=builder --chown=app:app /app/alembic.ini ./

ENV PATH="/app/.venv/bin:$PATH"

USER app

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
