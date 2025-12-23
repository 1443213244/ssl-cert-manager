#!/bin/bash
# 中央服务器一键部署脚本
# 自动安装Nginx、acme.sh，配置证书分发服务

set -e

# ============ 配置区 ============
DOMAIN="${DOMAIN:-cloud2345.com}"
CERT_TOKEN="${CERT_TOKEN:-your-secret-token-2024}"
CERT_DIR="/opt/cert-center/certs/${DOMAIN}"
AGENT_DIR="/opt/cert-center/agent"
SCRIPT_DIR="/opt/cert-center/scripts"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ============ 检查Root权限 ============
if [ "$EUID" -ne 0 ]; then
    log_error "请使用root权限运行此脚本"
fi

echo "=========================================="
echo "   SSL证书分发中央服务器部署"
echo "=========================================="
echo ""
echo "域名: ${DOMAIN}"
echo "Token: ${CERT_TOKEN}"
echo ""

# ============ 检测系统类型 ============
detect_os() {
    if [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

OS_TYPE=$(detect_os)
log_info "检测到系统类型: ${OS_TYPE}"

# ============ 安装Nginx ============
install_nginx() {
    log_info "安装 Nginx..."
    
    case $OS_TYPE in
        "rhel")
            # CentOS / RHEL / Rocky / AlmaLinux
            if ! command -v nginx &> /dev/null; then
                yum install -y epel-release || dnf install -y epel-release
                yum install -y nginx || dnf install -y nginx
            fi
            ;;
        "debian")
            # Debian / Ubuntu
            if ! command -v nginx &> /dev/null; then
                apt-get update
                apt-get install -y nginx
            fi
            ;;
        *)
            log_error "不支持的操作系统，请手动安装Nginx"
            ;;
    esac
    
    log_info "Nginx 安装完成"
}

# ============ 安装acme.sh ============
install_acme() {
    if [ ! -f "${HOME}/.acme.sh/acme.sh" ]; then
        log_info "安装 acme.sh..."
        curl https://get.acme.sh | sh -s email=admin@${DOMAIN}
        log_info "acme.sh 安装完成"
    else
        log_info "acme.sh 已安装"
    fi
}

# ============ 创建目录结构 ============
create_directories() {
    log_info "创建目录结构..."
    
    mkdir -p "${CERT_DIR}"
    mkdir -p "${AGENT_DIR}"
    mkdir -p "${SCRIPT_DIR}"
    mkdir -p /var/log/nginx
    
    chmod 755 /opt/cert-center
    chmod 755 "${CERT_DIR}"
    chmod 755 "${AGENT_DIR}"
    chmod 755 "${SCRIPT_DIR}"
    
    log_info "目录结构创建完成"
}

# ============ 配置Nginx ============
configure_nginx() {
    log_info "配置 Nginx..."
    
    # 生成Nginx配置
    cat > /etc/nginx/conf.d/cert-server.conf << EOF
# SSL证书分发服务器配置
# 自动生成于 $(date)

limit_req_zone \$binary_remote_addr zone=cert_limit:10m rate=5r/s;

server {
    listen 80;
    server_name cert.${DOMAIN};
    
    # 健康检查（无需重定向）
    location /health {
        return 200 "OK\\n";
        add_header Content-Type text/plain;
    }
    
    # 其他请求重定向到HTTPS（证书申请后启用）
    # return 301 https://\$server_name\$request_uri;
    
    # 临时提供HTTP服务（用于首次证书申请前）
    location /agent/ {
        alias ${AGENT_DIR}/;
        autoindex off;
    }
    
    location /certs/ {
        set \$valid_token "${CERT_TOKEN}";
        if (\$http_x_cert_token != \$valid_token) {
            return 403;
        }
        alias ${CERT_DIR}/../;
    }
}

# HTTPS配置（证书申请后取消注释）
# server {
#     listen 443 ssl http2;
#     server_name cert.${DOMAIN};
#
#     ssl_certificate     ${CERT_DIR}/fullchain.pem;
#     ssl_certificate_key ${CERT_DIR}/privkey.pem;
#     ssl_protocols TLSv1.2 TLSv1.3;
#     ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
#     ssl_prefer_server_ciphers off;
#     ssl_session_cache shared:SSL:10m;
#
#     access_log /var/log/nginx/cert-server-access.log;
#     error_log /var/log/nginx/cert-server-error.log;
#
#     location /certs/ {
#         limit_req zone=cert_limit burst=10 nodelay;
#         
#         set \$valid_token "${CERT_TOKEN}";
#         if (\$http_x_cert_token != \$valid_token) {
#             return 403;
#         }
#
#         alias ${CERT_DIR}/../;
#         add_header Cache-Control "no-cache, no-store";
#     }
#
#     location /agent/ {
#         alias ${AGENT_DIR}/;
#         autoindex off;
#     }
#
#     location /health {
#         return 200 "OK\\n";
#         add_header Content-Type text/plain;
#     }
# }
EOF

    # 测试Nginx配置
    if nginx -t; then
        log_info "Nginx 配置有效"
    else
        log_error "Nginx 配置无效，请检查"
    fi
}

