# syntax=docker/dockerfile:1

# TODO: pin to a real digest once resolved:
#   docker pull node:22-bookworm-slim
#   docker inspect --format='{{index .RepoDigests 0}}' node:22-bookworm-slim
FROM node:22-bookworm-slim AS builder

WORKDIR /app

# pins the exact pnpm version from package.json's "packageManager" field
RUN corepack enable && corepack prepare pnpm@12.4.2 --activate

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build


# nginxinc/nginx-unprivileged already listens on 8080 (not 80) and owns its pid/cache
# dirs as a non-root user (uid 101, "nginx") — no USER/EXPOSE override needed
# TODO: pin to a real digest once resolved (check the current stable tag on pull):
#   docker pull nginxinc/nginx-unprivileged:1.27-alpine
#   docker inspect --format='{{index .RepoDigests 0}}' nginxinc/nginx-unprivileged:1.27-alpine
FROM nginxinc/nginx-unprivileged:1.27-alpine AS final

COPY --from=builder /app/dist/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf
