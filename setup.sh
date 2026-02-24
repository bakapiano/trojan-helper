#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER_CONFIG="$SCRIPT_DIR/helper-config.json"

echo -e "${CYAN}${BOLD}"
echo "╔══════════════════════════════════════════╗"
echo "║        Trojan Helper 配置向导            ║"
echo "╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ─────────────────────────────────────────────
# Step 1: Detect and select Trojan config path
# ─────────────────────────────────────────────
echo -e "${BOLD}[1/3] 配置 Trojan 配置文件路径${NC}"
echo ""

# Common trojan config paths
COMMON_PATHS=(
    "/etc/trojan/config.json"
    "/etc/trojan-go/config.json"
    "/usr/local/etc/trojan/config.json"
    "/usr/local/etc/trojan-go/config.json"
    "/opt/trojan/config.json"
    "/opt/trojan-go/config.json"
    "$HOME/.trojan/config.json"
    "$HOME/trojan/config.json"
    "/etc/trojan/server.json"
    "/usr/local/etc/trojan/server.json"
)

FOUND_PATHS=()

echo -e "${YELLOW}正在探测常见 Trojan 配置文件路径...${NC}"
echo ""

for path in "${COMMON_PATHS[@]}"; do
    if [ -f "$path" ]; then
        FOUND_PATHS+=("$path")
        echo -e "  ${GREEN}✔ 发现:${NC} $path"
    fi
done