# ============ 复制脚本 ============
copy_scripts() {
    log_info "复制脚本文件..."
    
    # 获取当前脚本所在目录
    CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 复制中央服务器脚本
    if [ -f "${CURRENT_DIR}/scripts/renew-cert.sh" ]; then
        cp "${CURRENT_DIR}/scripts/renew-cert.sh" "${SCRIPT_DIR}/"
        cp "${CURRENT_DIR}/scripts/update-version.sh" "${SCRIPT_DIR}/"
        chmod +x "${SCRIPT_DIR}"/*.sh
    fi
    
    # 复制Agent脚本
    if [ -d "${CURRENT_DIR}/agent" ]; then
        cp "${CURRENT_DIR}/agent"/*.sh "${AGENT_DIR}/"
        chmod +x "${AGENT_DIR}"/*.sh
        
        # 替换Token
        sed -i "s/your-secret-token-2024/${CERT_TOKEN}/g" "${AGENT_DIR}"/*.sh
    fi
    
    log_info "脚本复制完成"
}

# ============ 生成配置文件 ============
generate_config() {
    log_info "生成配置文件..."
    
    cat > /opt/cert-center/config.sh << EOF
#!/bin/bash
# SSL证书管理系统配置文件
# 生成于 $(date)

# 阿里云DNS API配置（请修改为实际值）
export Ali_Key="YOUR_ALI_KEY"
export Ali_Secret="YOUR_ALI_SECRET"

# 域名配置
export DOMAIN="${DOMAIN}"

# 证书服务器配置
export CERT_SERVER="https://cert.${DOMAIN}"
export CERT_TOKEN="${CERT_TOKEN}"

# 目录配置
export CERT_DIR="${CERT_DIR}"
export AGENT_DIR="${AGENT_DIR}"
EOF

    chmod 600 /opt/cert-center/config.sh
    log_info "配置文件已生成: /opt/cert-center/config.sh"
}

# ============ 启动Nginx ============
start_nginx() {
    log_info "启动 Nginx..."
    
    systemctl enable nginx
    systemctl start nginx || systemctl restart nginx
    
    if systemctl is-active --quiet nginx; then
        log_info "Nginx 运行中"
    else
        log_error "Nginx 启动失败"
    fi
}

# ============ 配置防火墙 ============
configure_firewall() {
    log_info "配置防火墙..."
    
    # firewalld (CentOS/RHEL)
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service=http 2>/dev/null || true
        firewall-cmd --permanent --add-service=https 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        log_info "firewalld 规则已添加"
    fi
    
    # ufw (Ubuntu/Debian)
    if command -v ufw &> /dev/null; then
        ufw allow 'Nginx Full' 2>/dev/null || true
        log_info "ufw 规则已添加"
    fi
}

# ============ 主流程 ============
main() {
    install_nginx
    install_acme
    create_directories
    copy_scripts
    generate_config
    configure_nginx
    configure_firewall
    start_nginx
    
    echo ""
    echo "=========================================="
    log_info "部署完成！"
    echo "=========================================="
    echo ""
    echo "后续步骤："
    echo ""
    echo "1. 编辑配置文件，填入阿里云API密钥："
    echo "   vim /opt/cert-center/config.sh"
    echo ""
    echo "2. 申请SSL证书："
    echo "   source /opt/cert-center/config.sh"
    echo "   ${SCRIPT_DIR}/renew-cert.sh"
    echo ""
    echo "3. 启用HTTPS（申请证书后）："
    echo "   取消 /etc/nginx/conf.d/cert-server.conf 中HTTPS部分的注释"
    echo "   注释掉HTTP部分的location配置"
    echo "   systemctl reload nginx"
    echo ""
    echo "4. 客户端安装命令："
    echo "   curl -fsSL http://cert.${DOMAIN}/agent/install.sh | bash"
    echo ""
    echo "日志位置："
    echo "   /var/log/nginx/cert-server-*.log"
    echo ""
}

main "$@"
