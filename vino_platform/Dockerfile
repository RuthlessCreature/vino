FROM node:22-alpine

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=8797 \
    VINO_DATA_ROOT=/app/data \
    VINO_MODEL_UPLOAD_ROOT=/app/data/model-builds \
    VINO_INGEST_ASSET_ROOT=/app/data/assets \
    VINO_ARTIFACT_CACHE_ROOT=/app/data/artifact-cache \
    VINO_DOWNLOAD_WORK_ROOT=/app/data/download-work \
    VINO_BACKUP_ROOT=/app/data/backups \
    VINO_MODELS_ROOT=/app/models \
    VINO_REQUEST_BODY_LIMIT=200mb \
    VINO_RATE_LIMIT_ENABLED=true \
    VINO_RATE_LIMIT_WINDOW_MS=60000 \
    VINO_RATE_LIMIT_MAX=600 \
    VINO_RATE_LIMIT_AUTH_MAX=30 \
    VINO_TICKET_RETENTION_DAYS=30 \
    VINO_DOWNLOAD_WORK_RETENTION_MINUTES=60 \
    VINO_ARTIFACT_CACHE_RETENTION_DAYS=30

WORKDIR /app

COPY vino_platform/package.json ./package.json
COPY vino_platform/server.js ./server.js
COPY vino_platform/public ./public
COPY vino_platform/scripts ./scripts

RUN mkdir -p /app/data/artifact-cache /app/data/download-work /app/data/backups /app/models \
  && chown -R node:node /app

USER node

EXPOSE 8797

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node scripts/healthcheck.js

CMD ["node", "server.js"]
