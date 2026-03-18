#!/bin/bash

# 完全安装Ubuntu/Debian系统上的OpenClaw软件
# 该脚本会处理所有可能的安装场景，包括：
# - 系统要求检查
# - 包管理器检测
# - 全局安装OpenClaw
# - 安装Gateway服务
# - 验证安装
# - 错误处理和重试

set -euo pipefail

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}ℹ️  $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" &> /dev/null
}

# 检查系统要求
check_system_requirements() {
    log_info "检查系统要求..."

    # 检查操作系统
    if [[ "$(uname -s)" != "Linux" ]]; then
        log_error "此脚本仅适用于Linux系统（Ubuntu/Debian）"
        exit 1
    fi

    # 检查架构
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" && "$ARCH" != "arm64" && "$ARCH" != "aarch64" ]]; then
        log_error "不支持的架构: $ARCH。仅支持 x86_64、arm64 或 aarch64"
        exit 1
    fi

    log_success "系统架构支持: $ARCH"
}

# 检查并安装Node.js
check_and_install_nodejs() {
    log_info "检查Node.js版本..."

    if command_exists node; then
        NODE_VERSION=$(node --version | sed 's/v//')
        log_info "已安装Node.js版本: $NODE_VERSION"

        # 检查Node.js版本是否满足要求 (≥22)
        if [[ "$(printf '%s\n' "22.0.0" "$NODE_VERSION" | sort -V | head -n1)" != "22.0.0" ]]; then
            log_warning "Node.js版本 $NODE_VERSION 低于要求的22.0.0版本"
            read -p "是否要升级Node.js? (y/N): " -r
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                install_nodejs
            else
                log_error "Node.js版本不满足要求，安装无法继续"
                exit 1
            fi
        else
            log_success "Node.js版本满足要求"
        fi
    else
        log_warning "未找到Node.js"
        read -p "是否要安装Node.js 22+? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_nodejs
        else
            log_error "Node.js未安装，安装无法继续"
            exit 1
        fi
    fi
}

# 安装Node.js
install_nodejs() {
    log_info "正在安装Node.js 22..."

    # 检查包管理器
    if command_exists apt; then
        # Ubuntu/Debian
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
        sudo apt-get install -y nodejs
    elif command_exists yum; then
        # CentOS/RHEL
        curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo -E bash -
        sudo yum install -y nodejs
    else
        log_error "未找到支持的包管理器（apt或yum）"
        exit 1
    fi

    log_success "Node.js安装成功"
}

# 检测包管理器
detect_package_manager() {
    log_info "检测包管理器..."

    if command_exists pnpm; then
        PM="pnpm"
        PM_INSTALL="pnpm add -g"
        log_success "使用pnpm作为包管理器"
    elif command_exists npm; then
        PM="npm"
        PM_INSTALL="npm install -g"
        log_success "使用npm作为包管理器"
    elif command_exists bun; then
        PM="bun"
        PM_INSTALL="bun add -g"
        log_success "使用bun作为包管理器"
    else
        log_error "未找到可用的包管理器（npm/pnpm/bun）"
        log_info "请先安装npm、pnpm或bun"
        exit 1
    fi
}

# 安装OpenClaw
install_openclaw() {
    log_info "正在安装OpenClaw..."

    log_info "使用 $PM 安装OpenClaw..."

    if ! $PM_INSTALL openclaw@latest; then
        log_error "OpenClaw安装失败"
        log_info "正在尝试重试..."
        sleep 3
        if ! $PM_INSTALL openclaw@latest; then
            log_error "OpenClaw安装重试失败"
            log_info "请检查网络连接或包管理器配置"
            exit 1
        fi
    fi

    log_success "OpenClaw安装成功"

    # 验证安装
    if command_exists openclaw; then
        OPENCLAW_VERSION=$(openclaw --version)
        log_success "OpenClaw版本: $OPENCLAW_VERSION"
    else
        log_error "OpenClaw命令未找到"
        log_info "检查以下位置是否在PATH中:"
        log_info "  - /usr/local/bin"
        log_info "  - ~/.npm/bin"
        log_info "  - ~/.local/bin"
        log_info "  - ~/.bun/bin"
        exit 1
    fi
}

