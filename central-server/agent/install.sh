#!/bin/bash
# SSL证书Agent一键安装脚本
# 用法: curl -fsSL https://cert.cloud2345.com/agent/install.sh | bash
#
# 此脚本会自动检测服务器类型（GOST/JeeCG/Nginx）并安装对应的Agent

set -e

# ============ 配置 ============
CERT_SERVER="${CERT_SERVER:-https://cert.cloud2345.com}"
DOMAIN="${DOMAIN:-cloud2345.com}"
INSTALL_DIR="/opt/cert-agent"
SSL_DIR="/etc/ssl/${DOMAIN}"
LOG_FILE="/var/log/cert-agent.log"

# ============ 颜色输出 ============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============ 检测服务类型 ============
detect_service_type() {
    # 检测 GOST
    if pgrep -x "gost" > /dev/null 2>&1; then
        echo "gost"
        return
    fi
    
    if systemctl is-active --quiet gost 2>/dev/null; then
        echo "gost"
        return
    fi
    
    if [ -f "/etc/systemd/system/gost.service" ] || [ -f "/usr/lib/systemd/system/gost.service" ]; then
        echo "gost"
        return
    fi

    # 检测 JeeCG-Boot（Java应用）
    if pgrep -f "jeecg" > /dev/null 2>&1; then
        echo "jeecg"
        return
    fi
    
    if [ -d "/opt/jeecg-boot" ] || [ -f "/opt/jeecg-boot/app.jar" ]; then
        echo "jeecg"
        return
    fi

    # 检测 Nginx
    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo "nginx"
        return
    fi

    # 通用类型
    echo "generic"
}

# ============ 主流程 ============
echo "=========================================="
echo "   SSL Certificate Agent Installer"
echo "=========================================="
echo ""

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root"
    exit 1
fi

# 检测服务类型
SERVICE_TYPE=$(detect_service_type)
log_info "Detected service type: ${SERVICE_TYPE}"

# 创建目录
mkdir -p "${INSTALL_DIR}" "${SSL_DIR}"
log_info "Created directories: ${INSTALL_DIR}, ${SSL_DIR}"

# 确定要下载的Agent脚本
case $SERVICE_TYPE in
    "gost")
        AGENT_SCRIPT="fetch-cert-gost.sh"
        ;;
    "jeecg"|"nginx")
        AGENT_SCRIPT="fetch-cert-jeecg.sh"
        ;;
    *)
        AGENT_SCRIPT="fetch-cert-generic.sh"
        ;;
esac

# 下载Agent脚本
log_info "Downloading ${AGENT_SCRIPT}..."
if curl -fsSL "${CERT_SERVER}/agent/${AGENT_SCRIPT}" -o "${INSTALL_DIR}/fetch-cert.sh"; then
    chmod +x "${INSTALL_DIR}/fetch-cert.sh"
    log_info "Agent script installed"
else
    log_error "Failed to download agent script"
    exit 1
fi

# 配置 crontab（每4小时执行）
log_info "Setting up cron job..."
CRON_CMD="${INSTALL_DIR}/fetch-cert.sh >> ${LOG_FILE} 2>&1"
(crontab -l 2>/dev/null | grep -v 'cert-agent' | grep -v 'fetch-cert'; \
 echo "0 */4 * * * ${CRON_CMD}") | crontab -
log_info "Cron job configured (every 4 hours)"

# 创建日志文件
touch "${LOG_FILE}"
chmod 644 "${LOG_FILE}"

# 首次执行（后台运行，不等待随机延迟）
log_info "Running agent for the first time (background)..."
nohup bash -c "sleep 5 && ${INSTALL_DIR}/fetch-cert.sh" >> "${LOG_FILE}" 2>&1 &

echo ""
echo "=========================================="
log_info "Installation completed!"
echo "=========================================="
echo ""
echo "  Service Type: ${SERVICE_TYPE}"
echo "  Agent Script: ${INSTALL_DIR}/fetch-cert.sh"
echo "  Certificates: ${SSL_DIR}/"
echo "  Log File:     ${LOG_FILE}"
echo ""
echo "  Check status: tail -f ${LOG_FILE}"
echo ""
