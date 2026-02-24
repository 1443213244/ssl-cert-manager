#!/bin/bash
# 证书版本更新脚本
# 每次证书更新后调用，生成version.json供客户端检查

set -e

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh" 2>/dev/null || true

# 默认值
DOMAIN="${DOMAIN:-cloud2345.com}"
CERT_DIR="${CERT_DIR:-/opt/cert-center/certs/${DOMAIN}}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

FULLCHAIN="${CERT_DIR}/fullchain.pem"
VERSION_FILE="${CERT_DIR}/version.json"

if [ ! -f "${FULLCHAIN}" ]; then
    log "ERROR: Certificate not found: ${FULLCHAIN}"
    exit 1
fi

# 生成版本号（使用时间戳）
VERSION=$(date +%s)

# 获取证书过期时间
EXPIRES=$(openssl x509 -enddate -noout -in "${FULLCHAIN}" | cut -d= -f2)

# 获取证书指纹
FINGERPRINT=$(openssl x509 -fingerprint -sha256 -noout -in "${FULLCHAIN}" | cut -d= -f2 | tr -d ':')

# 生成版本文件
cat > "${VERSION_FILE}" << EOF
{
    "version": "${VERSION}",
    "expires": "${EXPIRES}",
    "fingerprint": "${FINGERPRINT}",
    "updated_at": "$(date -Iseconds)",
    "domain": "${DOMAIN}"
}
EOF

# 设置权限，允许Nginx读取以进行分发
chmod 644 "${CERT_DIR}"/*.pem "${VERSION_FILE}" 2>/dev/null || true

log "Version updated: ${VERSION}"
log "Expires: ${EXPIRES}"
log "Fingerprint: ${FINGERPRINT}"

# 重载Nginx（如果运行中）
if systemctl is-active --quiet nginx 2>/dev/null; then
    nginx -t && systemctl reload nginx
    log "Nginx reloaded"
fi