# 运行onboard向导
run_onboarding() {
    log_info "正在运行OpenClaw onboarding向导..."

    log_info "onboarding向导将引导您完成以下设置:"
    log_info "  1. Gateway服务配置"
    log_info "  2. 工作区设置"
    log_info "  3. 渠道配置"
    log_info "  4. 技能安装"
    log_info ""
    log_warning "此过程可能需要几分钟时间..."
    log_info ""

    read -p "是否要继续运行onboarding向导? (Y/n): " -r
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        if openclaw onboard --install-daemon; then
            log_success "onboarding向导完成"
        else
            log_warning "onboarding向导执行失败"
            log_info "您可以稍后手动运行: openclaw onboard --install-daemon"
        fi
    else
        log_warning "onboarding向导已跳过"
        log_info "您可以稍后手动运行: openclaw onboard --install-daemon"
    fi
}

# 验证Gateway服务状态
verify_gateway_service() {
    log_info "验证Gateway服务状态..."

    if command_exists systemctl; then
        # 检查systemd服务
        if systemctl --user is-active openclaw-gateway &> /dev/null; then
            log_success "OpenClaw Gateway服务正在运行"
        else
            log_warning "OpenClaw Gateway服务未运行"
            read -p "是否要启动Gateway服务? (Y/n): " -r
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                if systemctl --user start openclaw-gateway; then
                    log_success "OpenClaw Gateway服务启动成功"
                else
                    log_error "OpenClaw Gateway服务启动失败"
                fi
            fi
        fi

        # 检查服务是否已启用
        if systemctl --user is-enabled openclaw-gateway &> /dev/null; then
            log_success "OpenClaw Gateway服务已启用（开机自启动）"
        else
            log_warning "OpenClaw Gateway服务未启用"
            read -p "是否要启用Gateway服务开机自启动? (Y/n): " -r
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                if systemctl --user enable openclaw-gateway; then
                    log_success "OpenClaw Gateway服务已启用"
                else
                    log_error "OpenClaw Gateway服务启用失败"
                fi
            fi
        fi
    else
        log_warning "无法检查系统服务（未找到systemctl）"
        log_info "您可以通过以下命令手动检查Gateway状态:"
        log_info "  openclaw gateway status"
    fi
}

# 显示安装完成信息
show_installation_summary() {
    log_info ""
    log_success "====================================="
    log_success "OpenClaw安装完成！"
    log_success "====================================="
    log_info ""
    log_info "下一步操作:"
    log_info ""
    log_info "1. 如果您跳过了onboarding向导，请手动运行:"
    log_info "   openclaw onboard --install-daemon"
    log_info ""
    log_info "2. 检查Gateway服务状态:"
    log_info "   openclaw gateway status"
    log_info ""
    log_info "3. 启动Gateway服务（如果未运行）:"
    log_info "   openclaw gateway run --bind loopback --port 18789 --force"
    log_info ""
    log_info "4. 查看可用命令:"
    log_info "   openclaw --help"
    log_info ""
    log_info "文档:"
    log_info "   https://docs.openclaw.ai"
    log_info "   https://docs.openclaw.ai/start/getting-started"
    log_info ""
}

# 主安装函数
main() {
    log_info "====================================="
    log_info "OpenClaw安装脚本"
    log_info "====================================="
    log_info ""

    # 检查是否以root用户运行
    if [[ $EUID -eq 0 ]]; then
        log_warning "警告：不建议以root用户运行此脚本。某些操作可能需要sudo权限。"
        log_info ""
    fi

    # 执行安装步骤
    check_system_requirements
    check_and_install_nodejs
    detect_package_manager
    install_openclaw
    run_onboarding
    verify_gateway_service
    show_installation_summary
}

# 处理脚本退出
trap 'log_info ""; log_info "安装过程被中断"; exit 1' INT TERM

# 开始安装
main "$@"
