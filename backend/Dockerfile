# syntax=docker/dockerfile:1

# pin uv to the version used for local development, so uv.lock resolves identically
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

# fixed IDs above the ranges distros allocate, so they can't collide with a node's users;
# the name is kept so --chown and `ls -l` still read as "app"
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=builder --chown=app:app /app/.venv ./.venv
COPY --from=builder --chown=app:app /app/app ./app
COPY --from=builder --chown=app:app /app/alembic ./alembic
COPY --from=builder --chown=app:app /app/alembic.ini ./

ENV PATH="/app/.venv/bin:$PATH"

# the commit this image was built from, passed in by CI (deploy-dev.yml); "unknown" for
# any other build. An ARG only exists during the build, so ENV carries it into the
# running container, where the app reads it for /api/version. Declared down here because
# ARGs are per stage, and because the value changes on every build: only the cheap
# metadata-only layers below it miss the cache
ARG GIT_SHA=unknown
ENV GIT_SHA=${GIT_SHA}
# the standard OCI label for the source commit: readable from the registry without
# running the image
LABEL org.opencontainers.image.revision=${GIT_SHA}

# numeric, not "app": Kubernetes' runAsNonRoot can only verify a numeric user from the
# image config (it never reads the image's /etc/passwd); the group is explicit so it isn't
# looked up, and can't fall back to GID 0 (root's group)
USER 10001:10001

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
