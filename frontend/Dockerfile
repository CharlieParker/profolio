# syntax=docker/dockerfile:1

FROM node:22-bookworm-slim@sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5 AS builder

WORKDIR /app

# pins the exact pnpm version from package.json's "packageManager" field
RUN corepack enable && corepack prepare pnpm@12.4.2 --activate

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build


# nginxinc/nginx-unprivileged already listens on 8080 (not 80) and owns its pid/cache
# dirs as a non-root user (uid 101, "nginx") — no USER/EXPOSE override needed
FROM nginxinc/nginx-unprivileged:1.27-alpine@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0 AS final

LABEL org.opencontainers.image.source=https://github.com/CharlieParker/profolio

COPY --from=builder /app/dist/ /usr/share/nginx/html/
# the image's entrypoint renders /etc/nginx/templates/*.template into conf.d at start,
# substituting env vars — so the backend address is set per environment, not at build
ENV BACKEND_URL=http://backend:8000
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
