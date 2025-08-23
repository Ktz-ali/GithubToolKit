#!/bin/bash

# 通用函数库

# ====== 全局配置 ======
# 版本信息
VERSION="3.2.0"
LAST_UPDATE="2025-08-10"
TOOL_REPO="GithubToolKit"

# 路径配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GIT_TOOLKIT_ROOT="$SCRIPT_DIR"

# 文件路径配置
CONFIG_FILE="$HOME/.github_toolkit_config"
REPO_CONFIG_FILE="$HOME/.github_repo_config"
REPO_CACHE_FILE="$HOME/.github_repo_cache"
PLATFORM_CONFIG_FILE="$HOME/.github_platform_config"
LOG_DIR="$HOME/log/github_toolkit"
LOG_FILE="$LOG_DIR/toolkit.log"
AUDIT_LOG_FILE="$LOG_DIR/audit.log"

# 缓存配置
REPO_CACHE_TIMEOUT=300

# API配置
API_URL="https://api.github.com/user/repos"
GITEE_API_URL="https://gitee.com/api/v5/user/repos"

# 默认值配置
DEFAULT_REPO_NAME="GithubToolKit"
DEFAULT_DESCRIPTION="一款通过Github API开发集成的Github多功能同步管理工具箱"
SYNC_DIR="/root/github_sync"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # 无颜色

# ====== 初始化日志系统 ======
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$AUDIT_LOG_FILE")"
touch "$LOG_FILE" "$AUDIT_LOG_FILE"
chmod 600 "$LOG_FILE" "$AUDIT_LOG_FILE"

# ====== 日志函数 ======
# 常规日志记录
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE" >/dev/null
}

# 同步操作审计日志
audit_log() {
    local action="$1"
    local target="$2"
    local action_desc=""
    case "$action" in
        "SYNC_TO_REPO")
            action_desc="同步内容到仓库 ($target)"
            ;;
        "DELETE_REPO")
            action_desc="删除仓库 ($target)"
            ;;
        "UPDATE_DESCRIPTION")
            action_desc="更新仓库描述 ($target)"
            ;;
        "CREATE_REPO")
            action_desc="创建新仓库 ($target)"
            ;;
        "PUSH_CHANGES")
            action_desc="推送更改到仓库 ($target)"
            ;;
        *)
            action_desc="未知操作 ($action)"
            ;;
    esac
    
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local log_entry="[$timestamp] $action_desc"
    echo "$log_entry" >> "$AUDIT_LOG_FILE"
}

# 用户操作审计日志
user_audit_log() {
    local action=$1
    local target=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [AUDIT] 用户: $USER, 操作: $action, 目标: $target" >> "$AUDIT_LOG_FILE"
}

# 等待用户继续
press_enter_to_continue() {
    echo -e "${BLUE}--------------------------------${NC}"
    read -p "按回车键返回菜单..." enter_key
}

# 处理API响应
handle_github_response() {
    local response="$1"
    local success_message="$2"
    
    if [ $? -ne 0 ]; then
        log "ERROR" "API请求失败"
        echo -e "${RED}❌ 请求失败，请检查网络${NC}"
        return 1
    fi
    
    local error_msg=$(echo "$response" | jq -r '.message')
    if [ "$error_msg" != "null" ] && [ "$error_msg" != "" ]; then
        log "ERROR" "API错误: $error_msg"
        echo -e "${RED}❌ 操作失败: $error_msg${NC}"
        return 1
    fi
    
    log "INFO" "$success_message"
    echo -e "${GREEN}✅ $success_message${NC}"
    return 0
}


# 清理无效缓存
clean_invalid_cache() {
    if [ -f "$REPO_CACHE_FILE" ]; then
        if [ ! -s "$REPO_CACHE_FILE" ] || ! jq empty "$REPO_CACHE_FILE" >/dev/null 2>&1; then
            log "WARN" "清理无效缓存文件: $REPO_CACHE_FILE"
            rm -f "$REPO_CACHE_FILE"
            echo -e "${YELLOW}⚠️ 清理无效缓存文件${NC}"
        fi
    fi
}

