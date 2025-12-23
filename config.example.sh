#!/bin/bash
# SSL证书管理系统 - 配置文件示例
# 复制此文件为 config.sh 并修改配置

# ============ 阿里云DNS API配置 ============
export Ali_Key="你的阿里云AccessKey ID"
export Ali_Secret="你的阿里云AccessKey Secret"

# ============ 域名配置 ============
export DOMAIN="cloud2345.com"

# ============ 证书服务器配置 ============
export CERT_SERVER="https://cert.cloud2345.com"
export CERT_TOKEN="your-secret-token-2024"

# ============ 目录配置 ============
export CERT_DIR="/opt/cert-center/certs/${DOMAIN}"
export AGENT_DIR="/opt/cert-center/agent"

# ============ GOST配置（客户端） ============
export GOST_API="http://127.0.0.1:18080"
export GOST_SERVICE="service-0"
