# syntax=docker/dockerfile:1

# TODO: pin to a real digest once resolved (see README's "Containers" section):
#   docker pull ghcr.io/astral-sh/uv:<version-matching-local `uv --version`>
#   docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/astral-sh/uv:<version>
FROM ghcr.io/astral-sh/uv:0.5 AS uv

# TODO: pin to a real digest once resolved:
#   docker pull python:3.12-slim-bookworm
#   docker inspect --format='{{index .RepoDigests 0}}' python:3.12-slim-bookworm
FROM python:3.12-slim-bookworm AS builder

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


# same base as the builder, so glibc/library versions match exactly
FROM python:3.12-slim-bookworm AS final

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