# 获取仓库列表
get_repo_list() {
    # 清理无效缓存
    clean_invalid_cache
    
    # 检查缓存是否有效
    if [ -f "$REPO_CACHE_FILE" ] && [ $(($(date +%s) - $(stat -c %Y "$REPO_CACHE_FILE"))) -lt $REPO_CACHE_TIMEOUT ]; then
        # 验证缓存内容有效性
        if jq empty "$REPO_CACHE_FILE" >/dev/null 2>&1; then
            cat "$REPO_CACHE_FILE"
            return 0
        else
            rm -f "$REPO_CACHE_FILE"
        fi
    fi
    
    local max_retries=3
    local retry_count=0
    local repos_json=""
    local http_code=""
    
    while [ $retry_count -lt $max_retries ]; do
        echo -e "${BLUE}📡 获取仓库列表... (尝试 $((retry_count+1))/${max_retries})${NC}"
        
        # 获取响应和HTTP状态码
        response=$(curl -s -w "\n%{http_code}" -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/user/repos?per_page=100")
        
        # 分离HTTP状态码和JSON内容
        http_code=$(echo "$response" | tail -n1)
        repos_json=$(echo "$response" | head -n -1)
        
        # 检查HTTP状态码
        if [ "$http_code" = "200" ]; then
            # 验证JSON格式
            if jq empty <<< "$repos_json" 2>/dev/null; then
                # 保存到缓存
                echo "$repos_json" > "$REPO_CACHE_FILE"
                echo "$repos_json"
                return 0
            else
                log "ERROR" "获取到无效JSON: $repos_json"
                echo -e "${YELLOW}⚠️ 获取到无效数据，重试中...${NC}"
            fi
        else
            error_msg=$(echo "$repos_json" | jq -r '.message' 2>/dev/null)
            log "ERROR" "API请求失败 (HTTP $http_code): ${error_msg:-未知错误}"
            echo -e "${RED}❌ API请求失败 (HTTP $http_code): ${error_msg:-未知错误}${NC}"
            
            # 如果是权限问题，直接返回错误
            if [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
                break
            fi
        fi
        
        sleep 2
        ((retry_count++))
    done
    
    # 详细错误处理
    if [ -n "$http_code" ]; then
        case $http_code in
            401)
                echo -e "${RED}❌ 认证失败: 请检查GitHub令牌是否有效${NC}"
                ;;
            403)
                rate_limit=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    https://api.github.com/rate_limit | jq '.rate.remaining')
                echo -e "${RED}❌ 请求被拒绝: 剩余API调用次数 $rate_limit${NC}"
                ;;
            *)
                echo -e "${RED}❌ 无法获取仓库列表 (HTTP $http_code)${NC}"
                ;;
        esac
    else
        echo -e "${RED}❌ 无法连接GitHub API，请检查网络${NC}"
    fi
    
    return 1
}

# 验证GitHub令牌
verify_github_token() {
    echo -e "${BLUE}🔐 验证 GitHub 令牌...${NC}"
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        https://api.github.com/user)
    
    if echo "$response" | jq -e '.login' >/dev/null; then
        username=$(echo "$response" | jq -r '.login')
        echo -e "${GREEN}✅ 令牌有效，用户: $username${NC}"
        
        # 检查令牌权限
        scopes=$(curl -s -I -H "Authorization: token $GITHUB_TOKEN" \
            https://api.github.com/user | grep -i 'X-OAuth-Scopes:' | cut -d' ' -f2- | tr -d '\r')
        
        if [[ "$scopes" != *"repo"* ]]; then
            echo -e "${YELLOW}⚠️ 令牌缺少repo权限，部分功能可能受限${NC}"
            echo -e "当前权限: $scopes"
        fi
        
        return 0
    else
        error=$(echo "$response" | jq -r '.message')
        echo -e "${RED}❌ 令牌无效: ${error}${NC}"
        return 1
    fi
}

# 检查令牌有效期
check_token_expiration() {
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        https://api.github.com/application)
    
    if expiration_date=$(echo "$response" | jq -r '.expires_at' 2>/dev/null); then
        if [ "$expiration_date" != "null" ]; then
            if [ "$(date -d "$expiration_date" +%s)" -lt "$(date +%s)" ]; then
                echo -e "${YELLOW}⚠️ 令牌已过期，请重新生成${NC}"
                return 1
            fi
            return 0
        fi
    fi
    return 0
}


# 检查系统依赖
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
