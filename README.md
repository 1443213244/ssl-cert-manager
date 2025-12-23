# SSL 证书自动化管理系统

用于管理通配符SSL证书的自动申请、续期和分发系统。适用于大规模服务器集群（500+台）。

## 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                    证书中央服务器                            │
│  acme.sh (阿里云DNS) → Nginx 托管证书 → 提供HTTPS下载        │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │ 定时拉取 (每4小时)
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
   ┌────┴────┐           ┌────┴────┐           ┌────┴────┐
   │  GOST   │           │  GOST   │           │ JeeCG   │
   │ Server  │           │ Server  │           │ Server  │
   └─────────┘           └─────────┘           └─────────┘
```

## 目录结构

```
ssl-cert-manager/
├── config.example.sh              # 配置示例
├── central-server/                # 中央服务器
│   ├── deploy.sh                 # 一键部署脚本（安装Nginx等）
│   ├── scripts/
│   │   ├── renew-cert.sh         # 证书申请/续期
│   │   └── update-version.sh     # 版本文件更新
│   ├── nginx/
│   │   └── cert-server.conf      # Nginx配置模板
│   └── agent/                     # 托管给客户端下载
│       ├── install.sh            # 一键安装脚本
│       ├── fetch-cert-gost.sh    # GOST专用Agent
│       ├── fetch-cert-jeecg.sh   # JeeCG/Nginx专用Agent
│       └── fetch-cert-generic.sh # 通用Agent
└── README.md
```

## 快速开始

### 一、中央服务器部署（一键）

```bash
# 设置配置变量
export DOMAIN="cloud2345.com"
export CERT_TOKEN="your-secret-token-2024"  # 修改为安全的Token

# 运行一键部署脚本
cd central-server
chmod +x deploy.sh
./deploy.sh
```

部署脚本会自动完成：
- 安装 Nginx（支持 CentOS/Ubuntu/Debian）
- 安装 acme.sh
- 创建目录结构
- 配置 Nginx 证书分发服务
- 复制 Agent 脚本
- 配置防火墙规则

#### 部署后续步骤

```bash
# 1. 编辑配置文件，填入阿里云API密钥
vim /opt/cert-center/config.sh

# 2. 申请SSL证书
source /opt/cert-center/config.sh
/opt/cert-center/scripts/renew-cert.sh

# 3. 证书申请成功后，启用HTTPS
vim /etc/nginx/conf.d/cert-server.conf
nginx -t && systemctl reload nginx
```

### 二、客户端服务器安装

在每台需要证书的服务器上执行：

```bash
curl -fsSL https://cert.cloud2345.com/agent/install.sh | bash
```

安装脚本会自动检测服务类型（GOST/JeeCG/Nginx）并下载对应的Agent。

## 证书路径

### 中央服务器

| 路径 | 说明 |
|------|------|
| `/opt/cert-center/certs/cloud2345.com/` | 证书存储目录 |

文件：
- `fullchain.pem` - 完整证书链
- `cert.pem` - 服务器证书
- `privkey.pem` - 私钥
- `chain.pem` - CA证书链
- `version.json` - 版本信息

### GOST 服务器

| 路径 | 说明 |
|------|------|
| `/root/general/` | GOST证书目录 |

文件：
- `fullchain.pem` - 完整证书链
- `cert.pem` - 服务器证书
- `key.pem` - 私钥

证书更新后自动发送 SIGHUP 信号重载 GOST。

### JeeCG-Boot / Nginx 服务器

| 路径 | 说明 |
|------|------|
| `/etc/ssl/cloud2345.com/` | 证书目录 |

文件：
- `fullchain.pem` - 完整证书链
- `privkey.pem` - 私钥

证书更新后自动执行 `nginx -t && systemctl reload nginx`。

## 工作原理

### 证书同步流程

1. **中央服务器**：acme.sh 通过阿里云 DNS API 自动续期（Let's Encrypt 每90天过期）
2. **版本检查**：客户端定时检查 `/certs/cloud2345.com/version.json`
3. **下载证书**：发现新版本后下载证书文件
4. **验证安装**：验证证书有效性后安装到本地目录
5. **服务重载**：
   - **GOST**：发送 SIGHUP 信号重载全局证书
   - **Nginx**：执行 `nginx -t && systemctl reload nginx`

### 防并发设计

- **随机延迟**：每个Agent启动后随机等待0-300秒
- **文件锁**：使用 flock 防止多实例运行
- **Nginx限流**：限制每IP每秒5个请求

## 日志位置

| 服务器 | 日志路径 |
|--------|---------|
| 中央服务器 | `/var/log/nginx/cert-server-*.log` |
| 客户端 | `/var/log/cert-agent.log` |

```bash
# 查看日志
tail -f /var/log/cert-agent.log
```

## 常见问题

### 手动触发证书更新
```bash
/opt/cert-agent/fetch-cert.sh
```

### 查看本地证书版本
```bash
# GOST服务器
cat /root/general/.version

# JeeCG服务器
cat /etc/ssl/cloud2345.com/.version
```

### 查看证书过期时间
```bash
# GOST服务器
openssl x509 -enddate -noout -in /root/general/fullchain.pem

# JeeCG服务器
openssl x509 -enddate -noout -in /etc/ssl/cloud2345.com/fullchain.pem
```

### 修改检查间隔
```bash
crontab -e
# 修改 "0 */4 * * *" 为其他时间，如每小时 "0 * * * *"
```

## 安全建议

1. **修改默认Token**：务必修改 `your-secret-token-2024` 为强随机字符串
2. **IP白名单**：在Nginx配置中启用IP白名单
3. **HTTPS传输**：确保中央服务器使用HTTPS
4. **私钥权限**：私钥文件权限应为600

## License

MIT
