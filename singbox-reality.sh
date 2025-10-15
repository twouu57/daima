#!/bin/bash

# Sing-box 一键安装管理脚本
# GitHub: https://github.com/your-username/singbox-manager

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 变量定义
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
SCRIPT_NAME="jinrujm"
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME"

# 显示标题
show_header() {
    clear
    echo -e "${GREEN}"
    echo "=========================================="
    echo "           Sing-box 管理脚本"
    echo "=========================================="
    echo -e "${NC}"
}

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本必须使用 root 权限运行${NC}"
        exit 1
    fi
}

# 安装 sing-box
install_singbox() {
    echo -e "${YELLOW}开始安装 sing-box...${NC}"
    
    # 使用官方安装脚本
    bash <(curl -fsSL https://sing-box.app/install.sh)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ sing-box 安装成功${NC}"
        return 0
    else
        echo -e "${RED}❌ sing-box 安装失败${NC}"
        return 1
    fi
}

# 检查并安装 sing-box
check_and_install_singbox() {
    if command -v sing-box &> /dev/null; then
        echo -e "${GREEN}✅ 检测到 sing-box 已安装${NC}"
        echo -e "${BLUE}当前版本: $(sing-box version)${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  未检测到 sing-box${NC}"
        read -p "是否安装 sing-box? [Y/n]: " choice
        choice=${choice:-"Y"}
        
        if [[ $choice =~ [Yy] ]]; then
            install_singbox
            return $?
        else
            echo -e "${RED}取消安装，脚本退出${NC}"
            exit 1
        fi
    fi
}

# 生成 VLESS + Reality 配置
generate_vless_reality() {
    show_header
    echo -e "${PURPLE}正在生成 VLESS + Reality 配置...${NC}"
    
    # 生成 UUID
    UUID=$(sing-box generate uuid)
    echo -e "${GREEN}生成的 UUID: $UUID${NC}"
    
    # 生成 Reality 密钥对
    KEYPAIR=$(sing-box generate reality-keypair)
    PRIVATE_KEY=$(echo "$KEYPAIR" | grep 'PrivateKey:' | awk '{print $2}')
    PUBLIC_KEY=$(echo "$KEYPAIR" | grep 'PublicKey:' | awk '{print $2}')
    echo -e "${GREEN}生成的私钥: $PRIVATE_KEY${NC}"
    echo -e "${GREEN}生成的公钥: $PUBLIC_KEY${NC}"
    
    # 生成短 ID
    SHORT_ID=$(openssl rand -hex 4)
    echo -e "${GREEN}生成的短 ID: $SHORT_ID${NC}"
    
    # 获取用户输入
    read -p "请输入监听端口 [默认: 443]: " LISTEN_PORT
    LISTEN_PORT=${LISTEN_PORT:-"443"}
    
    read -p "请输入 Reality handshake 域名 [默认: www.google.com]: " HANDSHAKE_DOMAIN
    HANDSHAKE_DOMAIN=${HANDSHAKE_DOMAIN:-"www.google.com"}
    
    read -p "请输入 Reality handshake 端口 [默认: 443]: " HANDSHAKE_PORT
    HANDSHAKE_PORT=${HANDSHAKE_PORT:-"443"}
    
    # 获取服务器 IP
    SERVER_IP=$(curl -s http://ipinfo.io/ip || curl -s http://ifconfig.me || hostname -I | awk '{print $1}')
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="你的服务器IP"
    fi
    
    # 创建配置目录
    mkdir -p $CONFIG_DIR
    
    # 创建配置文件（已删除 sniff 字段，简化出站配置）
    cat > $CONFIG_FILE << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": $LISTEN_PORT,
      "users": [
        {
          "name": "user",
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$HANDSHAKE_DOMAIN",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$HANDSHAKE_DOMAIN",
            "server_port": $HANDSHAKE_PORT
          },
          "private_key": "$PRIVATE_KEY",
          "short_id": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF

    echo -e "${GREEN}✅ VLESS + Reality 配置文件已创建: $CONFIG_FILE${NC}"
    
    # 显示客户端配置信息
    show_client_config "$SERVER_IP" "$LISTEN_PORT" "$UUID" "$PUBLIC_KEY" "$SHORT_ID" "$HANDSHAKE_DOMAIN"
    
    # 重启服务
    restart_singbox_service
}

# 显示客户端配置信息
show_client_config() {
    local SERVER_IP=$1
    local LISTEN_PORT=$2
    local UUID=$3
    local PUBLIC_KEY=$4
    local SHORT_ID=$5
    local HANDSHAKE_DOMAIN=$6
    
    echo -e "${CYAN}==================== 客户端配置信息 ====================${NC}"
    echo -e "${YELLOW}服务器地址: ${BLUE}$SERVER_IP${NC}"
    echo -e "${YELLOW}端口: ${BLUE}$LISTEN_PORT${NC}"
    echo -e "${YELLOW}UUID: ${BLUE}$UUID${NC}"
    echo -e "${YELLOW}流控(Flow): ${BLUE}xtls-rprx-vision${NC}"
    echo -e "${YELLOW}公钥(Public Key): ${BLUE}$PUBLIC_KEY${NC}"
    echo -e "${YELLOW}短ID(Short ID): ${BLUE}$SHORT_ID${NC}"
    echo -e "${YELLOW}SNI: ${BLUE}$HANDSHAKE_DOMAIN${NC}"
    
    # 生成 VLESS 链接
    VLESS_LINK="vless://$UUID@$SERVER_IP:$LISTEN_PORT?type=tcp&security=reality&flow=xtls-rprx-vision&sni=$HANDSHAKE_DOMAIN&pbk=$PUBLIC_KEY&sid=$SHORT_ID#singbox-reality"
    echo -e "${YELLOW}VLESS 链接:${NC}"
    echo -e "${BLUE}$VLESS_LINK${NC}"
    echo
    
    read -p "按回车键返回主菜单..."
}

# 安装 Hysteria2
generate_hysteria2() {
    show_header
    echo -e "${PURPLE}正在生成 Hysteria2 配置...${NC}"
    
    echo -e "${YELLOW}⚠️  Hysteria2 功能正在开发中...${NC}"
    echo -e "${YELLOW}请稍后再试或手动配置${NC}"
    read -p "按回车键返回主菜单..."
}

# 显示配置文件内容
show_config() {
    show_header
    echo -e "${PURPLE}当前配置文件内容:${NC}"
    
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}配置文件路径: $CONFIG_FILE${NC}"
        echo
        cat "$CONFIG_FILE" | jq . 2>/dev/null || cat "$CONFIG_FILE"
    else
        echo -e "${RED}❌ 配置文件不存在: $CONFIG_FILE${NC}"
    fi
    
    echo
    read -p "按回车键返回主菜单..."
}

# 重启 sing-box 服务
restart_singbox_service() {
    echo -e "${YELLOW}重启 sing-box 服务...${NC}"
    
    # 创建 systemd 服务文件
    cat > $SERVICE_FILE << EOF
[Unit]
Description=sing-box proxy service
Documentation=https://sing-box.sagernet.org/
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=$(command -v sing-box) run -c $CONFIG_FILE
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sing-box --now
    systemctl restart sing-box
    
    # 检查服务状态
    if systemctl is-active --quiet sing-box; then
        echo -e "${GREEN}✅ sing-box 服务启动成功${NC}"
        echo -e "${YELLOW}服务状态:${NC}"
        systemctl status sing-box --no-pager -l
    else
        echo -e "${RED}❌ sing-box 服务启动失败${NC}"
        echo -e "${YELLOW}查看日志: journalctl -u sing-box -f${NC}"
    fi
}

# 卸载 sing-box
uninstall_singbox() {
    show_header
    echo -e "${RED}⚠️  警告: 此操作将卸载 sing-box 并删除所有配置文件${NC}"
    
    read -p "确定要卸载 sing-box 吗? (y/N): " confirm
    if [[ ! $confirm =~ [Yy] ]]; then
        echo -e "${YELLOW}取消卸载${NC}"
        return
    fi
    
    echo -e "${YELLOW}停止 sing-box 服务...${NC}"
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    
    echo -e "${YELLOW}删除服务文件...${NC}"
    rm -f $SERVICE_FILE
    systemctl daemon-reload
    
    echo -e "${YELLOW}删除配置文件...${NC}"
    rm -rf $CONFIG_DIR
    
    echo -e "${YELLOW}删除二进制文件...${NC}"
    rm -f /usr/local/bin/sing-box
    
    echo -e "${YELLOW}删除管理脚本...${NC}"
    rm -f $INSTALL_PATH
    
    echo -e "${GREEN}✅ sing-box 已完全卸载${NC}"
    echo -e "${YELLOW}如需重新安装，请再次运行此脚本${NC}"
    
    read -p "按回车键退出..."
    exit 0
}

# 安装管理命令
install_command() {
    if [ ! -f "$INSTALL_PATH" ]; then
        echo -e "${YELLOW}安装管理命令到系统...${NC}"
        cp "$0" "$INSTALL_PATH"
        chmod +x "$INSTALL_PATH"
        echo -e "${GREEN}✅ 管理命令已安装，现在您可以使用 'jinrujm' 命令进入管理界面${NC}"
        echo
    fi
}

# 主菜单
main_menu() {
    while true; do
        show_header
        echo -e "${CYAN}请选择操作:${NC}"
        echo "1. 安装 VLESS + Reality"
        echo "2. 安装 Hysteria2"
        echo "3. 显示配置文件内容"
        echo "4. 退出脚本"
        echo "5. 卸载 sing-box"
        echo
        
        read -p "请输入选择 [1-5]: " choice
        
        case $choice in
            1)
                generate_vless_reality
                ;;
            2)
                generate_hysteria2
                ;;
            3)
                show_config
                ;;
            4)
                echo -e "${GREEN}再见!${NC}"
                exit 0
                ;;
            5)
                uninstall_singbox
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${NC}"
                sleep 2
                ;;
        esac
    done
}

# 脚本入口
main() {
    check_root
    check_and_install_singbox
    install_command
    main_menu
}

# 如果直接运行脚本，执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi