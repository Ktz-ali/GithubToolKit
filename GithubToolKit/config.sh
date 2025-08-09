#!/bin/bash

# 全局配置文件

# ====== 全局配置 ======
# GitHub工具箱版本信息
VERSION="3.0.0"
LAST_UPDATE="2025-08-04"
TOOL_REPO="GithubToolKit"  # 工具箱的仓库名称

# ================= 多平台配置 =================

# 平台配置文件路径
PLATFORM_CONFIG_FILE="$HOME/.github_platform_config"

# ================= 用户配置文件 =================

# 用户配置文件路径（存储GitHub账户信息和同步设置）
CONFIG_FILE="$HOME/.github_toolkit_config"

# 仓库配置文件路径（存储用户管理的GitHub仓库信息）
REPO_CONFIG_FILE="$HOME/.github_repo_config"

# 仓库缓存文件路径（临时存储API获取的仓库列表）
REPO_CACHE_FILE="$HOME/.github_repo_cache"

# 仓库缓存超时时间（秒）- 5分钟
REPO_CACHE_TIMEOUT=300

# ================= 日志文件配置 =================

# 主日志文件路径（记录常规操作和错误）
LOG_DIR="$HOME/log/github_toolkit"  # 新增日志目录变量
LOG_FILE="$LOG_DIR/toolkit.log"     # 修改为使用目录变量

# 审计日志文件路径（记录重要操作如创建/删除仓库）
AUDIT_LOG_FILE="$LOG_DIR/audit.log"  # 修改为使用目录变量

# ================= 默认值配置 =================

# 默认仓库名称
DEFAULT_REPO_NAME="GithubToolKit"

# 默认仓库描述
DEFAULT_DESCRIPTION="一款通过Github API开发集成的Github多功能同步管理工具箱"

# 默认同步目录
SYNC_DIR="/root/github_sync"

# GitHub API
API_URL="https://api.github.com/user/repos"

# Gitee API
GITEE_API_URL="https://gitee.com/api/v5/user/repos"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # 无颜色


check_dependencies() {
    local missing=0
    local os_type=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    
    # 检查并安装git
    if ! command -v git &>/dev/null; then
        echo -e "${RED}错误: Git未安装${NC}"
        case $os_type in
            ubuntu|debian)
                sudo apt-get install -y git
                ;;
            centos|rhel|fedora)
                sudo yum install -y git
                ;;
            *)
                echo -e "${RED}无法自动安装Git，请手动安装${NC}"
                missing=1
                ;;
        esac
    fi
    
    # 检查并安装curl
    if ! command -v curl &>/dev/null; then
        echo -e "${RED}错误: curl未安装${NC}"
        case $os_type in
            ubuntu|debian)
                sudo apt-get install -y curl
                ;;
            centos|rhel|fedora)
                sudo yum install -y curl
                ;;
            *)
                echo -e "${RED}无法自动安装curl，请手动安装${NC}"
                missing=1
                ;;
        esac
    fi
    
    # 检查并安装jq
    if ! command -v jq &>/dev/null; then
        echo -e "${RED}错误: jq未安装${NC}"
        case $os_type in
            ubuntu|debian)
                sudo apt-get install -y jq
                ;;
            centos|rhel|fedora)
                sudo yum install -y jq
                ;;
            *)
                echo -e "${RED}无法自动安装jq，请手动安装${NC}"
                missing=1
                ;;
        esac
    fi
    
    # 检查并安装iconv
    if ! command -v iconv &>/dev/null; then
        echo -e "${RED}错误: iconv未安装${NC}"
        case $os_type in
            ubuntu|debian)
                sudo apt-get install -y libc-bin
                ;;
            centos|rhel|fedora)
                sudo yum install -y glibc-common
                ;;
            *)
                echo -e "${RED}无法自动安装iconv，请手动安装${NC}"
                missing=1
                ;;
        esac
    fi
    
    # 检查并安装xxd
    if ! command -v xxd &>/dev/null; then
        echo -e "${RED}错误: xxd未安装${NC}"
        case $os_type in
            ubuntu|debian)
                sudo apt-get install -y vim-common
                ;;
            centos|rhel|fedora)
                sudo yum install -y vim-common
                ;;
            *)
                echo -e "${RED}无法自动安装xxd，请手动安装${NC}"
                missing=1
                ;;
        esac
    fi
    
    [ $missing -eq 1 ] && exit 1
}

# 等待用户按回车键继续
press_enter_to_continue() {
    echo -e "${BLUE}--------------------------------${NC}"
    read -p "按回车键返回菜单..." enter_key
}