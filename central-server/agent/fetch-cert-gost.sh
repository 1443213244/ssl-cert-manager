#!/bin/bash
# GOST服务器 - SSL证书自动拉取Agent
# 定时从中央服务器拉取证书，重载GOST服务

set -e

# ============ 配置区 ============
CERT_SERVER="${CERT_SERVER:-https://cert.cloud2345.com}"
CERT_TOKEN="${CERT_TOKEN:-your-secret-token-2024}"
DOMAIN="${DOMAIN:-cloud2345.com}"

# GOST 证书存放位置
LOCAL_DIR="/root/general"
VERSION_FILE="${LOCAL_DIR}/.version"
LOG_FILE="/var/log/cert-agent.log"
LOCK_FILE="/var/run/cert-agent.lock"

# ============ 函数定义 ============
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [GOST] $1" >> "${LOG_FILE}"
}

cleanup() {
    rm -f "${LOCK_FILE}"
}

die() {
    log "ERROR: $1"
    cleanup
    exit 1
}

# ============ 主流程 ============

# 防止多实例运行
exec 200>"${LOCK_FILE}"
flock -n 200 || { log "Another instance is running, exiting."; exit 0; }
trap cleanup EXIT

log "Starting certificate check..."

# 随机延迟 0-300秒（5分钟），避免大量服务器同时请求
# 手动调试时可将下面三行注释掉
RANDOM_DELAY=$((RANDOM % 300))
log "Random delay: ${RANDOM_DELAY} seconds"
sleep ${RANDOM_DELAY}

# 确保目录存在
mkdir -p "${LOCAL_DIR}"

# 获取远程版本
log "Checking remote version..."
# 修复：改用兼容性更强的 cut 方式解析 JSON，无视空格影响
REMOTE_VERSION=$(curl -sf --connect-timeout 10 --max-time 30 \
    -H "X-Cert-Token: ${CERT_TOKEN}" \
    "${CERT_SERVER}/certs/${DOMAIN}/version.json" 2>/dev/null | \
    grep '"version"' | cut -d'"' -f4)

if [ -z "${REMOTE_VERSION}" ]; then
    die "Failed to fetch remote version from ${CERT_SERVER}"
fi

# 获取本地版本
LOCAL_VERSION=$(cat "${VERSION_FILE}" 2>/dev/null || echo "0")

log "Local version: ${LOCAL_VERSION}, Remote version: ${REMOTE_VERSION}"

# 版本对比
if [ "${REMOTE_VERSION}" = "${LOCAL_VERSION}" ]; then
    log "Certificate is up to date"
    exit 0
fi

log "New certificate detected, downloading..."

# 创建临时目录
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}; cleanup" EXIT

# 下载证书
curl -sf --connect-timeout 10 --max-time 60 \
    -H "X-Cert-Token: ${CERT_TOKEN}" \
    "${CERT_SERVER}/certs/${DOMAIN}/fullchain.pem" -o "${TEMP_DIR}/fullchain.pem" || \
    die "Failed to download fullchain.pem"

curl -sf --connect-timeout 10 --max-time 60 \
    -H "X-Cert-Token: ${CERT_TOKEN}" \
    "${CERT_SERVER}/certs/${DOMAIN}/privkey.pem" -o "${TEMP_DIR}/key.pem" || \
    die "Failed to download privkey.pem"

curl -sf --connect-timeout 10 --max-time 60 \
    -H "X-Cert-Token: ${CERT_TOKEN}" \
    "${CERT_SERVER}/certs/${DOMAIN}/cert.pem" -o "${TEMP_DIR}/cert.pem" || \
    die "Failed to download cert.pem"

# 验证证书有效性
if ! openssl x509 -in "${TEMP_DIR}/fullchain.pem" -noout 2>/dev/null; then
    die "Downloaded certificate is invalid"
fi

# 验证私钥与证书匹配 (兼容 RSA/ECC)
CERT_MD5=$(openssl x509 -in "${TEMP_DIR}/fullchain.pem" -pubkey -noout 2>/dev/null | md5sum | cut -d' ' -f1)
KEY_MD5=$(openssl pkey -in "${TEMP_DIR}/key.pem" -pubout 2>/dev/null | md5sum | cut -d' ' -f1)
if [ "${CERT_MD5}" != "${KEY_MD5}" ]; then
    die "Certificate and private key do not match"
fi

log "Certificate validated successfully"

# 安装证书到 /root/general
cp "${TEMP_DIR}/fullchain.pem" "${LOCAL_DIR}/fullchain.pem"
cp "${TEMP_DIR}/key.pem" "${LOCAL_DIR}/key.pem"
cp "${TEMP_DIR}/cert.pem" "${LOCAL_DIR}/cert.pem"
chmod 644 "${LOCAL_DIR}/fullchain.pem" "${LOCAL_DIR}/cert.pem"
chmod 644 "${LOCAL_DIR}/key.pem"
echo "${REMOTE_VERSION}" > "${VERSION_FILE}"

log "Certificate installed to ${LOCAL_DIR}"

# ============ 重载 GOST ============
log "Reloading GOST..."

if pgrep -x "gost" > /dev/null; then
    pkill -HUP gost
    if [ $? -eq 0 ]; then
        log "GOST reloaded successfully via SIGHUP"
    else
        log "WARN: Failed to send SIGHUP to GOST"
    fi
else
    if systemctl is-active --quiet gost 2>/dev/null; then
        systemctl reload gost 2>/dev/null || systemctl restart gost
        log "GOST reloaded via systemd"
    else
        log "WARN: GOST process not found"
    fi
fi

log "Certificate update completed"
