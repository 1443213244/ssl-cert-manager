#!/bin/bash
# SSL证书申请/续期脚本
# 使用 acme.sh + 阿里云DNS API

set -e

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../config.sh" 2>/dev/null || {
    echo "ERROR: config.sh not found. Copy config.example.sh to config.sh and edit it."
    exit 1
}

# 默认值
DOMAIN="${DOMAIN:-cloud2345.com}"
CERT_DIR="${CERT_DIR:-/opt/cert-center/certs/${DOMAIN}}"
ACME_HOME="${HOME}/.acme.sh"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 检查 acme.sh 是否安装
if [ ! -f "${ACME_HOME}/acme.sh" ]; then
    log "Installing acme.sh..."
    curl https://get.acme.sh | sh -s email=admin@${DOMAIN}
fi

# 确保目录存在
mkdir -p "${CERT_DIR}"

log "Starting certificate renewal for ${DOMAIN}..."

# 申请/续期证书（通配符）
"${ACME_HOME}/acme.sh" --issue --dns dns_ali \
    -d "${DOMAIN}" \
    -d "*.${DOMAIN}" \
    --force

# 安装证书到指定目录
log "Installing certificate to ${CERT_DIR}..."
"${ACME_HOME}/acme.sh" --install-cert -d "${DOMAIN}" \
    --key-file       "${CERT_DIR}/privkey.pem" \
    --fullchain-file "${CERT_DIR}/fullchain.pem" \
    --cert-file      "${CERT_DIR}/cert.pem" \
    --ca-file        "${CERT_DIR}/chain.pem" \
    --reloadcmd      "${SCRIPT_DIR}/update-version.sh"

log "Certificate renewal completed!"

# 显示证书信息
openssl x509 -in "${CERT_DIR}/fullchain.pem" -noout -subject -dates
