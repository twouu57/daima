#!/bin/bash

# sing-box VLESS + Reality 配置生成脚本
# GitHub: https://github.com/your-username/singbox-reality

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 变量定义
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="$CONFIG_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
TEMP_DIR="/tmp/singbox-config"

# 显示菜单
show_menu() {
    echo -e "${GREEN}"
    echo "=========================================="
    echo "    sing-box VLESS + Reality 配置生成脚本"
    echo "=========================================="
    echo -e "${NC}"
    echo "1. 生成 VLESS + Reality 配置"
    echo "2. 删除配置和服务"
    echo "0. 退出脚本"
    echo
    read -p "请输入选择 [0-2]: " choice
}

# 显示标题
show_header() {
    clear
    echo -e "${GREEN}"
    echo "=========================================="
    echo "    $1"
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

# 检查 sing-box 是否安装
check_singbox() {
    if ! command -v sing-box &> /dev/null; then
        echo -e "${RED}错误: 未找到 sing-box，请先安装 sing-box${NC}"
        echo -e "${YELLOW}安装命令参考: curl -fsSL https://sing-box.app/install.sh | sh${NC}"
        exit 1
    fi
    echo -e "${GREEN}检测到 sing-box: $(sing-box version)${NC}"
}

# 生成配置参数
generate_config() {
    # 生成 UUID
    UUID=$(sing-box generate uuid)
    echo -e "${GREEN}生成的 UUID: $UUID${NC}"
    
    # 生成 Reality 密钥对
    echo -e "${YELLOW}生成 Reality 密钥对...${NC}"
    KEYPAIR=$(sing-box generate reality-keypair)
    PRIVATE_KEY=$(echo "$KEYPAIR" | grep 'PrivateKey:' | awk '{print $2}')
    PUBLIC_KEY=$(echo "$KEYPAIR" | grep 'PublicKey:' | awk '{print $2}')
    
    echo -e "${GREEN}生成的公钥: $PUBLIC_KEY${NC}"
    echo -e "${GREEN}生成的私钥: $PRIVATE_KEY${NC}"
    
    # 生成短 ID
    SHORT_ID=$(openssl rand -hex 4)
    echo -e "${GREEN}生成的短 ID: $SHORT_ID${NC}"
    
    # 获取用户输入
    read -p "请输入 TLS 伪装域名 [默认: www.google.com]: " TLS_DOMAIN
    TLS_DOMAIN=${TLS_DOMAIN:-"www.google.com"}
    
    read -p "请输入监听端口 [默认: 443]: " LISTEN_PORT
    LISTEN_PORT=${LISTEN_PORT:-"443"}
    
    # 获取服务器公网 IP
    SERVER_IP=$(curl -s http://ipinfo.io/ip || curl -s http://ifconfig.me || hostname -I | awk '{print $1}')
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="你的服务器IP"
    fi
}

# 创建配置文件
create_config_file() {
    echo -e "${YELLOW}创建配置文件...${NC}"
    
    # 创建配置目录
    mkdir -p $CONFIG_DIR
    
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
      "sniff": true,
      "sniff_override_destination": true,
      "users": [
        {
          "name": "user",
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$TLS_DOMAIN",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$TLS_DOMAIN",
            "server_port": 443
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
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF

    echo -e "${GREEN}配置文件已创建: $CONFIG_FILE${NC}"
}

# 创建 systemd 服务
create_systemd_service() {
    echo -e "${YELLOW}创建 systemd 服务...${NC}"
    
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
ExecStart=/usr/local/bin/sing-box run -c $CONFIG_FILE
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载 systemd 并启动服务
    systemctl daemon-reload
    systemctl enable sing-box
    systemctl start sing-box
    
    echo -e "${GREEN}systemd 服务已创建并启动${NC}"
}

# 显示客户端配置信息
show_client_config() {
    show_header "客户端配置信息"
    
    # 询问输出格式
    echo -e "${YELLOW}请选择客户端配置输出格式:${NC}"
    echo "1. conf 格式 (类 v2rayN 配置)"
    echo "2. json 格式 (完整 sing-box 配置)"
    read -p "请输入选择 [默认: 1]: " format_choice
    format_choice=${format_choice:-"1"}
    
    echo -e "${GREEN}==================== 服务器信息 ====================${NC}"
    echo -e "服务器地址: ${BLUE}$SERVER_IP${NC}"
    echo -e "端口: ${BLUE}$LISTEN_PORT${NC}"
    echo -e "协议: ${BLUE}VLESS + Reality${NC}"
    
    echo -e "${GREEN}==================== 认证信息 ====================${NC}"
    echo -e "UUID: ${BLUE}$UUID${NC}"
    echo -e "流控(Flow): ${BLUE}xtls-rprx-vision${NC}"
    
    echo -e "${GREEN}==================== Reality 配置 ====================${NC}"
    echo -e "公钥(Public Key): ${BLUE}$PUBLIC_KEY${NC}"
    echo -e "短ID(Short ID): ${BLUE}$SHORT_ID${NC}"
    echo -e "SNI/伪装域名: ${BLUE}$TLS_DOMAIN${NC}"
    
    # 创建临时目录
    mkdir -p $TEMP_DIR
    
    # 根据选择显示不同格式的配置
    case $format_choice in
        1|"")
            echo -e "${GREEN}==================== 客户端配置 (conf格式) ====================${NC}"
            echo -e "${YELLOW}适用于 v2rayN、Shadowrocket 等客户端${NC}"
            echo
            
            # 生成 VLESS 链接
            VLESS_LINK="vless://$UUID@$SERVER_IP:$LISTEN_PORT?type=tcp&security=reality&flow=xtls-rprx-vision&sni=$TLS_DOMAIN&pbk=$PUBLIC_KEY&sid=$SHORT_ID#singbox-reality"
            echo -e "${BLUE}VLESS 链接:${NC}"
            echo -e "$VLESS_LINK"
            echo
            
            # 保存到文件
            cat > $TEMP_DIR/client-config.conf << EOF
# sing-box VLESS + Reality 客户端配置
# 适用于 v2rayN、Shadowrocket、Clash 等客户端

服务器地址: $SERVER_IP
端口: $LISTEN_PORT
协议: vless
用户ID(UUID): $UUID
流控(Flow): xtls-rprx-vision
传输协议: tcp
安全类型: reality
SNI: $TLS_DOMAIN
公钥(Public Key): $PUBLIC_KEY
短ID(Short ID): $SHORT_ID

VLESS 链接:
$VLESS_LINK

EOF
            echo -e "${YELLOW}配置文件已保存到: $TEMP_DIR/client-config.conf${NC}"
            ;;
        2)
            echo -e "${GREEN}==================== 客户端配置 (JSON格式) ====================${NC}"
            echo -e "${YELLOW}适用于 sing-box 客户端${NC}"
            echo
            
            # 创建完整的 sing-box 客户端配置
            cat > $TEMP_DIR/client-config.json << EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "tag": "local",
        "address": "223.5.5.5"
      }
    ],
    "strategy": "prefer_ipv4"
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 2333,
      "sniff": true
    }
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "$SERVER_IP",
      "server_port": $LISTEN_PORT,
      "uuid": "$UUID",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "$TLS_DOMAIN",
        "reality": {
          "enabled": true,
          "public_key": "$PUBLIC_KEY",
          "short_id": "$SHORT_ID"
        }
      },
      "packet_encoding": "xudp"
    },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ],
  "route": {
    "rules": [
      {
        "geoip": [
          "cn",
          "private"
        ],
        "outbound": "direct"
      },
      {
        "geosite": "cn",
        "outbound": "direct"
      }
    ],
    "final": "proxy",
    "auto_detect_interface": true
  }
}
EOF
            echo -e "${BLUE}客户端配置内容:${NC}"
            cat $TEMP_DIR/client-config.json
            echo -e "${YELLOW}配置文件已保存到: $TEMP_DIR/client-config.json${NC}"
            ;;
        *)
            echo -e "${RED}无效选择，使用默认 conf 格式${NC}"
            ;;
    esac
    
    echo
    echo -e "${GREEN}==================== 服务状态 ====================${NC}"
    systemctl status sing-box --no-pager
    
    echo
    echo -e "${GREEN}==================== 使用说明 ====================${NC}"
    echo -e "${YELLOW}1. 客户端配置已保存到临时目录: $TEMP_DIR/${NC}"
    echo -e "${YELLOW}2. 检查服务状态: systemctl status sing-box${NC}"
    echo -e "${YELLOW}3. 查看服务日志: journalctl -u sing-box -f${NC}"
    echo -e "${YELLOW}4. 防火墙请放行端口: $LISTEN_PORT${NC}"
    echo -e "${YELLOW}5. 检查配置文件: sing-box check -c $CONFIG_FILE${NC}"
    
    echo
    echo -e "${GREEN}✅ 配置生成完成!${NC}"
    echo -e "${YELLOW}请妥善保存上面的客户端配置信息${NC}"
}