if [ ${#FOUND_PATHS[@]} -eq 0 ]; then
    echo -e "  ${RED}✘ 未在常见路径下发现 Trojan 配置文件${NC}"
fi

echo ""

# Build menu
MENU_INDEX=1
if [ ${#FOUND_PATHS[@]} -gt 0 ]; then
    echo -e "${BOLD}请选择 Trojan 配置文件:${NC}"
    echo ""
    for path in "${FOUND_PATHS[@]}"; do
        echo -e "  ${CYAN}${MENU_INDEX})${NC} $path"
        MENU_INDEX=$((MENU_INDEX + 1))
    done
    echo -e "  ${CYAN}${MENU_INDEX})${NC} 手动输入路径"
    echo ""
    read -p "请输入选项 [1-${MENU_INDEX}]: " CHOICE

    if [ "$CHOICE" -eq "$MENU_INDEX" ] 2>/dev/null; then
        read -p "请输入 Trojan 配置文件完整路径: " TROJAN_CONFIG_PATH
    elif [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -lt "$MENU_INDEX" ] 2>/dev/null; then
        TROJAN_CONFIG_PATH="${FOUND_PATHS[$((CHOICE - 1))]}"
    else
        echo -e "${RED}无效选项，退出。${NC}"
        exit 1
    fi
else
    read -p "请输入 Trojan 配置文件完整路径: " TROJAN_CONFIG_PATH
fi

# Validate path
if [ ! -f "$TROJAN_CONFIG_PATH" ]; then
    echo -e "${RED}警告: 文件 '$TROJAN_CONFIG_PATH' 不存在！${NC}"
    read -p "是否继续？(y/N): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "已取消。"
        exit 1
    fi
fi

echo -e "${GREEN}✔ Trojan 配置文件路径: ${TROJAN_CONFIG_PATH}${NC}"
echo ""

# ─────────────────────────────────────────────
# Step 2: Configure Trojan password
# ─────────────────────────────────────────────
echo -e "${BOLD}[2/3] 配置 Trojan 密码${NC}"
echo ""

# Try to read password from trojan config
DEFAULT_PASSWORD=""
if [ -f "$TROJAN_CONFIG_PATH" ]; then
    # Try to extract first password from trojan config
    DEFAULT_PASSWORD=$(python3 -c "
import json, sys
try:
    c = json.load(open('$TROJAN_CONFIG_PATH'))
    pw = c.get('password', c.get('passwords', []))
    if isinstance(pw, list) and len(pw) > 0:
        print(pw[0])
    elif isinstance(pw, str):
        print(pw)
except:
    pass
" 2>/dev/null || true)
fi

if [ -n "$DEFAULT_PASSWORD" ]; then
    echo -e "从配置文件中检测到密码: ${CYAN}${DEFAULT_PASSWORD}${NC}"
    read -p "使用此密码？(Y/n): " USE_DEFAULT
    if [ "$USE_DEFAULT" != "n" ] && [ "$USE_DEFAULT" != "N" ]; then
        TROJAN_PASSWORD="$DEFAULT_PASSWORD"
    else
        read -p "请输入 Trojan 密码: " TROJAN_PASSWORD
    fi
else
    read -p "请输入 Trojan 密码: " TROJAN_PASSWORD
fi

if [ -z "$TROJAN_PASSWORD" ]; then
    echo -e "${RED}密码不能为空！${NC}"
    exit 1
fi

echo -e "${GREEN}✔ Trojan 密码已设置${NC}"
echo ""

# ─────────────────────────────────────────────
# Save helper-config.json
# ─────────────────────────────────────────────
cat > "$HELPER_CONFIG" <<EOF
{
    "trojan_config_path": "$TROJAN_CONFIG_PATH",
    "trojan_password": "$TROJAN_PASSWORD"
}
EOF

echo -e "${GREEN}✔ 配置已保存到: ${HELPER_CONFIG}${NC}"
echo ""

# ─────────────────────────────────────────────
# Step 3: Register as systemd service
# ─────────────────────────────────────────────
echo -e "${BOLD}[3/3] 注册为 systemd 服务${NC}"
echo ""

read -p "是否注册为 systemd 服务？(Y/n): " REGISTER_SERVICE
if [ "$REGISTER_SERVICE" = "n" ] || [ "$REGISTER_SERVICE" = "N" ]; then
    echo -e "${YELLOW}跳过服务注册。${NC}"
    echo ""
    echo -e "${GREEN}${BOLD}配置完成！${NC}"
    echo -e "你可以使用 ${CYAN}node $SCRIPT_DIR/index.js${NC} 手动启动。"
    exit 0
fi

# Detect node path
NODE_PATH=$(which node 2>/dev/null || echo "/usr/bin/node")
NPM_PATH=$(which npm 2>/dev/null || echo "/usr/bin/npm")

echo -e "检测到 Node.js: ${CYAN}${NODE_PATH}${NC}"

# Install dependencies if needed
if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
    echo -e "${YELLOW}正在安装依赖...${NC}"
    cd "$SCRIPT_DIR" && "$NPM_PATH" install
fi

# Create systemd service file
SERVICE_FILE="/etc/systemd/system/trojan-helper.service"

echo -e "正在创建 systemd 服务文件..."

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Trojan Helper Service
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$SCRIPT_DIR
ExecStart=$NODE_PATH $SCRIPT_DIR/index.js
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo -e "${GREEN}✔ 服务文件已创建: ${SERVICE_FILE}${NC}"

# Reload and enable service
sudo systemctl daemon-reload
sudo systemctl enable trojan-helper

echo ""
read -p "是否立即启动服务？(Y/n): " START_NOW
if [ "$START_NOW" != "n" ] && [ "$START_NOW" != "N" ]; then
    sudo systemctl start trojan-helper
    sleep 1
    if sudo systemctl is-active --quiet trojan-helper; then
        echo -e "${GREEN}✔ 服务已启动！${NC}"
    else
        echo -e "${RED}✘ 服务启动失败，请检查日志:${NC}"
        echo -e "  ${CYAN}sudo journalctl -u trojan-helper -f${NC}"
    fi
fi

echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  配置完成！${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════${NC}"
echo ""
echo -e "常用命令:"
echo -e "  ${CYAN}sudo systemctl status trojan-helper${NC}   查看状态"
echo -e "  ${CYAN}sudo systemctl restart trojan-helper${NC}  重启服务"
echo -e "  ${CYAN}sudo systemctl stop trojan-helper${NC}     停止服务"
echo -e "  ${CYAN}sudo journalctl -u trojan-helper -f${NC}   查看日志"
echo ""
