# vino_platform ECS Docker 部署

目标：先用一个 Docker 容器把 `vino_platform` 跑到阿里云 ECS 上，满足公网演示和小范围试运行。

## 部署形态

- 单容器：Node.js 内置 HTTP 服务。
- 持久化数据：宿主机目录挂载到 `/app/data`。
- 模型目录：宿主机目录只读挂载到 `/app/models`。
- 默认端口：`8797`。
- 健康检查：`GET /healthz` 和 `GET /readyz`。

## ECS 准备

安全组放行：

- `22/tcp`：SSH。
- `8797/tcp`：直接访问平台时放行。
- `80/tcp`、`443/tcp`：如果前面加 Nginx、宝塔或 SLB HTTPS。

安装 Docker 与 Compose：

```sh
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
docker compose version
```

## 首次启动

```sh
cd /opt
git clone <your-repo-url> vino
cd /opt/vino/vino_platform
cp .env.example .env
mkdir -p /opt/vino-platform/data /opt/vino-platform/models
```

编辑 `.env`：

```env
PORT=8797
VINO_EXTERNAL_BASE_URL=http://你的ECS公网IP:8797
VINO_DATA_DIR=/opt/vino-platform/data
VINO_MODELS_DIR=/opt/vino-platform/models
VINO_REQUEST_BODY_LIMIT=200mb
VINO_RATE_LIMIT_ENABLED=true
VINO_RATE_LIMIT_MAX=600
VINO_RATE_LIMIT_AUTH_MAX=30
VINO_TICKET_RETENTION_DAYS=30
VINO_DOWNLOAD_WORK_RETENTION_MINUTES=60
VINO_ARTIFACT_CACHE_RETENTION_DAYS=30
VINO_SESSION_TTL_DAYS=7
VINO_ARTIFACT_CACHE_ROOT=/app/data/artifact-cache
VINO_DOWNLOAD_WORK_ROOT=/app/data/download-work
VINO_BACKUP_ROOT=/app/data/backups
```

如果先用仓库自带 `models/`：

```env
VINO_MODELS_DIR=/opt/vino/models
```

公网演示环境建议至少改掉默认管理员密码：

```env
VINO_BOOTSTRAP_ADMIN_EMAIL=admin
VINO_BOOTSTRAP_ADMIN_PASSWORD=换成强密码
```

如果是公开可访问的 ECS，建议关闭演示账号注入：

```env
VINO_SEED_DEMO_DATA=false
VINO_BOOTSTRAP_ADMIN_EMAIL=admin
VINO_BOOTSTRAP_ADMIN_PASSWORD=换成强密码
```

注意：`VINO_SEED_DEMO_DATA=false` 只影响首次生成 `state.json` 或缺失的 seed 账号。已经生成过的数据不会被自动删除；如果之前已经用默认演示账号生成了数据，先备份，再通过后台禁用或删除默认账号。

启动：

```sh
docker compose run --rm --build vino-platform node scripts/deploy-check.js
docker compose up -d --build
docker compose ps
docker compose logs -f
```

验证：

```sh
curl http://127.0.0.1:8797/healthz
curl http://127.0.0.1:8797/readyz
npm run test:download
VINO_STRESS_MODEL_MB=500 npm run test:download
```

Admin ops status:

```text
GET /api/platform/v1/admin/ops/status
GET /api/platform/v1/admin/ops/doctor
```

Use it from the Web console or with an admin bearer token to inspect runtime, config risks, state file, backups, cache directories, tickets, sessions, collection counts and state integrity issues.

浏览器访问：

```text
http://你的ECS公网IP:8797/
```

## HTTPS 和域名

如果用 Nginx 反代，平台容器仍监听 `8797`，Nginx 负责 `443`。

`.env` 里必须改成最终公网地址：

```env
VINO_EXTERNAL_BASE_URL=https://platform.your-domain.com
```

否则 iPhone 拿到的模型下载地址会是内网或 HTTP 地址。

Nginx 反代要保留这些头：

```nginx
server {
    listen 80;
    server_name platform.your-domain.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name platform.your-domain.com;

    ssl_certificate /etc/nginx/cert/platform.your-domain.com.pem;
    ssl_certificate_key /etc/nginx/cert/platform.your-domain.com.key;

    client_max_body_size 250m;

    location / {
        proxy_pass http://127.0.0.1:8797;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

## 运维命令

更新：

```sh
cd /opt/vino
git pull
cd vino_platform
docker compose up -d --build
```

查看日志：

```sh
docker compose logs -f --tail=200
```

备份：

```sh
docker compose exec vino-platform node scripts/backup-state.js
docker compose exec vino-platform node scripts/doctor-state.js
docker compose exec vino-platform node scripts/maintenance.js --dry-run
docker compose exec vino-platform node scripts/maintenance.js
tar czf /opt/vino-platform-backup-$(date +%F-%H%M).tgz /opt/vino-platform/data
```

恢复：

```sh
docker compose down
docker compose run --rm -v /opt/vino-platform/data:/app/data vino-platform node scripts/restore-state.js /app/data/backups/state-YYYY-MM-DDTHH-MM-SS.json.gz
docker compose up -d
```

`restore-state.js` 会先校验备份 JSON 结构，并在覆盖 `state.json` 前写一份 `pre-restore-state-*.json.gz` 安全备份。

## 安全配置

- 密码会以 PBKDF2 hash 写入 `state.json`，旧明文密码会在服务启动读取时自动迁移。
- Web token 默认 7 天过期，可通过 `VINO_SESSION_TTL_DAYS` 调整。
- Web 退出登录会调用服务端 logout 并撤销当前 session。
- 所有 JSON 错误响应都会带 `error.requestId`，响应头也会带 `X-Request-Id`，方便按日志定位。
- 默认启用基础内存限频：每 IP 每分钟 600 次，登录口每分钟 30 次；公网前置 Nginx/SLB 后仍建议加 WAF 或安全组限源。
- 模型 artifact 会先落盘到 `VINO_ARTIFACT_CACHE_ROOT`，下载时用文件流返回；加密下载包写入 `VINO_DOWNLOAD_WORK_ROOT` 后一次性发送并清理，避免大模型下载长期占用内存。
- 公网环境不要保留默认 `admin / meiyoumima` 和 `demo123` 演示账号。

## 当前边界

- 这是单容器上线版，数据仍是 `state.json` 文件态。
- 适合演示、内测和小范围试运行，不适合高并发生产交易。
- 真正商业上线前，还要迁 PostgreSQL、对象存储、生产鉴权、审计留存和备份监控。