# 生成 VLESS + Reality 配置
generate_vless_reality() {
    show_header "生成 VLESS + Reality 配置"
    
    check_root
    check_singbox
    generate_config
    create_config_file
    
    # 检查是否要创建 systemd 服务
    read -p "是否创建并启动 systemd 服务? [Y/n]: " create_service
    create_service=${create_service:-"Y"}
    
    if [[ $create_service =~ [Yy] ]]; then
        create_systemd_service
        # 等待服务启动
        sleep 3
    else
        echo -e "${YELLOW}跳过服务创建，请手动启动 sing-box${NC}"
        echo -e "${YELLOW}启动命令: sing-box run -c $CONFIG_FILE${NC}"
    fi
    
    show_client_config
    
    read -p "按回车键返回主菜单..."
}

# 删除配置和服务
remove_config_service() {
    show_header "删除 VLESS + Reality 配置"
    
    read -p "确定要删除 sing-box 配置和服务吗？(y/N): " confirm
    if [[ $confirm != [yY] ]]; then
        echo "删除已取消"
        return
    fi
    
    echo -e "${YELLOW}停止服务...${NC}"
    systemctl stop sing-box 2>/dev/null || true
    systemctl disable sing-box 2>/dev/null || true
    
    echo -e "${YELLOW}删除配置文件...${NC}"
    rm -rf $CONFIG_DIR
    
    echo -e "${YELLOW}删除服务文件...${NC}"
    rm -f $SERVICE_FILE
    
    echo -e "${YELLOW}重新加载 systemd...${NC}"
    systemctl daemon-reload
    
    echo -e "${GREEN}✅ 配置和服务删除完成!${NC}"
    echo -e "${YELLOW}注意: sing-box 二进制文件仍保留在系统中${NC}"
    
    read -p "按回车键返回主菜单..."
}

# 主循环
main() {
    while true; do
        show_menu
        case $choice in
            1)
                generate_vless_reality
                ;;
            2)
                remove_config_service
                ;;
            0)
                echo -e "${GREEN}再见!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${NC}"
                sleep 2
                ;;
        esac
    done
}

# 脚本入口
if [[ $1 == "--generate" ]]; then
    generate_vless_reality
elif [[ $1 == "--remove" ]]; then
    remove_config_service
else
    main
fi
