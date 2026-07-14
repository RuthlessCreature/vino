# Cloudflare + 阿里云 ECS/CDN 部署 SOP

## 0. 先给结论

如果你现在要“先上 Cloudflare”，推荐顺序是：

1. Cloudflare DNS/Proxy 先接到阿里云 ECS，作为 Web/API 入口。
2. `vino_platform` 仍跑在 ECS Docker 里，继续负责账号、设备绑定、授权、下载票据。
3. 当前模型下载先不要强行 CDN 缓存，因为现有 `/api/cloud/v1/download/:ticketId` 是短期、设备绑定、动态加密下载，缓存命中率低。
4. 真正的模型 CDN 化放下一步：模型 artifact 进对象存储，platform 只签发短期 URL。

国内用户优先级：

1. 稳定生产：阿里云 ECS + 阿里云 OSS + 阿里云 CDN。
2. 免费/低成本海外测试：Cloudflare Free + Cloudflare R2 Free tier。
3. 国内免费 CDN：不建议作为生产依赖，稳定性和合规都不可控。

## 1. Cloudflare 官方限制要点

当前判断基于 2026-07-13 官方文档：

- Cloudflare Workers Free：100,000 requests/day、10 ms CPU、128 MB memory。
- Worker 请求体上限跟 Cloudflare 账号计划有关：Free/Pro 100 MB，Business 200 MB，Enterprise 默认 500 MB。
- Worker 响应体无强制大小上限，但 CDN cache 单文件限制：Free/Pro/Business 512 MB，Enterprise 5 GB。
- R2 Free tier：10 GB-month storage、1M Class A、10M Class B、Internet egress free。
- Cloudflare China Network 需要 Enterprise plan + China Network 单独订阅 + ICP。

参考：

- Workers limits: https://developers.cloudflare.com/workers/platform/limits/
- R2 pricing: https://developers.cloudflare.com/r2/pricing/
- R2 public buckets/custom domains: https://developers.cloudflare.com/r2/buckets/public-buckets/
- Cloudflare China Network get started: https://developers.cloudflare.com/china-network/get-started/

## 2. 目标域名规划

建议至少两个域名：

| 域名 | 用途 | 当前做法 |
| --- | --- | --- |
| `api.example.com` | Web 后台 + iPhone API | Cloudflare 代理到 ECS |
| `models.example.com` | 模型文件 CDN | P1 用 R2/OSS；当前先预留 |
| `origin.example.com` | ECS 源站域名 | 可选，建议 DNS only 或仅内网/安全组可达 |

如果只有一个域名：

- `vino.example.com` 作为平台入口。
- 后续再拆 `models.vino.example.com`。

## 3. ECS 部署准备

### 3.1 安全组

打开：

- TCP 80
- TCP 443
- SSH 22 限制你的固定 IP

如果暂时不用 Nginx HTTPS，也可以开放 `8797` 测试，但生产不要直接暴露 Node 端口。

### 3.2 目录

```sh
sudo mkdir -p /opt/vino-platform/data
sudo mkdir -p /opt/vino-platform/models
sudo mkdir -p /opt/vino-platform/nginx
```

### 3.3 `.env`

在 ECS 的 `vino_platform/.env`：

```env
VINO_EXTERNAL_BASE_URL=https://api.example.com
VINO_DATA_DIR=/opt/vino-platform/data
VINO_MODELS_DIR=/opt/vino-platform/models
VINO_SEED_DEMO_DATA=false
VINO_BOOTSTRAP_ADMIN_EMAIL=admin
VINO_BOOTSTRAP_ADMIN_PASSWORD=换成强密码
VINO_REQUEST_BODY_LIMIT=200mb
VINO_SESSION_TTL_DAYS=7
```

### 3.4 启动

```sh
cd /opt/vino/vino_platform
docker compose --env-file .env up -d --build
curl http://127.0.0.1:8797/healthz
curl http://127.0.0.1:8797/readyz
```

## 4. ECS Nginx 反代

建议 Nginx 负责 TLS，Node 只监听内网端口。

