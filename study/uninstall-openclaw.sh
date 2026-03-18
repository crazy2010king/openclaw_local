#!/bin/bash

# 完全卸载Ubuntu/Debian系统上的OpenClaw软件与数据
# 该脚本会卸载所有OpenClaw组件，包括：
# - Gateway服务 (systemd)
# - 配置和状态文件 (~/.openclaw)
# - 工作区文件
# - 全局npm/pnpm安装的CLI

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}开始完全卸载OpenClaw...${NC}"

# 检查是否以root用户运行
if [[ $EUID -eq 0 ]]; then
    echo -e "${YELLOW}警告：不建议以root用户运行此脚本。某些操作可能需要sudo权限。${NC}"
fi

# 1. 停止并卸载Gateway服务（使用OpenClaw自带的卸载命令）
echo -e "\n${GREEN}1. 停止并卸载OpenClaw Gateway服务${NC}"
if command -v openclaw &> /dev/null; then
    echo "正在执行 openclaw uninstall --all --yes --non-interactive"
    if openclaw uninstall --all --yes --non-interactive; then
        echo -e "${GREEN}✓ OpenClaw组件卸载成功${NC}"
    else
        echo -e "${YELLOW}⚠️  OpenClaw自带卸载命令执行失败，将尝试手动卸载${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  未找到openclaw命令，将直接进行手动卸载${NC}"
fi

# 2. 手动卸载systemd服务（如果存在）
echo -e "\n${GREEN}2. 检查并卸载systemd服务${NC}"
if [[ -f "/etc/systemd/system/openclaw-gateway.service" ]]; then
    echo "停止openclaw-gateway服务"
    sudo systemctl stop openclaw-gateway.service 2>/dev/null || true

    echo "禁用openclaw-gateway服务"
    sudo systemctl disable openclaw-gateway.service 2>/dev/null || true

    echo "删除systemd服务文件"
    sudo rm -f "/etc/systemd/system/openclaw-gateway.service"

    echo "重新加载systemd配置"
    sudo systemctl daemon-reload
    echo -e "${GREEN}✓ Systemd服务卸载成功${NC}"
else
    echo -e "${YELLOW}⚠️  未找到openclaw-gateway systemd服务${NC}"
fi

# 3. 删除用户状态和配置文件
echo -e "\n${GREEN}3. 删除OpenClaw状态和配置文件${NC}"
OPENCLAW_STATE_DIR="$HOME/.openclaw"
if [[ -d "$OPENCLAW_STATE_DIR" ]]; then
    echo "删除 $OPENCLAW_STATE_DIR"
    rm -rf "$OPENCLAW_STATE_DIR"
    echo -e "${GREEN}✓ 状态和配置文件删除成功${NC}"
else
    echo -e "${YELLOW}⚠️  未找到 $OPENCLAW_STATE_DIR${NC}"
fi

# 4. 删除工作区目录
echo -e "\n${GREEN}4. 删除OpenClaw工作区文件${NC}"
# 根据src/commands/uninstall.ts中的逻辑，工作区可能在以下位置
# - ~/.openclaw/agents (已在上面删除)
# - 其他可能的工作区位置

# 5. 卸载npm/pnpm全局安装的OpenClaw
echo -e "\n${GREEN}5. 卸载OpenClaw CLI${NC}"

# 检查是否通过npm安装
if npm list -g openclaw &> /dev/null; then
    echo "通过npm卸载OpenClaw"
    npm uninstall -g openclaw
    echo -e "${GREEN}✓ npm卸载成功${NC}"
else
    echo -e "${YELLOW}⚠️  未找到npm全局安装的OpenClaw${NC}"
fi

# 检查是否通过pnpm安装
if command -v pnpm &> /dev/null && pnpm list -g openclaw &> /dev/null; then
    echo "通过pnpm卸载OpenClaw"
    pnpm uninstall -g openclaw
    echo -e "${GREEN}✓ pnpm卸载成功${NC}"
else
    echo -e "${YELLOW}⚠️  未找到pnpm全局安装的OpenClaw${NC}"
fi

# 6. 检查是否有其他OpenClaw相关文件
echo -e "\n${GREEN}6. 检查并删除其他OpenClaw相关文件${NC}"

# 检查是否有OpenClaw应用程序
if [[ -d "/opt/openclaw" ]]; then
    echo "删除 /opt/openclaw"
    sudo rm -rf "/opt/openclaw"
    echo -e "${GREEN}✓ /opt/openclaw删除成功${NC}"
fi

# 检查是否有OpenClaw的二进制文件
if [[ -f "/usr/bin/openclaw" ]]; then
    echo "删除 /usr/bin/openclaw"
    sudo rm -f "/usr/bin/openclaw"
    echo -e "${GREEN}✓ /usr/bin/openclaw删除成功${NC}"
fi

# 检查是否有OpenClaw的符号链接
if command -v openclaw &> /dev/null; then
    OPENCLAW_PATH=$(which openclaw)
    echo "删除OpenClaw可执行文件: $OPENCLAW_PATH"
    rm -f "$OPENCLAW_PATH"
    echo -e "${GREEN}✓ OpenClaw可执行文件删除成功${NC}"
fi

# 检查是否有残留的进程
echo -e "\n${GREEN}7. 检查并终止OpenClaw进程${NC}"
OPENCLAW_PROCESSES=$(pgrep -f "openclaw" || true)
if [[ -n "$OPENCLAW_PROCESSES" ]]; then
    echo "找到OpenClaw进程: $OPENCLAW_PROCESSES"
    echo "正在终止这些进程"
    kill -9 $OPENCLAW_PROCESSES 2>/dev/null || true
    # 等待进程终止
    sleep 2
    # 再次检查
    REMAINING_PROCESSES=$(pgrep -f "openclaw" || true)
    if [[ -n "$REMAINING_PROCESSES" ]]; then
        echo -e "${YELLOW}⚠️  仍有OpenClaw进程残留: $REMAINING_PROCESSES${NC}"
    else
        echo -e "${GREEN}✓ 所有OpenClaw进程已终止${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  未找到OpenClaw进程${NC}"
fi

echo -e "\n${GREEN}=====================================${NC}"
echo -e "${GREEN}OpenClaw卸载完成！${NC}"
echo -e "${GREEN}=====================================${NC}"
echo -e "\n${YELLOW}提示：${NC}"
echo "如果您之前使用了其他安装方式（如源码安装），可能需要手动检查以下位置："
echo "  - /usr/local/bin/openclaw"
echo "  - /usr/local/lib/node_modules/openclaw"
echo "  - ~/.local/bin/openclaw"
echo "  - ~/.local/share/openclaw"
