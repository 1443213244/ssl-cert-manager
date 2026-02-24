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

### 证书更新与续期机制

1.  **自动检查**：中央服务器部署后，`acme.sh` 会自动添加系统定时任务（cron），每天凌晨检查证书状态。
2.  **续期阈值**：只有当证书有效期**少于 30 天**时，中央服务器才会真正向 CA 发起续期请求。
3.  **联动更新**：续期成功后，会自动触发 `update-version.sh`：
    *   生成全新的 `version.json` 版本文件。
    *   修正私钥权限（644），确保 Nginx 可读取分发。
    *   重载中央服务器 Nginx 以应用新证书。
4.  **客户端同步**：各客户端 Agent 每 4 小时检查一次版本，发现变化后在 4 小时内完成全网同步。
5.  **强制续期**：如需立即更新，可在中央服务器执行：
    ```bash
    /opt/cert-center/scripts/renew-cert.sh --force
    ```

### 技术特性

*   **全算法支持**：兼容传统的 **RSA** 和现代的 **ECC (ECDSA)** 算法证书。
*   **鲁棒的解析**：Agent 使用健壮的 JSON 解析逻辑，兼容不同环境下的格式化差异。
*   **权限自动化**：自动管理证书链与私钥权限（644），解决非 root 进程读取障碍。
*   **防并发设计**：
    *   **随机延迟**：每个 Agent 启动后随机等待 0-300 秒，将 500+ 台服务器的压力均匀分布。
    *   **文件锁**：使用 `flock` 防止多实例运行。
    *   **Nginx 限流**：限制每 IP 每秒 5 个请求。

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