`/etc/nginx/conf.d/vino-platform.conf`：

```nginx
server {
  listen 80;
  server_name api.example.com;

  client_max_body_size 200m;

  location / {
    proxy_pass http://127.0.0.1:8797;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 600s;
    proxy_send_timeout 600s;
  }
}
```

先测试：

```sh
sudo nginx -t
sudo systemctl reload nginx
curl http://api.example.com/healthz
```

生产 HTTPS 有两种：

- 方案 A：ECS 上用 Let’s Encrypt，Cloudflare SSL/TLS 选 `Full (strict)`。
- 方案 B：Cloudflare Origin Certificate 装在 ECS，Cloudflare SSL/TLS 选 `Full (strict)`。

不要用 `Flexible`，否则 origin 到 Cloudflare 之间是 HTTP，登录/下载都不合适。

## 5. Cloudflare DNS/Proxy

### 5.1 接入域名

1. Cloudflare 添加你的域名。
2. 按提示把域名 NS 改到 Cloudflare。
3. 等 DNS 生效。

### 5.2 DNS 记录

| Type | Name | Value | Proxy |
| --- | --- | --- | --- |
| A | `api` | ECS 公网 IP | Proxied |
| A | `origin` | ECS 公网 IP | DNS only |

没有源站域名也可以只配 `api`。

### 5.3 SSL/TLS

Cloudflare Dashboard：

- SSL/TLS mode: `Full (strict)`
- Always Use HTTPS: 开
- Minimum TLS: 1.2 或更高

### 5.4 Cache Rules

第一阶段建议：

1. Bypass API
   - Rule: URI Path starts with `/api/`
   - Action: Bypass cache

2. Cache static assets
   - Rule: URI Path ends with `.js`, `.css`, `.png`, `.jpg`, `.ico`
   - Action: Eligible for cache / Edge TTL 1 month

3. 不缓存动态下载 ticket
   - Rule: URI Path starts with `/api/cloud/v1/download/`
   - Action: Bypass cache

原因：当前 ticket 下载是短期动态包，CDN 缓存价值低，且不能让授权边界变复杂。

## 6. 部署 Worker

我已经放了 Worker 工程：

- `cloudflare/vino-edge-worker`

### 6.1 安装

```sh
cd cloudflare/vino-edge-worker
npm install
copy wrangler.toml.example wrangler.toml
```

编辑 `wrangler.toml`：

```toml
[vars]
ORIGIN_BASE_URL = "https://origin.example.com"
CACHE_PATH_PREFIXES = "/assets/,/cdn/,/models/"
CACHE_DOWNLOAD_TICKETS = "false"
EDGE_CACHE_TTL_SECONDS = "604800"
```

如果你没有 `origin.example.com`，也可以先写：

```toml
ORIGIN_BASE_URL = "https://api.example.com"
```

但更推荐 Worker 指向 DNS-only 源站域名，避免 Worker 反代到 Cloudflare 自己。

### 6.2 登录和部署

```sh
npx wrangler login
npx wrangler deploy
```

### 6.3 绑定 route

Cloudflare Dashboard：

- Workers & Pages
- 选择 `vino-edge-worker`
- Settings -> Triggers -> Routes
- 添加：

```txt
api.example.com/*
```

验证：

```sh
curl https://api.example.com/__edge/health
curl https://api.example.com/healthz
curl https://api.example.com/readyz
```

预期 `__edge/health` 返回：

```json
{"service":"vino-edge-worker","status":"ok","originConfigured":true}
```

## 7. iPhone 配置

打包 iPhone App 时，把默认平台地址改为：

```txt
VINO_DEFAULT_CLOUD_BASE_URL=https://api.example.com
```

当前工程已经支持：

- `Info.plist` 的 `VinoDefaultCloudBaseURL`
- `vino://provision?baseURL=https%3A%2F%2Fapi.example.com&code=...`
- 平台绑定码粘贴

上线后操作路径：

1. Web 后台登录 `https://api.example.com`
2. 进入“终端数据”
3. 生成 iPhone 绑定邀请
4. iPhone 粘贴绑定链接或绑定码
5. iPhone 自动 claim session 并同步模型清单

## 8. 模型 CDN 化 P1：Cloudflare R2 免费/低成本方案

适用：

- 海外测试
- 模型总量小于 R2 Free tier
- 对国内访问速度没有强约束

### 8.1 创建 R2 bucket

Cloudflare Dashboard：

- R2 Object Storage
- Create bucket: `vino-models`

### 8.2 上传模型 artifact

```sh
npx wrangler r2 object put vino-models/models/example.bin --file ./example.bin
```

### 8.3 绑定自定义域名

R2 bucket -> Settings -> Custom Domains：

```txt
models.example.com
```

如果模型是公开样例，可以开 Public Access。

如果模型是商业/授权模型，不要开公共 bucket。应由 platform 生成短期签名 URL 或 Worker 验证 ticket 后读取 R2。

### 8.4 需要改代码的点

当前 platform 仍是本机动态下载包。要真正使用 R2/CDN，需要下一步改：

- `modelBuild` 增加 `artifactStorageProvider`
- `modelBuild` 增加 `artifactBucket`
- `modelBuild` 增加 `artifactKey`
- `download-ticket` 返回 `models.example.com` 的短期签名 URL
- ECS 不再流式发送大模型，只签发 ticket

## 9. 模型 CDN 化 P1：阿里云 OSS + CDN 生产方案

适用：

- 用户主要在国内
- 有备案域名
- 对下载稳定性和时延有要求

### 9.1 阿里云 OSS

1. 创建 OSS bucket，例如 `vino-models-prod`
2. Region 选离用户近的位置
3. Bucket 设为私有
4. 开启服务端加密可选
5. 配置生命周期清理旧 artifact

### 9.2 阿里云 CDN

1. 添加 CDN 加速域名：`models.example.com`
2. 源站选择 OSS bucket
3. 配置 HTTPS 证书
4. 配置回源鉴权或签名 URL
5. 缓存规则：模型 artifact 按 hash/buildId 路径长缓存

### 9.3 Platform 改造

和 R2 类似，platform 不直接传大文件，只做：

- 校验 entitlement
- 创建 download ticket
- 生成 OSS/CDN signed URL
- 写 audit log
- iPhone 直接下载 CDN signed URL

## 10. 免费 CDN 方案判断

| 方案 | 是否免费 | 是否适合国内生产 | 结论 |
| --- | --- | --- | --- |
| Cloudflare Free CDN | 是 | 否，除非买 China Network | 可先上，适合海外/测试 |
| Cloudflare R2 Free tier | 小额度免费 | 否，国内不稳定 | 适合小模型/海外测试 |
| GitHub Releases + jsDelivr | 免费 | 否 | 只适合公开 demo，不适合商业模型 |
| 阿里云 CDN | 通常按量付费 | 是 | 国内生产优先 |
| 腾讯云 COS/CDN | 通常按量付费 | 是 | 国内备选 |

## 11. 当前推荐执行顺序

今天能做：

1. Cloudflare 接入域名。
2. `api.example.com` 代理 ECS。
3. `VINO_EXTERNAL_BASE_URL=https://api.example.com`。
4. 部署 `cloudflare/vino-edge-worker`。
5. iPhone 默认地址改成 `https://api.example.com`。

下一轮开发：

1. 把 model artifact 从 ECS 文件系统迁到 OSS/R2。
2. `download-ticket` 返回 CDN signed URL。
3. iPhone 下载从 CDN URL 走。
4. ECS 只保留控制面和审计。

## 12. 回滚

如果 Cloudflare 代理异常：

1. Cloudflare DNS 记录从 Proxied 改成 DNS only。
2. Worker route 删除或 disable。
3. iPhone 默认地址临时改回 ECS/Nginx 域名。
4. ECS Docker 服务不需要改。

如果模型 CDN 异常：

1. `download-ticket` 暂时回退到 `/api/cloud/v1/download/:ticketId`。
2. 保持旧的 ECS 本机下载路径。
3. 后续排查对象存储权限、签名 URL、CDN 回源。
