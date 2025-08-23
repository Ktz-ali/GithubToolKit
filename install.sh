#!/bin/bash

# GitHub工具箱模块化安装脚本
# 版本: 3.2.0
# 最后更新: 2025-08-04

# 安装目录
INSTALL_DIR="$HOME/GithubToolKit"
BIN_DIR="/usr/local/bin"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

# 检查是否以root运行
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本必须以root权限运行${NC}"
        exit 1
    fi
}

# 安装依赖函数
install_dependencies() {
    echo -e "${YELLOW}检测系统环境并安装依赖包...${NC}"
    
    # 识别系统类型
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        case $ID in
            debian|ubuntu)
                os_type="debian"
                ;;
            centos|rhel|fedora|rocky|almalinux)
                os_type="rhel"
                ;;
            opensuse*|sles)
                os_type="suse"
                ;;
            *)
                echo -e "${RED}错误: 不支持的操作系统: $ID${NC}"
                exit 1
                ;;
        esac
    elif [ -f /etc/redhat-release ]; then
        os_type="rhel"
    elif [ -f /etc/debian_version ]; then
        os_type="debian"
    else
        echo -e "${RED}错误: 无法识别操作系统${NC}"
        exit 1
    fi

    # 安装基础依赖
    case $os_type in
        debian)
            apt-get update > /dev/null
            apt-get install -y git curl jq > /dev/null
            ;;
        rhel)
            # 更彻底的 CentOS 7 镜像源修复
            if grep -q "CentOS Linux 7" /etc/os-release; then
                echo -e "${YELLOW}检测到 CentOS 7，进行深度镜像源修复...${NC}"
                
                # 备份原有仓库文件
                mkdir -p /etc/yum.repos.d/backup
                mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup/ 2>/dev/null
                
                # 创建新的可靠仓库配置
                cat > /etc/yum.repos.d/CentOS-Vault.repo << 'EOF'
[base]
name=CentOS-7 - Base (Vault)
baseurl=https://vault.centos.org/7.9.2009/os/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1

[updates]
name=CentOS-7 - Updates (Vault)
baseurl=https://vault.centos.org/7.9.2009/updates/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1

[extras]
name=CentOS-7 - Extras (Vault)
baseurl=https://vault.centos.org/7.9.2009/extras/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
enabled=1
EOF
                
                # 导入 GPG 密钥
                curl -s https://www.centos.org/keys/RPM-GPG-KEY-CentOS-7 -o /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
                
                # 强制清理缓存
                rm -rf /var/cache/yum/*
                yum clean all > /dev/null
                
                # 禁用所有其他仓库
                if [ -f /etc/yum/pluginconf.d/subscription-manager.conf ]; then
                    sed -i 's/enabled=1/enabled=0/' /etc/yum/pluginconf.d/subscription-manager.conf
                fi
                
                # 设置跳过不可用仓库
                echo "skip_if_unavailable=1" >> /etc/yum.conf
            fi
            
            # 安装依赖（增加重试机制）
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y --disablerepo=* --enablerepo=base --enablerepo=updates --enablerepo=extras git curl jq > /dev/null
            else
                yum install -y --disablerepo=* --enablerepo=base --enablerepo=updates --enablerepo=extras git curl jq > /dev/null
            fi
            ;;
        suse)
            zypper refresh > /dev/null
            zypper install -y git curl jq > /dev/null
            ;;
    esac

    # 检查安装结果
    for tool in git curl jq; do
        if ! command -v $tool >/dev/null 2>&1; then
            echo -e "${RED}错误: $tool 安装失败${NC}"
            # 对于 CentOS 7 提供额外诊断
            if grep -q "CentOS Linux 7" /etc/os-release 2>/dev/null; then
                echo -e "${YELLOW}尝试手动修复:"
                echo "1. 检查仓库配置: cat /etc/yum.repos.d/*.repo"
                echo "2. 手动清理缓存: yum clean all && rm -rf /var/cache/yum"
                echo "3. 尝试直接安装: yum install -y https://vault.centos.org/7.9.2009/os/x86_64/Packages/jq-1.6-2.el7.x86_64.rpm"
                echo "   (替换为当前架构的包)"
                echo -e "${NC}"
            fi
            exit 1
        fi
    done

    echo -e "${GREEN}✓ 依赖安装完成${NC}"
}




# 创建目录结构
create_directory_structure() {
    echo -e "${YELLOW}创建目录结构...${NC}"
    
    # 主安装目录
    mkdir -p "$INSTALL_DIR"
    
    # 子目录
    mkdir -p "$INSTALL_DIR/modules"
    
    # 日志目录
    mkdir -p "$HOME/log/github_toolkit"
    chmod 777 "$HOME/log/github_toolkit"
    
    echo -e "${GREEN}✓ 目录结构创建完成${NC}"
}

# 创建主菜单入口文件
create_main_script() {
cat > "$INSTALL_DIR/main.sh" << 'EOL'
#!/bin/bash

# GitHub工具箱主入口
VERSION="3.2.0"
LAST_UPDATE="2025-08-10"
TOOL_REPO="GithubToolKit"  # 工具箱的仓库名称

# 确保脚本使用bash执行
if [ -z "$BASH_VERSION" ]; then
    echo -e "${RED}错误: 请使用bash执行此脚本${NC}"
    exit 1
fi

# 加载配置和模块
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GIT_TOOLKIT_ROOT="$SCRIPT_DIR"

source "$GIT_TOOLKIT_ROOT/common.sh" # 通用函数库
source "$GIT_TOOLKIT_ROOT/modules/core.sh" # 核心功能模块
source "$GIT_TOOLKIT_ROOT/modules/warehouse.sh" # 仓库管理模块
source "$GIT_TOOLKIT_ROOT/modules/senior.sh" # 高级功能模块
source "$GIT_TOOLKIT_ROOT/modules/system.sh" # 系统功能模块
source "$GIT_TOOLKIT_ROOT/modules/platforms.sh" # 跨平台同步Gitee

# ====== 主程序 ======
main() {
    # 确保日志文件存在
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE" "$AUDIT_LOG_FILE"
    chmod 600 "$LOG_FILE" "$AUDIT_LOG_FILE"
    
    # 运行首次配置向导
    if first_run_wizard; then
        # 首次运行后加载配置
        load_config
        
        # 创建初始缓存文件
        touch "$REPO_CACHE_FILE"
    else
        load_config || {
            echo -e "${RED}❌ 无法加载配置文件${NC}"
            exit 1
        }
    fi
    
    # 验证令牌有效性
    if ! verify_github_token; then
        echo -e "${RED}❌ GitHub令牌无效或过期，请检查配置${NC}"
        press_enter_to_continue
        exit 1
    fi
    
    # 检查令牌有效期
    if ! check_token_expiration; then
        echo -e "${YELLOW}⚠️ 令牌已过期，部分功能可能受限${NC}"
    fi
    
    check_dependencies
    
    # 显示欢迎信息
    echo -e "${YELLOW}🔑 使用GitHub账号: $GITHUB_USER${NC}"
    if [ -n "$CURRENT_REPO" ]; then
        echo -e "${CYAN}📦 当前仓库: $CURRENT_REPO${NC}"
    fi
    
    # 预加载仓库列表
    echo -e "${BLUE}⏳ 预加载仓库列表...${NC}"
    get_repo_list > /dev/null 2>&1
    
    # 切换到指定同步目录
    if [ -n "$SYNC_DIR" ] && [ "$SYNC_DIR" != "." ]; then
        echo -e "${BLUE}切换到同步目录: $SYNC_DIR${NC}"
        mkdir -p "$SYNC_DIR"
        cd "$SYNC_DIR" || { echo -e "${RED}❌ 无法进入目录: $SYNC_DIR${NC}"; exit 1; }
    fi
    
    # 检查是否自动同步模式
    if [ "$1" == "--auto-sync" ]; then
        log "INFO" "自动同步任务启动"
        if push_changes; then
            log "INFO" "自动同步完成"
        else
            log "ERROR" "自动同步失败"
        fi
        exit 0
    fi
    
    show_menu
}

# ====== 主菜单 ======
show_menu() {
    while true; do
        clear
        echo -e "${BLUE}"
        echo "   ____ _ _   _   _       _          _   "
        echo "  / ___(_) |_| | | |_   _| |__   ___| |_ "
        echo " | |  _| | __| |_| | | | | '_ \ / _ \ __|"
        echo " | |_| | | |_|  _  | |_| | |_) |  __/ |_ "
        echo "  \____|_|\__|_| |_|\__,_|_.__/ \___|\__|"
        echo -e "${NC}"
        echo -e "${YELLOW} 遥辉GitHub 同步管理工具箱 v${VERSION} (${LAST_UPDATE})${NC}"
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${GREEN}同步目录: $SYNC_DIR${NC}"
        if [ -n "$CURRENT_REPO" ]; then
            echo -e "${CYAN}当前仓库: $CURRENT_REPO${NC}"
        fi
        echo -e "${BLUE}--------------------------------------------------${NC}"
        
        # 居中显示分类标题函数
        center_title() {
            local title="$1"
            local color="$2"
            local total_width=50
            local title_len=${#title}
            local padding_left=$(( (total_width - title_len) / 2 ))
            local padding_right=$(( total_width - title_len - padding_left ))
            
            printf "%${padding_left}s" | tr ' ' '='
            echo -ne "${color}${title}${NC}"
            printf "%${padding_right}s" | tr ' ' '='
            echo
        }
        
        # ====== 仓库操作管理 ======
        center_title " 仓库基本操作 " "${GREEN}"
        echo -e "${GREEN}01. 创建仓库并同步${NC}\t\t${GREEN}02. 克隆远程仓库${NC}"
        echo -e "${GREEN}03. 同步到现有仓库${NC}\t\t${GREEN}04. 更新仓库描述${NC}"
        echo -e "${GREEN}05. 删除项目仓库${NC}\t\t${GREEN}06. 仓库配置管理${NC}"
        
        # ====== 代码版本管理 ======
        center_title " 代码版本管理 " "${CYAN}"
        echo -e "${CYAN}07. 拉取远程更改${NC}\t\t${CYAN}08. 推送本地更改${NC}"
        echo -e "${CYAN}09. 本地分支管理${NC}\t\t${CYAN}10. 远程分支管理${NC}"
        echo -e "${CYAN}11. 标签发布管理${NC}\t\t${CYAN}12. 文件历史查看${NC}"
        
        # ====== 协作功能管理 ======
        center_title " 协作功能管理 " "${PURPLE}"
        echo -e "${PURPLE}13. 我的组织管理${NC}\t\t${PURPLE}14. 协作人员管理${NC}"
        echo -e "${PURPLE}15. 项目议题管理${NC}\t\t${PURPLE}16. 里程碑管理${NC}"
        echo -e "${PURPLE}17. 拉取请求管理${NC}\t\t${PURPLE}18. Webhook管理${NC}"
        
        # ====== 高级功能管理 ======
        center_title " 高级功能管理 " "${YELLOW}"
        echo -e "${YELLOW}19. 代码片段管理${NC}\t\t${YELLOW}20. 仓库状态管理${NC}"
        echo -e "${YELLOW}21. LFS储存管理${NC}\t\t\t${YELLOW}22. 仓库维护管理${NC}"
        echo -e "${YELLOW}23. 代码搜索功能${NC}\t\t${YELLOW}24. 仓库搜索管理${NC}"
        
        # ====== 跨平台同步管理 ======
        center_title " 跨平台同步管理 " "${BLUE}"
        echo -e "${BLUE}25. 跨平台同步${NC}\t\t\t${BLUE}26. 多平台镜像配置${NC}"
        
        # ====== 系统功能管理 ======
        center_title " 系统功能管理 " "${MAGENTA}"
        echo -e "${MAGENTA}27. 自动同步设置${NC}\t\t${MAGENTA}28. 系统状态信息${NC}"
        echo -e "${MAGENTA}29. 仓库统计与活动${NC}\t\t${MAGENTA}30. 系统资源监控${NC}"
        echo -e "${MAGENTA}31. 检查版本更新${NC}\t\t${MAGENTA}32. 工具箱诊断${NC}"
        echo -e "${MAGENTA}33. 日志查看器${NC}\t\t\t${RED}34. 退出工具箱${NC}"
        echo -e "${BLUE}==================================================${NC}"
        
        read -p "请选择操作 (1-34): " choice
        
        case $choice in
            01) create_and_sync_repo ;;
            02) clone_repository ;;
            03) sync_to_existing_repo ;;
            04) update_repo_description ;;
            05) delete_github_repo ;;
            06) list_configured_repos ;;
            07) pull_changes ;;
            08) push_changes ;;
            09) manage_local_branches ;;
            10) manage_branches ;;
            11) manage_tags ;;
            12) view_file_history ;;
            13) manage_organizations ;;
            14) manage_collaborators ;;
            15) manage_issues ;;
            16) manage_milestones ;;
            17) manage_pull_requests ;;
            18) view_webhooks ;;
            19) manage_gists ;;
            20) manage_repo_status ;;
            21) manage_git_lfs ;;
            22) repo_maintenance ;;
            23) search_code ;;
            24) search_repos ;;
            25) cross_platform_sync ;;
            26) setup_multi_platform_sync ;;
            27) setup_auto_sync ;;
            28) show_system_info ;;
            29) repo_stats_and_activity ;;
            30) monitor_system_resources ;;
            31) check_for_updates ;;
            32) diagnose_toolkit ;;
            33) view_logs ;;
            34) 
                echo -e "${BLUE}👋 退出程序${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ 无效选择，请重新输入${NC}"
                sleep 1
                ;;
        esac
    done
}

# 启动主程序
main "$@"
EOL

    chmod +x "$INSTALL_DIR/main.sh"
    echo -e "${GREEN}✓ 主菜单入口文件创建完成${NC}"
}


# 创建全局配置文件
create_config_script() {
    cat > "$INSTALL_DIR/common.sh" << 'EOL'
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

# URL编码
urlencode() {
    local string="${1}"
    local length=${#string}
    local char
    local encoded=""
    
    for (( i = 0; i < length; i++ )); do
        char="${string:i:1}"
        case "$char" in
            [a-zA-Z0-9.~_-]) encoded+="$char" ;;
            *) printf -v hex '%%%02X' "'$char"; encoded+="$hex" ;;
        esac
    done
    echo "$encoded"
}

# 检查Git状态
check_git_status() {
    if [ -n "$(git status --porcelain)" ]; then
        echo -e "${YELLOW}🔄 检测到未提交的更改:${NC}"
        git status -s
        return 0
    fi
    return 1
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
EOL
    echo -e "${GREEN}✓ 全局配置文件创建完成${NC}"
}

# 创建核心功能模块
create_core_module() {
cat > "$INSTALL_DIR/modules/core.sh" << 'EOL'
#!/bin/bash

# 仓库操作功能模块

# 加载配置和工具
source "$GIT_TOOLKIT_ROOT/common.sh"

# ====== 克隆远程仓库 ======
clone_repository() {
    read -p "🔗 输入要克隆的仓库URL: " repo_url
    if [[ -z "$repo_url" ]]; then
        echo -e "${RED}❌ 仓库URL不能为空${NC}"
        return 1
    fi

    # 提取仓库名称
    repo_name=$(basename "$repo_url" .git)

    read -p "📁 输入本地目录名称 (默认: $repo_name): " local_dir
    local_dir=${local_dir:-$repo_name}

    echo -e "${BLUE}⬇️ 正在克隆仓库...${NC}"
    if run_command "git clone $repo_url $local_dir"; then
        echo -e "${GREEN}✅ 仓库克隆成功${NC}"
        cd "$local_dir" || return 1
        # 将新仓库添加到配置
        add_repo_to_config "$repo_name" "$repo_url"
        return 0
    else
        echo -e "${RED}❌ 克隆失败${NC}"
        return 1
    fi
    press_enter_to_continue
}


# ====== 创建并同步新仓库 ======
create_and_sync_repo() {
    initialize_repo
    create_gitignore
    create_readme
    create_github_repo
    if [ -n "$REPO_URL" ]; then
        connect_and_push
        # 将新仓库添加到配置
        add_repo_to_config "$REPO_NAME" "$REPO_URL"
    fi
    press_enter_to_continue
}


# ====== 执行命令并处理错误 ======
run_command() {
    if ! eval "$@" > /dev/null 2>&1; then
        log "ERROR" "命令执行失败: $@"
        echo -e "${RED}❌ 命令执行失败: $@${NC}"
        return 1
    fi
    return 0
}

# ====== 仓库操作 ======
initialize_repo() {
    if [ ! -d ".git" ]; then
        echo -e "${BLUE}🛠️ 初始化Git仓库...${NC}"
        run_command "git init" || return 1
        run_command "git add ." || return 1
        run_command 'git commit -m "Initial commit"' || return 1
        echo -e "${GREEN}✅ Git仓库初始化完成${NC}"
    else
        echo -e "${GREEN}✅ Git仓库已存在${NC}"
    fi
    return 0
}


# 创建.gitignore文件
create_gitignore() {
    if [ ! -f ".gitignore" ]; then
        cat << EOF > .gitignore
# 忽略文件
__pycache__/
*.pyc
*.log
*.tmp
output/
temp/
.env
*.apk
*.keystore
secrets.txt
EOF
        echo -e "${GREEN}✅ .gitignore文件已创建${NC}"
    else
        echo -e "${GREEN}✅ .gitignore文件已存在${NC}"
    fi
}


# ====== 创建README.md ======
create_readme() {
    if [ ! -f "README.md" ]; then
        echo -e "${BLUE}📝 创建README.md文件...${NC}"
        cat << EOF > README.md
# $REPO_NAME

$REPO_DESCRIPTION

## 项目概述
这是一个使用GitHub工具箱创建的仓库

## 功能特性
- 功能1
- 功能2
- 功能3

## 安装使用
\`\`\`bash
git clone $REPO_URL
cd $REPO_NAME
\`\`\`

## 贡献指南
欢迎提交Pull Request

## 许可证
[MIT](LICENSE)
EOF
        echo -e "${GREEN}✅ README.md文件已创建${NC}"
        
        # 将README.md添加到Git
        run_command "git add README.md" || return 1
        run_command 'git commit -m "添加 README.md"' || return 1
    else
        echo -e "${GREEN}✅ README.md文件已存在${NC}"
    fi
    return 0
}

# ====== 创建GitHub仓库 ======
create_github_repo() {
    read -p "📝 输入仓库名称 (默认: ${DEFAULT_REPO_NAME}): " repo_name
    repo_name=${repo_name:-$DEFAULT_REPO_NAME}
    REPO_NAME=$repo_name
    
    read -p "📝 输入仓库描述 (默认: ${DEFAULT_DESCRIPTION}): " repo_description
    repo_description=${repo_description:-$DEFAULT_DESCRIPTION}
    REPO_DESCRIPTION=$repo_description
    
    read -p "🔒 是否设为私有仓库? (y/N): " private_input
    private_input=${private_input:-n}
    [[ "$private_input" =~ ^[Yy]$ ]] && private="true" || private="false"
    
    read -p "🪝 是否启用Git LFS? (y/N): " lfs_input
    lfs_input=${lfs_input:-n}
    
    echo -e "${BLUE}🚀 正在创建仓库 $repo_name...${NC}"
    
    response=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{
            \"name\": \"$repo_name\",
            \"description\": \"$repo_description\",
            \"private\": $private,
            \"auto_init\": false
        }" $API_URL)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 创建仓库失败: 网络错误${NC}"
        return 1
    fi
    
    error_msg=$(echo "$response" | jq -r '.message')
    if [ "$error_msg" != "null" ]; then
        echo -e "${RED}❌ 创建仓库失败: $error_msg${NC}"
        return 1
    fi
    
    remote_url=$(echo "$response" | jq -r '.clone_url')
    if [ -z "$remote_url" ] || [ "$remote_url" = "null" ]; then
        echo -e "${RED}❌ 无法获取仓库URL${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✅ 仓库创建成功: $remote_url${NC}"
    REPO_URL=$remote_url
    
    # 启用Git LFS
    if [[ "$lfs_input" =~ ^[Yy]$ ]]; then
        setup_git_lfs
    fi
    
    return 0
}

# ====== 设置Git LFS ======
setup_git_lfs() {
    command -v git-lfs &>/dev/null || {
        echo -e "${YELLOW}⚠️ Git LFS 未安装，尝试安装...${NC}"
        sudo apt-get install git-lfs -y > /dev/null 2>&1 || {
            echo -e "${RED}❌ 安装Git LFS失败${NC}"
            return 1
        }
    }
    git lfs install
    echo -e "${GREEN}✅ Git LFS 已启用${NC}"
    
    # 添加LFS跟踪规则示例
    git lfs track "*.psd" "*.zip" "*.bin"
    git add .gitattributes
    git commit -m "添加Git LFS跟踪规则"
    echo -e "${GREEN}✅ 已添加LFS跟踪规则${NC}"
}

# ====== 连接并推送代码 ======
connect_and_push() {
    if [ -z "$REPO_URL" ]; then
        echo -e "${RED}❌ 未设置远程仓库URL${NC}"
        return 1
    fi
    
    echo -e "${BLUE}🔗 连接远程仓库...${NC}"
    
    # 提取仓库路径（去掉 https://）
    repo_path=${REPO_URL#https://}
    
    # 创建带认证令牌的正确格式URL
    AUTH_REPO_URL="https://$GITHUB_USER:$GITHUB_TOKEN@$repo_path"
    
    # 如果已存在origin远程仓库，则先移除
    if git remote | grep -q origin; then
        run_command "git remote remove origin" || echo -e "${YELLOW}⚠️ 移除现有origin远程仓库失败，继续尝试...${NC}"
    fi
    
    run_command "git remote add origin \"$AUTH_REPO_URL\"" || return 1
    run_command "git branch -M main" || return 1
    
    echo -e "${BLUE}🚀 推送代码到GitHub...${NC}"
    if run_command "git push -u origin main"; then
        echo -e "${GREEN}✅ 代码推送成功${NC}"
        return 0
    else
        echo -e "${RED}❌ 推送失败${NC}"
        return 1
    fi
}

# ====== 重命名仓库功能 ======
rename_repository() {
    # 获取仓库列表
    repo_json=$(get_repo_list)
    if [ -z "$repo_json" ]; then
        echo -e "${RED}❌ 无法获取仓库列表${NC}"
        press_enter_to_continue
        return
    fi

    # 解析仓库列表
    mapfile -t repo_array < <(echo "$repo_json" | jq -r '.[] | "\(.id) \(.name)"')

    # 显示仓库列表
    echo -e "\n${YELLOW}选择仓库:${NC}"
    echo "--------------------------------"
    printf "%-5s %s\n" "序号" "仓库名称"
    echo "--------------------------------"
    for i in "${!repo_array[@]}"; do
        repo_info=(${repo_array[$i]})
        printf "%-5s %s\n" "$((i+1))" "${repo_info[1]}"
    done
    echo "--------------------------------"

    read -p "➡️ 输入要重命名的仓库序号: " repo_index
    if [[ ! "$repo_index" =~ ^[0-9]+$ ]] || [ "$repo_index" -lt 1 ] || [ "$repo_index" -gt "${#repo_array[@]}" ]; then
        echo -e "${RED}❌ 无效的仓库序号${NC}"
        press_enter_to_continue
        return
    fi

    # 获取仓库名称
    repo_info=(${repo_array[$((repo_index-1))]})
    repo_name=${repo_info[1]}
    encoded_repo=$(urlencode "$repo_name")

    # 输入新仓库名
    read -p "📝 输入新的仓库名称: " new_repo_name
    if [ -z "$new_repo_name" ]; then
        echo -e "${RED}❌ 新仓库名称不能为空${NC}"
        press_enter_to_continue
        return
    fi

    # 检查新名称是否已存在
    repo_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USER/$new_repo_name")

    if [ "$(echo "$repo_info" | jq -r '.message')" != "Not Found" ]; then
        echo -e "${RED}❌ 仓库 $new_repo_name 已存在${NC}"
        press_enter_to_continue
        return
    fi

    # 重命名仓库
    response=$(curl -s -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{\"name\": \"$new_repo_name\"}" \
        "https://api.github.com/repos/$GITHUB_USER/$repo_name")

    error_msg=$(echo "$response" | jq -r '.message')
    if [ "$error_msg" != "null" ]; then
        echo -e "${RED}❌ 重命名失败: $error_msg${NC}"
    else
        echo -e "${GREEN}✅ 仓库 '$repo_name' 已重命名为 '$new_repo_name'${NC}"
        user_audit_log "RENAME_REPO" "$repo_name -> $new_repo_name"
        # 更新仓库配置文件
        if grep -q "^$repo_name|" "$REPO_CONFIG_FILE"; then
            sed -i "s|^$repo_name|$new_repo_name|" "$REPO_CONFIG_FILE"
        fi
    fi
    press_enter_to_continue
}


# ====== 删除GitHub仓库 ======
delete_github_repo() {
    # 获取仓库列表
    repo_json=$(get_repo_list)
    if [ -z "$repo_json" ]; then
        echo -e "${RED}❌ 无法获取仓库列表${NC}"
        return
    fi
    
    # 解析仓库列表
    mapfile -t repo_array < <(echo "$repo_json" | jq -r '.[] | "\(.id) \(.name)"')
    
    # 显示仓库列表
    echo -e "\n${YELLOW}可删除的仓库列表:${NC}"
    echo "--------------------------------"
    printf "%-5s %s\n" "序号" "仓库名称"
    echo "--------------------------------"
    for i in "${!repo_array[@]}"; do
        repo_info=(${repo_array[$i]})
        printf "%-5s %s\n" "$((i+1))" "${repo_info[1]}"
    done
    echo "--------------------------------"
    
    read -p "➡️ 输入要删除的仓库序号: " repo_index
    if [[ ! "$repo_index" =~ ^[0-9]+$ ]] || [ "$repo_index" -lt 1 ] || [ "$repo_index" -gt "${#repo_array[@]}" ]; then
        echo -e "${RED}❌ 无效的仓库序号${NC}"
        return
    fi
    
    # 获取仓库ID和名称
    repo_info=(${repo_array[$((repo_index-1))]})
    repo_id=${repo_info[0]}
    repo_name=${repo_info[1]}
    
    read -p "⚠️ 确定要永久删除仓库 '$repo_name' 吗? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo -e "${YELLOW}❌ 取消删除操作${NC}"; return; }
    
    # URL编码仓库名称
    encoded_repo_name=$(urlencode "$repo_name")
    
    delete_url="https://api.github.com/repos/$GITHUB_USER/$encoded_repo_name"
    response=$(curl -s -i -X DELETE \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        $delete_url)
    
    if [[ "$response" == *"HTTP/2 204"* ]] || [[ "$response" == *"HTTP/1.1 204"* ]]; then
        echo -e "${GREEN}✅ 仓库 '$repo_name' 已删除${NC}"
        audit_log "DELETE_REPO" "$repo_name"
        # 从配置中移除
        remove_repo_from_config "$repo_name"
        # 清除缓存
        rm -f "$REPO_CACHE_FILE"
    elif [[ "$response" == *"HTTP/2 404"* ]] || [[ "$response" == *"HTTP/1.1 404"* ]]; then
        echo -e "${RED}❌ 仓库不存在: '$repo_name'${NC}"
    else
        echo -e "${RED}❌ 删除失败${NC}"
        echo "$response"
    fi
    press_enter_to_continue
}

# ====== 更新仓库描述 ======
update_repo_description() {
    # 获取仓库列表
    repo_json=$(get_repo_list)
    if [ -z "$repo_json" ]; then
        echo -e "${RED}❌ 无法获取仓库列表${NC}"
        return
    fi
    
    # 解析仓库列表
    mapfile -t repo_array < <(echo "$repo_json" | jq -r '.[] | "\(.id) \(.name)"')
    
    # 显示仓库列表
    echo -e "\n${YELLOW}可更新的仓库列表:${NC}"
    echo "--------------------------------"
    printf "%-5s %s\n" "序号" "仓库名称"
    echo "--------------------------------"
    for i in "${!repo_array[@]}"; do
        repo_info=(${repo_array[$i]})
        printf "%-5s %s\n" "$((i+1))" "${repo_info[1]}"
    done
    echo "--------------------------------"
    
    read -p "➡️ 输入要更新的仓库序号: " repo_index
    if [[ ! "$repo_index" =~ ^[0-9]+$ ]] || [ "$repo_index" -lt 1 ] || [ "$repo_index" -gt "${#repo_array[@]}" ]; then
        echo -e "${RED}❌ 无效的仓库序号${NC}"
        return
    fi
    
    # 获取仓库ID和名称
    repo_info=(${repo_array[$((repo_index-1))]})
    repo_id=${repo_info[0]}
    repo_name=${repo_info[1]}
    
    # URL编码仓库名称
    encoded_repo_name=$(urlencode "$repo_name")
    
    # 获取当前描述
    current_desc=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$GITHUB_USER/$encoded_repo_name" | jq -r '.description')
    
    echo -e "\n${YELLOW}当前描述: ${NC}$current_desc"
    read -p "📝 输入新的仓库描述: " new_description
    if [ -z "$new_description" ]; then
        echo -e "${RED}❌ 描述不能为空${NC}"
        return
    fi
    
    update_url="https://api.github.com/repos/$GITHUB_USER/$encoded_repo_name"
    response=$(curl -s -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{\"description\": \"$new_description\"}" \
        $update_url)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 更新请求失败${NC}"
        return
    fi
    
    error_msg=$(echo "$response" | jq -r '.message')
    if [ "$error_msg" != "null" ]; then
        echo -e "${RED}❌ 更新失败: $error_msg${NC}"
    else
        echo -e "${GREEN}✅ 仓库 '$repo_name' 描述已更新: $new_description${NC}"
        audit_log "UPDATE_DESCRIPTION" "$repo_name"
        # 清除缓存
        rm -f "$REPO_CACHE_FILE"
    fi
    press_enter_to_continue
}



# ====== 同步到现有仓库 ======
sync_to_existing_repo() {
    # 检查当前目录是否是Git仓库
    if [ ! -d ".git" ]; then
        echo -e "${RED}❌ 当前目录不是Git仓库${NC}"
        return 1
    fi

    # 获取仓库列表
    repo_json=$(get_repo_list)
    if [ -z "$repo_json" ]; then
        echo -e "${RED}❌ 无法获取仓库列表${NC}"
        return 1
    fi

    # 解析仓库列表
    mapfile -t repo_array < <(echo "$repo_json" | jq -r '.[] | "\(.id) \(.name)"')
    
    # 显示仓库列表
    echo -e "\n${YELLOW}可同步的仓库列表:${NC}"
    echo "--------------------------------"
    printf "%-5s %s\n" "序号" "仓库名称"
    echo "--------------------------------"
    for i in "${!repo_array[@]}"; do
        repo_info=(${repo_array[$i]})
        printf "%-5s %s\n" "$((i+1))" "${repo_info[1]}"
    done
    echo "--------------------------------"
    
    read -p "➡️ 输入要同步的仓库序号: " repo_index
    if [[ ! "$repo_index" =~ ^[0-9]+$ ]] || [ "$repo_index" -lt 1 ] || [ "$repo_index" -gt "${#repo_array[@]}" ]; then
        echo -e "${RED}❌ 无效的仓库序号${NC}"
        return 1
    fi
    
    # 获取仓库名称
    repo_info=(${repo_array[$((repo_index-1))]})
    repo_name=${repo_info[1]}
    
    # 验证仓库存在
    encoded_repo_name=$(urlencode "$repo_name")
    repo_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$GITHUB_USER/$encoded_repo_name")
    
    if [ "$(echo "$repo_info" | jq -r '.message')" == "Not Found" ]; then
        echo -e "${RED}❌ 仓库 '$repo_name' 不存在${NC}"
        return 1
    fi
    
    # 获取仓库URL
    REPO_URL=$(echo "$repo_info" | jq -r '.clone_url')
    if [ -z "$REPO_URL" ] || [ "$REPO_URL" == "null" ]; then
        echo -e "${RED}❌ 无法获取仓库URL${NC}"
        return 1
    fi
    
    # 添加远程仓库
    if git remote | grep -q origin; then
        read -p "⚠️ 已存在origin远程仓库，是否覆盖? (y/N): " overwrite
        if [[ "$overwrite" =~ ^[Yy]$ ]]; then
            run_command "git remote remove origin" || return 1
        else
            echo -e "${YELLOW}❌ 取消同步操作${NC}"
            return 1
        fi
    fi
    
    # 添加带认证的远程URL
    repo_path=${REPO_URL#https://}
    AUTH_REPO_URL="https://$GITHUB_USER:$GITHUB_TOKEN@$repo_path"
    run_command "git remote add origin \"$AUTH_REPO_URL\"" || return 1
    
    # 设置分支并推送
    run_command "git branch -M main" || return 1
    echo -e "${BLUE}🚀 正在推送代码到仓库 '$repo_name'...${NC}"
    
    if run_command "git push -u origin main"; then
        echo -e "${GREEN}✅ 代码同步成功${NC}"
        # 将新仓库添加到配置
        add_repo_to_config "$repo_name" "$REPO_URL"
        # 更新当前仓库
        save_config_key "CURRENT_REPO" "$repo_name"
        return 0
    else
        echo -e "${RED}❌ 同步失败${NC}"
        return 1
    fi
    press_enter_to_continue
}


# ====== 推送本地更改到GitHub仓库 ======
push_changes() {
    # 检查当前目录是否是Git仓库
    if [ ! -d ".git" ]; then
        echo -e "${RED}❌ 当前目录不是Git仓库${NC}"
        press_enter_to_continue
        return 1
    fi
    
    # 检查是否有未提交的更改
    if ! check_git_status; then
        echo -e "${GREEN}✅ 没有检测到未提交的更改${NC}"
        press_enter_to_continue
        return 0
    fi
    
    echo -e "${BLUE}📝 检测到未提交的更改:${NC}"

git status -s | while IFS= read -r line; do
 
    decoded_line=$(echo "$line" | sed 's/\\//g' | xxd -r -p 2>/dev/null)
    # 尝试转换编码
    converted_line=$(echo "$decoded_line" | iconv -f UTF-8 -t UTF-8//IGNORE 2>/dev/null || echo "$line")
    echo "$converted_line"
done
    
    read -p "🔄 是否提交这些更改? (Y/n): " commit_choice
    commit_choice=${commit_choice:-Y}
    
    if [[ ! "$commit_choice" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}❌ 取消提交操作${NC}"
        press_enter_to_continue
        return 1
    fi
    
    read -p "📝 输入提交信息: " commit_message
    if [ -z "$commit_message" ]; then
        commit_message="自动提交更新"
    fi
    
    echo -e "${BLUE}🔄 正在提交更改...${NC}"
    run_command "git add ." || return 1
    run_command "git commit -m \"$commit_message\"" || return 1
    
    # 获取当前远程URL
    current_url=$(git config --get remote.origin.url)
    
    # 正确解析仓库路径
    if [[ $current_url == https://* ]]; then
        repo_path=${current_url#https://}
        clean_path=${repo_path#*@}
        AUTH_REPO_URL="https://$GITHUB_USER:$GITHUB_TOKEN@$clean_path"
    elif [[ $current_url == git@* ]]; then
        repo_domain=$(echo "$current_url" | sed 's/git@//; s/:/\//; s/\.git$//')
        repo_name=$(basename "$repo_domain")
        repo_owner=$(dirname "$repo_domain")
        AUTH_REPO_URL="https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$repo_owner/$repo_name.git"
    else
        echo -e "${RED}❌ 不支持的远程仓库URL格式${NC}"
        press_enter_to_continue
        return 1
    fi
    
    # 设置带认证的远程URL
    if ! git remote set-url origin "$AUTH_REPO_URL" > /dev/null 2>&1; then
        echo -e "${RED}❌ 设置远程仓库URL失败${NC}"
        press_enter_to_continue
        return 1
    fi
    
    # 获取当前分支（兼容旧版Git）
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -z "$current_branch" ]; then
        echo -e "${RED}❌ 无法确定当前分支${NC}"
        return 1
    fi
    
    echo -e "${BLUE}🚀 正在推送更改到GitHub...${NC}"
    if run_command "git push origin $current_branch"; then
        echo -e "${GREEN}✅ 代码推送成功${NC}"
        # 恢复原始URL
        git remote set-url origin "$current_url" > /dev/null 2>&1
        # 审计日志
        repo_name=$(basename -s .git "$(git config --get remote.origin.url)")
        audit_log "PUSH_CHANGES" "$repo_name"
        press_enter_to_continue
        return 0
    else
        echo -e "${RED}❌ 推送失败${NC}"
        # 恢复原始URL
        git remote set-url origin "$current_url" > /dev/null 2>&1
        press_enter_to_continue
        return 1
    fi
}


# ====== 拉取远程更改 ======
pull_changes() {
    # 检查当前目录是否是Git仓库
    if [ ! -d ".git" ]; then
        echo -e "${RED}❌ 当前目录不是Git仓库${NC}"
        press_enter_to_continue
        return 1
    fi
    
    # 检查是否有远程仓库
    if ! git remote | grep -q origin; then
        echo -e "${RED}❌ 没有配置远程仓库，请先创建并同步新仓库${NC}"
        press_enter_to_continue
        return 1
    fi
    
    echo -e "${BLUE}🔄 正在检查远程更新...${NC}"
    
    # 获取当前远程URL
    current_url=$(git config --get remote.origin.url)
    
    # 正确解析仓库路径
    if [[ $current_url == https://* ]]; then
        repo_path=${current_url#https://}
        clean_path=${repo_path#*@}
        AUTH_REPO_URL="https://$GITHUB_USER:$GITHUB_TOKEN@$clean_path"
    elif [[ $current_url == git@* ]]; then
        repo_domain=$(echo "$current_url" | sed 's/git@//; s/:/\//; s/\.git$//')
        repo_name=$(basename "$repo_domain")
        repo_owner=$(dirname "$repo_domain")
        AUTH_REPO_URL="https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$repo_owner/$repo_name.git"
    else
        echo -e "${RED}❌ 不支持的远程仓库URL格式${NC}"
        press_enter_to_continue
        return 1
    fi
    
    # 设置带认证的远程URL
    if ! git remote set-url origin "$AUTH_REPO_URL" > /dev/null 2>&1; then
        echo -e "${RED}❌ 设置远程仓库URL失败${NC}"
        press_enter_to_continue
        return 1
    fi
    
    # 执行拉取操作并简化输出
    if git pull --quiet > /dev/null 2>&1; then
        # 检查是否有更新
        if git status | grep -q "Your branch is up to date"; then
            echo -e "${GREEN}✅ 已是最新版本，没有可更新的内容${NC}"
        else
            echo -e "${GREEN}✅ 更新成功，已同步最新更改${NC}"
        fi
        # 恢复原始URL
        git remote set-url origin "$current_url" > /dev/null 2>&1
    else
        echo -e "${RED}❌ 更新失败，请检查网络连接或仓库权限${NC}"
        # 恢复原始URL
        git remote set-url origin "$current_url" > /dev/null 2>&1
    fi
    
    press_enter_to_continue
    return 0
}


# ====== 本地分支管理 ======
manage_local_branches() {
    # 检查当前目录是否是Git仓库
    if [ ! -d ".git" ]; then
        echo -e "${RED}❌ 当前目录不是Git仓库${NC}"
        press_enter_to_continue
        return 1
    fi

    while true; do
        clear
        echo -e "${BLUE}===================================${NC}"
        echo -e "${YELLOW}          本地分支管理${NC}"
        echo -e "${BLUE}===================================${NC}"
        echo "1. 查看分支列表"
        echo "2. 创建分支"
        echo "3. 切换分支"
        echo "4. 删除分支"
        echo "5. 合并分支"
        echo -e "${YELLOW}6. 返回主菜单${NC}"
        echo -e "${BLUE}===================================${NC}"

        read -p "请选择操作: " choice

        case $choice in
            1)
                # 查看分支
                echo -e "${GREEN}本地分支:${NC}"
                git branch
                echo -e "\n${GREEN}远程分支:${NC}"
                git branch -r
                press_enter_to_continue
                ;;
            2)
                read -p "输入新分支名称: " branch_name
                if git checkout -b "$branch_name"; then
                    echo -e "${GREEN}✅ 分支创建成功${NC}"
                else
                    echo -e "${RED}❌ 创建分支失败${NC}"
                fi
                press_enter_to_continue
                ;;
            3)
                read -p "输入要切换的分支名称: " branch_name
                if git checkout "$branch_name"; then
                    echo -e "${GREEN}✅ 切换成功${NC}"
                else
                    echo -e "${RED}❌ 切换失败${NC}"
                fi
                press_enter_to_continue
                ;;
            4)
                read -p "输入要删除的分支名称: " branch_name
                # 不能删除当前分支
                current_branch=$(git branch --show-current)
                if [ "$current_branch" == "$branch_name" ]; then
                    echo -e "${RED}❌ 不能删除当前分支，请先切换到其他分支${NC}"
                else
                    if git branch -d "$branch_name"; then
                        echo -e "${GREEN}✅ 删除分支成功${NC}"
                    else
                        echo -e "${RED}❌ 删除失败，请确认分支是否存在且已经合并${NC}"
                    fi
                fi
                press_enter_to_continue
                ;;
            5)
                read -p "输入要合并的分支名称: " branch_name
                if git merge "$branch_name"; then
                    echo -e "${GREEN}✅ 合并成功${NC}"
                else
                    echo -e "${RED}❌ 合并失败，请解决冲突后提交${NC}"
                fi
                press_enter_to_continue
                ;;
            6) return ;;
            *)
                echo -e "${RED}❌ 无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}
EOL

    echo -e "${GREEN}✓ 核心功能模块创建完成${NC}"
}


# 创建仓库管理模块
create_warehouse_module() {
cat > "$INSTALL_DIR/modules/warehouse.sh" << 'EOL'
#!/bin/bash

# 仓库管理模块

# 使用绝对路径加载配置和工具
source "$GIT_TOOLKIT_ROOT/common.sh"

# ====== 搜索仓库功能 ======
search_repos() {
    echo -e "${BLUE}选择搜索范围:${NC}"
    echo "1. 搜索自己的仓库"
    echo "2. 搜索公共仓库"
    read -p "请选择 (默认: 1): " scope_choice
    scope_choice=${scope_choice:-1}

    read -p "🔍 输入搜索关键词: " search_term
    if [ -z "$search_term" ]; then
        echo -e "${RED}❌ 搜索词不能为空${NC}"
        press_enter_to_continue
        return
    fi

    # 添加语言过滤选项
    echo -e "${BLUE}选择语言过滤:${NC}"
    echo "0. 无过滤"
    echo "1. JavaScript"
    echo "2. Python"
    echo "3. Java"
    echo "4. Go"
    echo "5. Shell"
    read -p "请选择 (默认: 0): " lang_choice
    lang_choice=${lang_choice:-0}
    
    # 映射语言选择到实际值
    case $lang_choice in
        1) lang="javascript";;
        2) lang="python";;
        3) lang="java";;
        4) lang="go";;
        5) lang="shell";;
        *) lang="";;
    esac

    encoded_search=$(urlencode "$search_term")
    
    if [ "$scope_choice" -eq 1 ]; then
        # 搜索自己的仓库
        echo -e "${BLUE}🔍 正在搜索自己的仓库: $search_term...${NC}"
        url="https://api.github.com/search/repositories?q=$encoded_search+user:$GITHUB_USER"
    else
        # 搜索公共仓库
        echo -e "${BLUE}🔍 正在搜索公共仓库: $search_term...${NC}"
        url="https://api.github.com/search/repositories?q=$encoded_search"
    fi
    
    # 添加语言过滤
    if [ -n "$lang" ]; then
        url+="+language:$lang"
    fi

    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "$url")
    
    count=$(echo "$response" | jq '.total_count')
    if [ -z "$count" ] || [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}🔍 未找到匹配的仓库${NC}"
        press_enter_to_continue
        return
    fi
    
    echo -e "\n${GREEN}🔍 找到 $count 个匹配的仓库:${NC}"
    echo "--------------------------------"
    echo "$response" | jq -r '.items[] | "\(.name) - \(.language): \(.description // "无描述")"'
    echo "--------------------------------"
    press_enter_to_continue
}

# ====== 管理议题功能 ======
manage_issues() {
    # 获取仓库列表
    repo_json=$(get_repo_list)
    if [ -z "$repo_json" ]; then
        echo -e "${RED}❌ 无法获取仓库列表${NC}"
        press_enter_to_continue
        return
    fi
    
    # 解析仓库列表
    mapfile -t repo_array < <(echo "$repo_json" | jq -r '.[] | "\(.id) \(.name)"')
    
    # 显示仓库列表
    echo -e "\n${YELLOW}选择仓库:${NC}"
    echo "--------------------------------"
    printf "%-5s %s\n" "序号" "仓库名称"
    echo "--------------------------------"
    for i in "${!repo_array[@]}"; do
        repo_info=(${repo_array[$i]})
        printf "%-5s %s\n" "$((i+1))" "${repo_info[1]}"
    done
    echo "--------------------------------"
    
    read -p "➡️ 输入仓库序号: " repo_index
    if [[ ! "$repo_index" =~ ^[0-9]+$ ]] || [ "$repo_index" -lt 1 ] || [ "$repo_index" -gt "${#repo_array[@]}" ]; then
        echo -e "${RED}❌ 无效的仓库序号${NC}"
        press_enter_to_continue
        return
    fi
    
    # 获取仓库名称
    repo_info=(${repo_array[$((repo_index-1))]})
    repo_name=${repo_info[1]}
    
    while true; do
        clear
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${YELLOW}          议题管理: ${CYAN}$repo_name${NC}"
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${CYAN}1. 查看议题${NC}"
        echo -e "${CYAN}2. 创建新议题${NC}"
        echo -e "${CYAN}3. 关闭议题${NC}"
        echo -e "${YELLOW}4. 返回仓库管理菜单${NC}"
        echo -e "${BLUE}==================================================${NC}"
        
        read -p "选择操作 (1-4): " issue_choice
        
        case $issue_choice in
            1)
                # 查看议题
                echo -e "${BLUE}📝 正在获取议题列表...${NC}"
                encoded_repo=$(urlencode "$repo_name")
                issues=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/issues?state=all")
                
                count=$(echo "$issues" | jq 'length')
                if [ "$count" -eq 0 ]; then
                    echo -e "${YELLOW}📝 该仓库没有议题${NC}"
                else
                    echo -e "\n${GREEN}📝 议题列表:${NC}"
                    echo "--------------------------------"
                    echo "$issues" | jq -r '.[] | "#\(.number): \(.title) [状态: \(.state)]"'
                    echo "--------------------------------"
                    
                    read -p "输入议题编号查看详情 (留空返回): " issue_number
                    if [ -n "$issue_number" ]; then
                        view_issue_detail "$repo_name" "$issue_number"
                    fi
                fi
                press_enter_to_continue
                ;;
            2)
                # 创建新议题
                read -p "📝 输入议题标题: " issue_title
                read -p "📝 输入议题描述: " issue_body
                
                if [ -z "$issue_title" ]; then
                    echo -e "${RED}❌ 议题标题不能为空${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                encoded_repo=$(urlencode "$repo_name")
                response=$(curl -s -X POST \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d "{
                        \"title\": \"$issue_title\",
                        \"body\": \"$issue_body\"
                    }" "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/issues")
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ 创建议题失败${NC}"
                else
                    error_msg=$(echo "$response" | jq -r '.message')
                    if [ "$error_msg" != "null" ]; then
                        echo -e "${RED}❌ 创建议题失败: $error_msg${NC}"
                    else
                        issue_url=$(echo "$response" | jq -r '.html_url')
                        echo -e "${GREEN}✅ 议题创建成功: $issue_url${NC}"
                        user_audit_log "CREATE_ISSUE" "$repo_name/$issue_title"
                    fi
                fi
                press_enter_to_continue
                ;;
            3)
                # 关闭议题
                echo -e "${BLUE}📝 获取开放中的议题...${NC}"
                encoded_repo=$(urlencode "$repo_name")
                open_issues=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/issues?state=open")
                
                count=$(echo "$open_issues" | jq 'length')
                if [ "$count" -eq 0 ]; then
                    echo -e "${YELLOW}📝 该仓库没有开放中的议题${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                echo -e "\n${GREEN}开放中的议题:${NC}"
                echo "--------------------------------"
                echo "$open_issues" | jq -r '.[] | "#\(.number): \(.title)"'
                echo "--------------------------------"
                
                read -p "输入要关闭的议题编号: " issue_number
                if [ -z "$issue_number" ]; then
                    echo -e "${RED}❌ 议题编号不能为空${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                response=$(curl -s -X PATCH \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d '{"state": "closed"}' \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/issues/$issue_number")
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ 关闭议题失败${NC}"
                else
                    error_msg=$(echo "$response" | jq -r '.message')
                    if [ "$error_msg" != "null" ]; then
                        echo -e "${RED}❌ 关闭失败: $error_msg${NC}"
                    else
                        echo -e "${GREEN}✅ 议题 #$issue_number 已关闭${NC}"
                        user_audit_log "CLOSE_ISSUE" "$repo_name/$issue_number"
                    fi
                fi
                press_enter_to_continue
                ;;
            4) return ;;
            *) 
                echo -e "${RED}❌ 无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# ====== 查看议题详情 ======
view_issue_detail() {
    local repo_name=$1
    local issue_number=$2
    encoded_repo=$(urlencode "$repo_name")
    
    issue=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/issues/$issue_number")
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 获取议题详情失败${NC}"
        return
    fi
    
    title=$(echo "$issue" | jq -r '.title')
    state=$(echo "$issue" | jq -r '.state')
    creator=$(echo "$issue" | jq -r '.user.login')
    created_at=$(echo "$issue" | jq -r '.created_at' | cut -d'T' -f1)
    updated_at=$(echo "$issue" | jq -r '.updated_at' | cut -d'T' -f1)
    body=$(echo "$issue" | jq -r '.body')
    comments_url=$(echo "$issue" | jq -r '.comments_url')
    
    echo -e "\n${YELLOW}议题详情: #$issue_number - $title${NC}"
    echo "--------------------------------"
    echo -e "状态: ${state^} | 创建者: $creator"
    echo -e "创建时间: $created_at | 更新时间: $updated_at"
    echo -e "\n${BLUE}描述:${NC}"
    echo "$body"
    echo "--------------------------------"
    
    # 获取评论
    comments=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "$comments_url")
    
    comment_count=$(echo "$comments" | jq 'length')
    if [ "$comment_count" -gt 0 ]; then
        echo -e "\n${GREEN}评论 ($comment_count):${NC}"
        echo "--------------------------------"
        for i in $(seq 0 $((comment_count-1))); do
            comment_user=$(echo "$comments" | jq -r ".[$i].user.login")
            comment_date=$(echo "$comments" | jq -r ".[$i].created_at" | cut -d'T' -f1)
            comment_body=$(echo "$comments" | jq -r ".[$i].body")
            echo -e "${CYAN}$comment_user (于 $comment_date):${NC}"
            echo "$comment_body"
            echo "--------------------------------"
        done
    fi
}

# ====== 管理协作者功能 ======
manage_collaborators() {
    # 获取仓库列表
    repo_json=$(get_repo_list)
    if [ -z "$repo_json" ]; then
        echo -e "${RED}❌ 无法获取仓库列表${NC}"
        press_enter_to_continue
        return
    fi
    
    # 解析仓库列表
    mapfile -t repo_array < <(echo "$repo_json" | jq -r '.[] | "\(.id) \(.name)"')
    
    # 显示仓库列表
    echo -e "\n${YELLOW}选择仓库:${NC}"
    echo "--------------------------------"
    printf "%-5s %s\n" "序号" "仓库名称"
    echo "--------------------------------"
    for i in "${!repo_array[@]}"; do
        repo_info=(${repo_array[$i]})
        printf "%-5s %s\n" "$((i+1))" "${repo_info[1]}"
    done
    echo "--------------------------------"
    
    read -p "➡️ 输入仓库序号: " repo_index
    if [[ ! "$repo_index" =~ ^[0-9]+$ ]] || [ "$repo_index" -lt 1 ] || [ "$repo_index" -gt "${#repo_array[@]}" ]; then
        echo -e "${RED}❌ 无效的仓库序号${NC}"
        press_enter_to_continue
        return
    fi
    
    # 获取仓库名称
    repo_info=(${repo_array[$((repo_index-1))]})
    repo_name=${repo_info[1]}
    encoded_repo=$(urlencode "$repo_name")
    
    while true; do
        clear
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${YELLOW}          协作者管理: ${CYAN}$repo_name${NC}"
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${PURPLE}1. 查看协作者${NC}"
        echo -e "${PURPLE}2. 添加协作者${NC}"
        echo -e "${PURPLE}3. 移除协作者${NC}"
        echo -e "${YELLOW}4. 返回仓库管理菜单${NC}"
        echo -e "${BLUE}==================================================${NC}"
        
        read -p "选择操作 (1-4): " collab_choice
        
        case $collab_choice in
            1)
                # 查看协作者
                echo -e "${BLUE}👥 正在获取协作者列表...${NC}"
                collaborators=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/collaborators")
                
                count=$(echo "$collaborators" | jq 'length')
                if [ "$count" -eq 0 ]; then
                    echo -e "${YELLOW}👥 该仓库没有协作者${NC}"
                else
                    echo -e "\n${GREEN}👥 协作者列表:${NC}"
                    echo "--------------------------------"
                    echo "$collaborators" | jq -r '.[].login'
                    echo "--------------------------------"
                fi
                press_enter_to_continue
                ;;
            2)
                # 添加协作者
                read -p "👤 输入GitHub用户名: " username
                if [ -z "$username" ]; then
                    echo -e "${RED}❌ 用户名不能为空${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                # 选择权限级别
                echo -e "${BLUE}选择权限级别:${NC}"
                echo "1. 读取 (pull)"
                echo "2. 写入 (push)"
                echo "3. 管理员 (admin)"
                read -p "选择 (默认: 2): " permission_choice
                
                case $permission_choice in
                    1) permission="pull" ;;
                    2|"") permission="push" ;;
                    3) permission="admin" ;;
                    *) 
                        echo -e "${RED}❌ 无效选择，使用默认写入权限${NC}"
                        permission="push"
                        ;;
                esac
                
                response=$(curl -s -X PUT \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d "{\"permission\": \"$permission\"}" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/collaborators/$username")
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ 添加协作者失败${NC}"
                else
                    message=$(echo "$response" | jq -r '.message')
                    if [ "$message" == "null" ]; then
                        echo -e "${GREEN}✅ 已添加协作者: $username (权限: $permission)${NC}"
                        user_audit_log "ADD_COLLABORATOR" "$repo_name/$username"
                    else
                        echo -e "${RED}❌ 添加失败: $message${NC}"
                    fi
                fi
                press_enter_to_continue
                ;;
            3)
                # 移除协作者
                # 先获取当前协作者
                collaborators=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/collaborators")
                
                count=$(echo "$collaborators" | jq 'length')
                if [ "$count" -eq 0 ]; then
                    echo -e "${YELLOW}👥 该仓库没有协作者${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                echo -e "\n${GREEN}👥 当前协作者:${NC}"
                echo "--------------------------------"
                echo "$collaborators" | jq -r '.[].login'
                echo "--------------------------------"
                
                read -p "👤 输入要移除的GitHub用户名: " username
                if [ -z "$username" ]; then
                    echo -e "${RED}❌ 用户名不能为空${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                response=$(curl -s -X DELETE \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/collaborators/$username")
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ 移除协作者失败${NC}"
                else
                    # 成功删除返回204
                    if [[ "$response" == *"HTTP/2 204"* ]] || [[ "$response" == *"HTTP/1.1 204"* ]]; then
                        echo -e "${GREEN}✅ 已移除协作者: $username${NC}"
                        user_audit_log "REMOVE_COLLABORATOR" "$repo_name/$username"
                    else
                        echo -e "${RED}❌ 移除失败${NC}"
                    fi
                fi
                press_enter_to_continue
                ;;
            4) return ;;
            *) 
                echo -e "${RED}❌ 无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# ====== 管理仓库状态功能 ======
manage_repo_status() {
    # 获取仓库列表
    repo_json=$(get_repo_list)
    if [ -z "$repo_json" ]; then
        echo -e "${RED}❌ 无法获取仓库列表${NC}"
        press_enter_to_continue
        return
    fi
    
    # 解析仓库列表
    mapfile -t repo_array < <(echo "$repo_json" | jq -r '.[] | "\(.id) \(.name)"')
    
    # 显示仓库列表
    echo -e "\n${YELLOW}选择仓库:${NC}"
    echo "--------------------------------"
    printf "%-5s %s\n" "序号" "仓库名称"
    echo "--------------------------------"
    for i in "${!repo_array[@]}"; do
        repo_info=(${repo_array[$i]})
        printf "%-5s %s\n" "$((i+1))" "${repo_info[1]}"
    done
    echo "--------------------------------"
    
    read -p "➡️ 输入仓库序号: " repo_index
    if [[ ! "$repo_index" =~ ^[0-9]+$ ]] || [ "$repo_index" -lt 1 ] || [ "$repo_index" -gt "${#repo_array[@]}" ]; then
        echo -e "${RED}❌ 无效的仓库序号${NC}"
        press_enter_to_continue
        return
    fi
    
    # 获取仓库名称
    repo_info=(${repo_array[$((repo_index-1))]})
    repo_name=${repo_info[1]}
    encoded_repo=$(urlencode "$repo_name")
    
    # 获取当前仓库状态
    repo_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USER/$encoded_repo")
    
    archived=$(echo "$repo_info" | jq -r '.archived')
    disabled=$(echo "$repo_info" | jq -r '.disabled')
    is_template=$(echo "$repo_info" | jq -r '.is_template')
    visibility=$(echo "$repo_info" | jq -r '.private? | if . then "私有" else "公开" end')
    
    while true; do
        clear
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${YELLOW}          仓库状态管理: ${CYAN}$repo_name${NC}"
        echo -e "${BLUE}==================================================${NC}"
        echo "1. 归档状态: $([ "$archived" == "true" ] && echo "已归档" || echo "未归档")"
        echo "2. 禁用状态: $([ "$disabled" == "true" ] && echo "已禁用" || echo "未禁用")"
        echo "3. 模板状态: $([ "$is_template" == "true" ] && echo "是模板" || echo "不是模板")"
        echo "4. 可见性: $visibility"
        echo "5. 转移仓库所有权"
        echo -e "${YELLOW}6. 返回仓库管理菜单${NC}"
        echo -e "${BLUE}==================================================${NC}"
        read -p "选择操作: " status_choice
        
        case $status_choice in
            1)
                # 切换归档状态
                new_status=$([ "$archived" == "true" ] && echo "false" || echo "true")
                action=$([ "$new_status" == "true" ] && echo "归档" || echo "取消归档")
                
                read -p "⚠️ 确定要$action仓库 '$repo_name' 吗? (y/N): " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] || { echo -e "${YELLOW}❌ 操作已取消${NC}"; press_enter_to_continue; continue; }
                
                response=$(curl -s -X PATCH \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d "{\"archived\": $new_status}" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo")
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ $action 操作失败${NC}"
                else
                    echo -e "${GREEN}✅ 仓库已成功$action${NC}"
                    archived=$new_status
                    user_audit_log "ARCHIVE_REPO" "$repo_name/$action"
                fi
                press_enter_to_continue
                ;;
            2)
                # 切换禁用状态
                new_status=$([ "$disabled" == "true" ] && echo "false" || echo "true")
                action=$([ "$new_status" == "true" ] && echo "禁用" || echo "启用")
                
                read -p "⚠️ 确定要$action仓库 '$repo_name' 吗? (y/N): " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] || { echo -e "${YELLOW}❌ 操作已取消${NC}"; press_enter_to_continue; continue; }
                
                response=$(curl -s -X PATCH \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d "{\"disabled\": $new_status}" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo")
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ $action 操作失败${NC}"
                else
                    echo -e "${GREEN}✅ 仓库已成功$action${NC}"
                    disabled=$new_status
                    user_audit_log "DISABLE_REPO" "$repo_name/$action"
                fi
                press_enter_to_continue
                ;;
            3)
                # 切换模板状态
                new_status=$([ "$is_template" == "true" ] && echo "false" || echo "true")
                action=$([ "$new_status" == "true" ] && echo "设为模板" || echo "取消模板")
                
                read -p "⚠️ 确定要将仓库 '$repo_name' $action吗? (y/N): " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] || { echo -e "${YELLOW}❌ 操作已取消${NC}"; press_enter_to_continue; continue; }
                
                response=$(curl -s -X PATCH \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d "{\"is_template\": $new_status}" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo")
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ $action 操作失败${NC}"
                else
                    echo -e "${GREEN}✅ 仓库已成功$action${NC}"
                    is_template=$new_status
                    user_audit_log "TEMPLATE_REPO" "$repo_name/$action"
                fi
                press_enter_to_continue
                ;;
            4)
                # 切换仓库可见性
                current_visibility=$(echo "$repo_info" | jq -r '.private? | if . then "private" else "public" end')
                new_visibility=$([ "$current_visibility" == "private" ] && echo "public" || echo "private")
                action=$([ "$new_visibility" == "private" ] && echo "设为私有" || echo "设为公开")
                
                read -p "⚠️ 确定要将仓库 '$repo_name' $action吗? (y/N): " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] || { echo -e "${YELLOW}❌ 操作已取消${NC}"; press_enter_to_continue; continue; }
                
                response=$(curl -s -X PATCH \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d "{\"private\": $([ "$new_visibility" == "private" ] && echo "true" || echo "false")}" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo")
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ 更改可见性失败${NC}"
                else
                    error_msg=$(echo "$response" | jq -r '.message')
                    if [ "$error_msg" != "null" ]; then
                        echo -e "${RED}❌ 更改失败: $error_msg${NC}"
                    else
                        echo -e "${GREEN}✅ 仓库可见性已更改为 $new_visibility${NC}"
                        user_audit_log "CHANGE_VISIBILITY" "$repo_name/$new_visibility"
                    fi
                fi
                press_enter_to_continue
                ;;
            5)
                # 转移仓库所有权
                read -p "👤 输入新所有者的GitHub用户名: " new_owner
                if [ -z "$new_owner" ]; then
                    echo -e "${RED}❌ 用户名不能为空${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                read -p "📝 输入新仓库名称 (留空保持原名): " new_name
                if [ -z "$new_name" ]; then
                    new_name=$repo_name
                fi
                
                read -p "⚠️ 确定要将 '$repo_name' 转移给 '$new_owner' 吗? (y/N): " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] || { echo -e "${YELLOW}❌ 操作已取消${NC}"; press_enter_to_continue; continue; }
                
                response=$(curl -s -X POST \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d "{
                        \"new_owner\": \"$new_owner\",
                        \"new_name\": \"$new_name\"
                    }" "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/transfer")
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ 转移仓库失败${NC}"
                else
                    message=$(echo "$response" | jq -r '.message')
                    if [ "$message" == "null" ]; then
                        new_url=$(echo "$response" | jq -r '.html_url')
                        echo -e "${GREEN}✅ 仓库已成功转移: $new_url${NC}"
                        user_audit_log "TRANSFER_REPO" "$repo_name -> $new_owner/$new_name"
                    else
                        echo -e "${RED}❌ 转移失败: $message${NC}"
                    fi
                fi
                press_enter_to_continue
                ;;
            6) return ;;
            *) 
                echo -e "${RED}❌ 无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# ====== 查看Webhook功能 ======
view_webhooks() {
    # 获取仓库列表
    repo_json=$(get_repo_list)
    if [ -z "$repo_json" ]; then
        echo -e "${RED}❌ 无法获取仓库列表${NC}"
        press_enter_to_continue
        return
    fi
    
    # 解析仓库列表
    mapfile -t repo_array < <(echo "$repo_json" | jq -r '.[] | "\(.id) \(.name)"')
    
    # 显示仓库列表
    echo -e "\n${YELLOW}选择仓库:${NC}"
    echo "--------------------------------"
    printf "%-5s %s\n" "序号" "仓库名称"
    echo "--------------------------------"
    for i in "${!repo_array[@]}"; do
        repo_info=(${repo_array[$i]})
        printf "%-5s %s\n" "$((i+1))" "${repo_info[1]}"
    done
    echo "--------------------------------"
    
    read -p "➡️ 输入仓库序号: " repo_index
    if [[ ! "$repo_index" =~ ^[0-9]+$ ]] || [ "$repo_index" -lt 1 ] || [ "$repo_index" -gt "${#repo_array[@]}" ]; then
        echo -e "${RED}❌ 无效的仓库序号${NC}"
        press_enter_to_continue
        return
    fi
    
    # 获取仓库名称
    repo_info=(${repo_array[$((repo_index-1))]})
    repo_name=${repo_info[1]}
    encoded_repo=$(urlencode "$repo_name")
    
    echo -e "${BLUE}🪝 正在获取Webhook列表...${NC}"
    webhooks=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/hooks")
    
    count=$(echo "$webhooks" | jq 'length')
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}🪝 该仓库没有Webhook${NC}"
    else
        echo -e "\n${GREEN}🪝 Webhook列表:${NC}"
        echo "--------------------------------"
        for i in $(seq 0 $((count-1))); do
            hook_id=$(echo "$webhooks" | jq -r ".[$i].id")
            hook_url=$(echo "$webhooks" | jq -r ".[$i].config.url")
            events=$(echo "$webhooks" | jq -r ".[$i].events[]" | tr '\n' ',' | sed 's/,$//')
            active=$(echo "$webhooks" | jq -r ".[$i].active")
            state=$([ "$active" == "true" ] && echo "激活" || echo "未激活")
            
            echo -e "ID: ${CYAN}$hook_id${NC} | 状态: $state"
            echo -e "URL: $hook_url"
            echo -e "事件: $events"
            echo "--------------------------------"
        done
        
        # Webhook管理选项
        read -p "输入Webhook ID进行管理 (留空返回): " hook_id
        if [ -n "$hook_id" ]; then
            manage_webhook "$repo_name" "$hook_id"
        fi
    fi
    press_enter_to_continue
}

# ====== 管理Webhook ======
manage_webhook() {
    local repo_name=$1
    local hook_id=$2
    encoded_repo=$(urlencode "$repo_name")
    
    while true; do
        clear
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${YELLOW}          Webhook管理: ${CYAN}$repo_name #$hook_id${NC}"
        echo -e "${BLUE}==================================================${NC}"
        echo "1. 查看详情"
        echo "2. 测试Webhook"
        echo "3. 删除Webhook"
        echo -e "${YELLOW}4. 返回${NC}"
        echo -e "${BLUE}==================================================${NC}"
        read -p "选择操作: " hook_choice
        
        case $hook_choice in
            1)
                # 查看Webhook详情
                webhook=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/hooks/$hook_id")
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ 获取Webhook详情失败${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                url=$(echo "$webhook" | jq -r '.config.url')
                content_type=$(echo "$webhook" | jq -r '.config.content_type')
                secret=$(echo "$webhook" | jq -r '.config.secret // "未设置"')
                insecure_ssl=$(echo "$webhook" | jq -r '.config.insecure_ssl')
                events=$(echo "$webhook" | jq -r '.events[]' | tr '\n' ',' | sed 's/,$//')
                active=$(echo "$webhook" | jq -r '.active')
                created_at=$(echo "$webhook" | jq -r '.created_at' | cut -d'T' -f1)
                updated_at=$(echo "$webhook" | jq -r '.updated_at' | cut -d'T' -f1)
                
                echo -e "\n${GREEN}Webhook详情:${NC}"
                echo "--------------------------------"
                echo -e "ID: ${CYAN}$hook_id${NC}"
                echo -e "URL: $url"
                echo -e "内容类型: $content_type"
                echo -e "密钥: $secret"
                echo -e "SSL验证: $([ "$insecure_ssl" == "0" ] && echo "严格" || echo "宽松")"
                echo -e "事件: $events"
                echo -e "状态: $([ "$active" == "true" ] && echo "激活" || echo "未激活")"
                echo -e "创建时间: $created_at | 更新时间: $updated_at"
                echo "--------------------------------"
                press_enter_to_continue
                ;;
            2)
                # 测试Webhook
                echo -e "${BLUE}🚀 测试Webhook...${NC}"
                response=$(curl -s -X POST \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/hooks/$hook_id/tests")
                
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✅ Webhook测试请求已发送${NC}"
                else
                    echo -e "${RED}❌ 测试失败${NC}"
                fi
                press_enter_to_continue
                ;;
            3)
                # 删除Webhook
                read -p "⚠️ 确定要删除此Webhook吗? (y/N): " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] || { echo -e "${YELLOW}❌ 操作已取消${NC}"; press_enter_to_continue; continue; }
                
                response=$(curl -s -X DELETE \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/hooks/$hook_id")
                
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✅ Webhook已删除${NC}"
                    user_audit_log "DELETE_WEBHOOK" "$repo_name/$hook_id"
                    return
                else
                    echo -e "${RED}❌ 删除失败${NC}"
                fi
                press_enter_to_continue
                ;;
            4) return ;;
            *) 
                echo -e "${RED}❌ 无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}


# ====== 多仓库管理功能 ======
add_repo_to_config() {
    local repo_name=$1
    local repo_url=$2
    
    # 检查是否已存在
    if grep -q "^$repo_name|" "$REPO_CONFIG_FILE"; then
        echo -e "${YELLOW}ℹ️ 仓库 '$repo_name' 已在配置中${NC}"
        return
    fi
    
    # 添加新仓库
    echo "$repo_name|$repo_url" >> "$REPO_CONFIG_FILE"
    echo -e "${GREEN}✅ 仓库 '$repo_name' 已添加到配置${NC}"
    user_audit_log "ADD_REPO" "$repo_name"
    
    # 设置为当前仓库
    CURRENT_REPO=$repo_name
    save_config
}

# ====== 从配置中移除仓库 ======
remove_repo_from_config() {
    local repo_name=$1
    
    # 创建临时文件
    temp_file=$(mktemp)
    
    # 过滤掉要删除的仓库
    grep -v "^$repo_name|" "$REPO_CONFIG_FILE" > "$temp_file"
    
    # 替换原文件
    mv "$temp_file" "$REPO_CONFIG_FILE"
    
    echo -e "${GREEN}✅ 仓库 '$repo_name' 已从配置中移除${NC}"
    user_audit_log "REMOVE_REPO" "$repo_name"
    
    # 如果移除的是当前仓库，清空当前仓库设置
    if [ "$CURRENT_REPO" == "$repo_name" ]; then
        CURRENT_REPO=""
        save_config
    fi
}

# ====== 列出所有配置仓库 ======
list_configured_repos() {
    while true; do
        clear
        if [ ! -s "$REPO_CONFIG_FILE" ]; then
            echo -e "${YELLOW}ℹ️ 没有配置任何仓库${NC}"
        else
            echo -e "\n${GREEN}已配置的仓库:${NC}"
            echo "--------------------------------"
            printf "%-20s %s\n" "仓库名称" "URL"
            echo "--------------------------------"
            while IFS='|' read -r name url; do
                printf "%-20s %s\n" "$name" "$url"
            done < "$REPO_CONFIG_FILE"
            echo "--------------------------------"
            
            if [ -n "$CURRENT_REPO" ]; then
                echo -e "当前仓库: ${CYAN}$CURRENT_REPO${NC}"
            else
                echo -e "${YELLOW}ℹ️ 未设置当前仓库${NC}"
            fi
        fi
        
        echo -e "\n${BLUE}配置仓库管理:${NC}"
        echo "1. 添加仓库到配置"
        echo "2. 从配置中移除仓库"
        echo "3. 切换当前仓库"
        echo -e "${YELLOW}4. 返回主菜单${NC}"
        
        read -p "请选择操作 (1-4): " config_choice
        
        case $config_choice in
            1)
                read -p "📝 输入仓库名称: " repo_name
                read -p "🌐 输入仓库URL: " repo_url
                if [ -z "$repo_name" ] || [ -z "$repo_url" ]; then
                    echo -e "${RED}❌ 仓库名称和URL不能为空${NC}"
                    press_enter_to_continue
                    continue
                fi
                add_repo_to_config "$repo_name" "$repo_url"
                press_enter_to_continue
                ;;
            2)
                if [ ! -s "$REPO_CONFIG_FILE" ]; then
                    echo -e "${YELLOW}ℹ️ 没有配置仓库可移除${NC}"
                    press_enter_to_continue
                    continue
                fi
                read -p "📝 输入要移除的仓库名称: " repo_name
                if [ -z "$repo_name" ]; then
                    echo -e "${RED}❌ 仓库名称不能为空${NC}"
                    press_enter_to_continue
                    continue
                fi
                remove_repo_from_config "$repo_name"
                press_enter_to_continue
                ;;
            3)
                switch_current_repo
                press_enter_to_continue
                ;;
            4) 
                return
                ;;
            *)
                echo -e "${RED}❌ 无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# ====== 切换当前仓库 ======
switch_current_repo() {
    if [ ! -s "$REPO_CONFIG_FILE" ]; then
        echo -e "${YELLOW}ℹ️ 没有配置任何仓库${NC}"
        return
    fi
    
    # 读取仓库列表
    mapfile -t repos < <(cut -d'|' -f1 "$REPO_CONFIG_FILE")
    
    echo -e "\n${YELLOW}选择要切换的仓库:${NC}"
    echo "--------------------------------"
    for i in "${!repos[@]}"; do
        echo "$((i+1)). ${repos[$i]}"
    done
    echo "--------------------------------"
    
    read -p "➡️ 输入仓库序号: " repo_index
    if [[ ! "$repo_index" =~ ^[0-9]+$ ]] || [ "$repo_index" -lt 1 ] || [ "$repo_index" -gt "${#repos[@]}" ]; then
        echo -e "${RED}❌ 无效的仓库序号${NC}"
        return
    fi
    
    CURRENT_REPO="${repos[$((repo_index-1))]}"
    save_config
    echo -e "${GREEN}✅ 已切换到仓库: $CURRENT_REPO${NC}"
    user_audit_log "SWITCH_REPO" "$CURRENT_REPO"
}

# ===== 仓库统计功能 ======
show_repo_stats() {
    # 获取仓库列表
    repo_json=$(get_repo_list)
    if [ -z "$repo_json" ]; then
        echo -e "${RED}❌ 无法获取仓库列表${NC}"
        press_enter_to_continue
        return
    fi
    
    # 解析仓库列表
    mapfile -t repo_array < <(echo "$repo_json" | jq -r '.[] | "\(.id) \(.name)"')
    
    # 显示仓库列表
    echo -e "\n${YELLOW}选择仓库:${NC}"
    echo "--------------------------------"
    printf "%-5s %s\n" "序号" "仓库名称"
    echo "--------------------------------"
    for i in "${!repo_array[@]}"; do
        repo_info=(${repo_array[$i]})
        printf "%-5s %s\n" "$((i+1))" "${repo_info[1]}"
    done
    echo "--------------------------------"
    
    read -p "➡️ 输入仓库序号: " repo_index
    if [[ ! "$repo_index" =~ ^[0-9]+$ ]] || [ "$repo_index" -lt 1 ] || [ "$repo_index" -gt "${#repo_array[@]}" ]; then
        echo -e "${RED}❌ 无效的仓库序号${NC}"
        press_enter_to_continue
        return
    fi
    
    # 获取仓库ID和名称
    repo_info=(${repo_array[$((repo_index-1))]})
    repo_id=${repo_info[0]}
    repo_name=${repo_info[1]}
    
    # 获取仓库统计信息
    echo -e "${BLUE}📊 获取仓库统计信息...${NC}"
    stats=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USER/$repo_name")
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 获取统计信息失败${NC}"
        press_enter_to_continue
        return
    fi
    
    error_msg=$(echo "$stats" | jq -r '.message')
    if [ "$error_msg" != "null" ]; then
        echo -e "${RED}❌ 获取统计信息失败: $error_msg${NC}"
        press_enter_to_continue
        return
    fi
    
    echo -e "\n${GREEN}📊 仓库统计 ($repo_name):${NC}"
    echo "--------------------------------"
    echo "⭐ 星标: $(echo "$stats" | jq -r '.stargazers_count')"
    echo "👀 关注者: $(echo "$stats" | jq -r '.watchers_count')"
    echo "🍴 Fork数: $(echo "$stats" | jq -r '.forks_count')"
    echo "📁 大小: $(echo "$stats" | jq -r '.size') KB"
    echo "📅 创建于: $(echo "$stats" | jq -r '.created_at' | cut -d'T' -f1)"
    echo "🔄 更新于: $(echo "$stats" | jq -r '.pushed_at' | cut -d'T' -f1)"
    echo "🌐 访问URL: $(echo "$stats" | jq -r '.html_url')"
    echo "--------------------------------"
    press_enter_to_continue
}



# ====== 仓库备份功能 ======
backup_repository() {
    # 获取仓库列表
    repo_json=$(get_repo_list)
    if [ -z "$repo_json" ]; then
        echo -e "${RED}❌ 无法获取仓库列表${NC}"
        press_enter_to_continue
        return
    fi

    # 解析仓库列表
    mapfile -t repo_array < <(echo "$repo_json" | jq -r '.[] | "\(.id) \(.name)"')

    # 显示仓库列表
    echo -e "\n${YELLOW}选择仓库:${NC}"
    echo "--------------------------------"
    printf "%-5s %s\n" "序号" "仓库名称"
    echo "--------------------------------"
    for i in "${!repo_array[@]}"; do
        repo_info=(${repo_array[$i]})
        printf "%-5s %s\n" "$((i+1))" "${repo_info[1]}"
    done
    echo "--------------------------------"

    read -p "➡️ 输入仓库序号: " repo_index
    if [[ ! "$repo_index" =~ ^[0-9]+$ ]] || [ "$repo_index" -lt 1 ] || [ "$repo_index" -gt "${#repo_array[@]}" ]; then
        echo -e "${RED}❌ 无效的仓库序号${NC}"
        press_enter_to_continue
        return
    fi

    # 获取仓库名称
    repo_info=(${repo_array[$((repo_index-1))]})
    repo_name=${repo_info[1]}
    encoded_repo=$(urlencode "$repo_name")

    # 创建备份目录
    backup_dir="$HOME/github_backups"
    mkdir -p "$backup_dir"

    # 生成备份文件名
    backup_file="${backup_dir}/${repo_name}_$(date +%Y%m%d_%H%M%S).tar.gz"

    # 克隆仓库到临时目录
    temp_dir=$(mktemp -d)
    echo -e "${BLUE}⬇️ 正在克隆仓库 $repo_name ...${NC}"
    git clone --mirror "https://github.com/$GITHUB_USER/$repo_name.git" "$temp_dir/$repo_name.git" || {
        echo -e "${RED}❌ 克隆仓库失败${NC}"
        rm -rf "$temp_dir"
        return 1
    }

    # 打包仓库
    tar -czf "$backup_file" -C "$temp_dir" "$repo_name.git"
    rm -rf "$temp_dir"

    echo -e "${GREEN}✅ 仓库备份成功: $backup_file${NC}"
    user_audit_log "BACKUP_REPO" "$repo_name"
    press_enter_to_continue
}


# ====== 恢复仓库功能 ======
restore_repository() {
    # 选择备份文件
    backup_dir="$HOME/github_backups"
    if [ ! -d "$backup_dir" ]; then
        echo -e "${YELLOW}备份目录不存在，请先备份仓库${NC}"
        press_enter_to_continue
        return
    fi

    mapfile -t backup_files < <(ls "$backup_dir"/*.tar.gz 2>/dev/null)
    if [ ${#backup_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}没有找到备份文件${NC}"
        press_enter_to_continue
        return
    fi

    echo -e "\n${YELLOW}选择备份文件:${NC}"
    echo "--------------------------------"
    for i in "${!backup_files[@]}"; do
        echo "$((i+1)). $(basename "${backup_files[$i]}")"
    done
    echo "--------------------------------"

    read -p "➡️ 输入备份文件序号: " file_index
    if [[ ! "$file_index" =~ ^[0-9]+$ ]] || [ "$file_index" -lt 1 ] || [ "$file_index" -gt "${#backup_files[@]}" ]; then
        echo -e "${RED}❌ 无效的序号${NC}"
        press_enter_to_continue
        return
    fi

    backup_file="${backup_files[$((file_index-1))]}"
    echo -e "${BLUE}🔄 正在从备份恢复: $(basename "$backup_file") ...${NC}"

    # 解压备份文件到临时目录
    temp_dir=$(mktemp -d)
    tar -xzf "$backup_file" -C "$temp_dir" || {
        echo -e "${RED}❌ 解压备份文件失败${NC}"
        rm -rf "$temp_dir"
        return 1
    }

    # 获取仓库名称（从备份文件名或目录中提取）
    repo_name=$(basename "$backup_file" | cut -d'_' -f1)
    repo_dir="$temp_dir/$repo_name.git"

    if [ ! -d "$repo_dir" ]; then
        echo -e "${RED}❌ 备份文件中未找到仓库目录${NC}"
        rm -rf "$temp_dir"
        return 1
    fi

    # 创建新仓库（使用原仓库名或让用户输入新名字）
    read -p "输入新的仓库名称（留空使用原名 $repo_name）: " new_repo_name
    new_repo_name=${new_repo_name:-$repo_name}

    # 检查仓库是否已存在
    repo_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USER/$new_repo_name")

    if [ "$(echo "$repo_info" | jq -r '.message')" != "Not Found" ]; then
        echo -e "${RED}❌ 仓库 $new_repo_name 已存在${NC}"
        rm -rf "$temp_dir"
        return 1
    fi

    # 创建新仓库
    response=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{\"name\": \"$new_repo_name\", \"private\": false}" \
        "https://api.github.com/user/repos")

    error_msg=$(echo "$response" | jq -r '.message')
    if [ "$error_msg" != "null" ]; then
        echo -e "${RED}❌ 创建仓库失败: $error_msg${NC}"
        rm -rf "$temp_dir"
        return 1
    fi

    # 获取新仓库的URL
    new_repo_url=$(echo "$response" | jq -r '.clone_url')
    new_repo_url_auth="https://$GITHUB_USER:$GITHUB_TOKEN@${new_repo_url#https://}"

    # 将备份的仓库推送到新仓库
    cd "$repo_dir" || return 1
    git remote set-url origin "$new_repo_url_auth"
    git push --mirror || {
        echo -e "${RED}❌ 推送仓库失败${NC}"
        cd - >/dev/null
        rm -rf "$temp_dir"
        return 1
    }

    cd - >/dev/null
    rm -rf "$temp_dir"

    echo -e "${GREEN}✅ 仓库 $new_repo_name 恢复成功${NC}"
    user_audit_log "RESTORE_REPO" "$new_repo_name"
    press_enter_to_continue
}





# ====== 查看仓库贡献者 ======
show_contributors() {
    # 获取仓库列表
    repo_json=$(get_repo_list)
    if [ -z "$repo_json" ]; then
        echo -e "${RED}❌ 无法获取仓库列表${NC}"
        press_enter_to_continue
        return
    fi

    # 解析仓库列表
    mapfile -t repo_array < <(echo "$repo_json" | jq -r '.[] | "\(.id) \(.name)"')

    # 显示仓库列表
    echo -e "\n${YELLOW}选择仓库:${NC}"
    echo "--------------------------------"
    printf "%-5s %s\n" "序号" "仓库名称"
    echo "--------------------------------"
    for i in "${!repo_array[@]}"; do
        repo_info=(${repo_array[$i]})
        printf "%-5s %s\n" "$((i+1))" "${repo_info[1]}"
    done
    echo "--------------------------------"

    read -p "➡️ 输入仓库序号: " repo_index
    if [[ ! "$repo_index" =~ ^[0-9]+$ ]] || [ "$repo_index" -lt 1 ] || [ "$repo_index" -gt "${#repo_array[@]}" ]; then
        echo -e "${RED}❌ 无效的仓库序号${NC}"
        press_enter_to_continue
        return
    fi

    # 获取仓库名称
    repo_info=(${repo_array[$((repo_index-1))]})
    repo_name=${repo_info[1]}
    encoded_repo=$(urlencode "$repo_name")

    # 获取贡献者列表
    echo -e "${BLUE}👥 获取贡献者列表...${NC}"
    contributors=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/contributors")

    count=$(echo "$contributors" | jq 'length')
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}👥 该仓库没有贡献者${NC}"
    else
        echo -e "\n${GREEN}👥 贡献者列表:${NC}"
        echo "--------------------------------"
        echo "$contributors" | jq -r '.[] | "\(.login): \(.contributions) 次提交"'
        echo "--------------------------------"
    fi
    press_enter_to_continue
}

# ====== 查看仓库活动 ======
show_repo_activity() {
    # 获取仓库列表
    repo_json=$(get_repo_list)
    if [ -z "$repo_json" ]; then
        echo -e "${RED}❌ 无法获取仓库列表${NC}"
        press_enter_to_continue
        return
    fi

    # 解析仓库列表
    mapfile -t repo_array < <(echo "$repo_json" | jq -r '.[] | "\(.id) \(.name)"')

    # 显示仓库列表
    echo -e "\n${YELLOW}选择仓库:${NC}"
    echo "--------------------------------"
    printf "%-5s %s\n" "序号" "仓库名称"
    echo "--------------------------------"
    for i in "${!repo_array[@]}"; do
        repo_info=(${repo_array[$i]})
        printf "%-5s %s\n" "$((i+1))" "${repo_info[1]}"
    done
    echo "--------------------------------"

    read -p "➡️ 输入仓库序号: " repo_index
    if [[ ! "$repo_index" =~ ^[0-9]+$ ]] || [ "$repo_index" -lt 1 ] || [ "$repo_index" -gt "${#repo_array[@]}" ]; then
        echo -e "${RED}❌ 无效的仓库序号${NC}"
        press_enter_to_continue
        return
    fi

    # 获取仓库名称
    repo_info=(${repo_array[$((repo_index-1))]})
    repo_name=${repo_info[1]}
    encoded_repo=$(urlencode "$repo_name")

    # 获取仓库活动
    echo -e "${BLUE}📅 获取仓库活动...${NC}"
    events=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/events")

    count=$(echo "$events" | jq 'length')
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}📅 该仓库没有活动${NC}"
    else
        echo -e "\n${GREEN}📅 最近活动:${NC}"
        echo "--------------------------------"
        for i in $(seq 0 $((count-1))); do
            type=$(echo "$events" | jq -r ".[$i].type")
            user=$(echo "$events" | jq -r ".[$i].actor.login")
            created_at=$(echo "$events" | jq -r ".[$i].created_at" | cut -d'T' -f1)
            payload=$(echo "$events" | jq -r ".[$i].payload")
            case $type in
                "PushEvent")
                    ref=$(echo "$payload" | jq -r '.ref')
                    commits_count=$(echo "$payload" | jq -r '.commits | length')
                    echo -e "${CYAN}推送事件${NC} - 用户: $user, 分支: $ref, 提交数: $commits_count, 时间: $created_at"
                    ;;
                "IssuesEvent")
                    action=$(echo "$payload" | jq -r '.action')
                    issue_num=$(echo "$payload" | jq -r '.issue.number')
                    issue_title=$(echo "$payload" | jq -r '.issue.title')
                    echo -e "${GREEN}议题事件${NC} - 用户: $user, 操作: $action, 议题: #$issue_num - $issue_title, 时间: $created_at"
                    ;;
                "PullRequestEvent")
                    action=$(echo "$payload" | jq -r '.action')
                    pr_num=$(echo "$payload" | jq -r '.number')
                    pr_title=$(echo "$payload" | jq -r '.pull_request.title')
                    echo -e "${PURPLE}拉取请求事件${NC} - 用户: $user, 操作: $action, PR: #$pr_num - $pr_title, 时间: $created_at"
                    ;;
                "CreateEvent")
                    ref_type=$(echo "$payload" | jq -r '.ref_type')
                    ref_name=$(echo "$payload" | jq -r '.ref')
                    echo -e "${YELLOW}创建事件${NC} - 用户: $user, 类型: $ref_type, 名称: $ref_name, 时间: $created_at"
                    ;;
                "DeleteEvent")
                    ref_type=$(echo "$payload" | jq -r '.ref_type')
                    ref_name=$(echo "$payload" | jq -r '.ref')
                    echo -e "${RED}删除事件${NC} - 用户: $user, 类型: $ref_type, 名称: $ref_name, 时间: $created_at"
                    ;;
                *)
                    echo -e "未知事件: $type - 用户: $user, 时间: $created_at"
                    ;;
            esac
        done
        echo "--------------------------------"
    fi
    press_enter_to_continue
}

# ====== 协作管理 ======
collaboration_management() {
    while true; do
        clear
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${YELLOW}          协作管理${NC}"
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${CYAN}1. 议题管理${NC}"
        echo -e "${CYAN}2. 协作者管理${NC}"
        echo -e "${CYAN}3. 查看贡献者${NC}"
        echo -e "${YELLOW}4. 返回仓库管理菜单${NC}"
        echo -e "${BLUE}==================================================${NC}"
        
        read -p "选择操作 (1-4): " choice
        
        case $choice in
            1) manage_issues ;;
            2) manage_collaborators ;;
            3) show_contributors ;;
            4) return ;;
            *) 
                echo -e "${RED}❌ 无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# ====== 仓库维护 ======
repo_maintenance() {
    while true; do
        clear
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${YELLOW}          仓库维护${NC}"
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${CYAN}1. 备份仓库${NC}"
        echo -e "${CYAN}2. 恢复仓库${NC}"
        echo -e "${CYAN}3. 重命名仓库${NC}"
        echo -e "${CYAN}4. 子模块管理${NC}"
        echo -e "${YELLOW}5. 返回仓库管理菜单${NC}"
        echo -e "${BLUE}==================================================${NC}"
        
        read -p "选择操作 (1-5): " choice
        
        case $choice in
            1) backup_repository ;;
            2) restore_repository ;;
            3) rename_repository ;;
            4) manage_submodules ;;
            5) return ;;
            *) 
                echo -e "${RED}❌ 无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# ====== 仓库统计与活动 ======
repo_stats_and_activity() {
    while true; do
        clear
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${YELLOW}          仓库统计与活动${NC}"
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${CYAN}1. 查看仓库统计${NC}"
        echo -e "${CYAN}2. 查看仓库活动${NC}"
        echo -e "${YELLOW}3. 返回仓库管理菜单${NC}"
        echo -e "${BLUE}==================================================${NC}"
        
        read -p "选择操作 (1-3): " choice
        
        case $choice in
            1) show_repo_stats ;;
            2) show_repo_activity ;;
            3) return ;;
            *) 
                echo -e "${RED}❌ 无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}


# ====== 里程碑管理 ======
manage_milestones() {
    # 获取仓库列表
    repo_json=$(get_repo_list)
    if [ -z "$repo_json" ]; then
        echo -e "${RED}❌ 无法获取仓库列表${NC}"
        press_enter_to_continue
        return
    fi

    # 解析仓库列表
    mapfile -t repo_array < <(echo "$repo_json" | jq -r '.[] | "\(.id) \(.name)"')

    # 显示仓库列表
    echo -e "\n${YELLOW}选择仓库:${NC}"
    echo "--------------------------------"
    printf "%-5s %s\n" "序号" "仓库名称"
    echo "--------------------------------"
    for i in "${!repo_array[@]}"; do
        repo_info=(${repo_array[$i]})
        printf "%-5s %s\n" "$((i+1))" "${repo_info[1]}"
    done
    echo "--------------------------------"

    read -p "➡️ 输入仓库序号: " repo_index
    if [[ ! "$repo_index" =~ ^[0-9]+$ ]] || [ "$repo_index" -lt 1 ] || [ "$repo_index" -gt "${#repo_array[@]}" ]; then
        echo -e "${RED}❌ 无效的仓库序号${NC}"
        press_enter_to_continue
        return
    fi

    # 获取仓库名称
    repo_info=(${repo_array[$((repo_index-1))]})
    repo_name=${repo_info[1]}
    encoded_repo=$(urlencode "$repo_name")

    while true; do
        clear
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${YELLOW}          里程碑管理: ${CYAN}$repo_name${NC}"
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${GREEN}1. 查看里程碑${NC}"
        echo -e "${GREEN}2. 创建里程碑${NC}"
        echo -e "${GREEN}3. 关闭里程碑${NC}"
        echo -e "${GREEN}4. 删除里程碑${NC}"
        echo -e "${YELLOW}5. 返回仓库管理菜单${NC}"
        echo -e "${BLUE}==================================================${NC}"
        read -p "选择操作: " milestone_choice

        case $milestone_choice in
            1)
                # 查看里程碑
                milestones=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/milestones?state=all")
                
                count=$(echo "$milestones" | jq 'length')
                if [ "$count" -eq 0 ]; then
                    echo -e "${YELLOW}📅 该仓库没有里程碑${NC}"
                else
                    echo -e "\n${GREEN}📅 里程碑列表:${NC}"
                    echo "--------------------------------"
                    echo "$milestones" | jq -r '.[] | "#\(.number): \(.title) [状态: \(.state)] - \(.description // "无描述")"'
                    echo "--------------------------------"
                fi
                press_enter_to_continue
                ;;
            2)
                # 创建里程碑
                read -p "📝 输入里程碑标题: " title
                read -p "📝 输入里程碑描述: " description
                read -p "📅 输入截止日期 (YYYY-MM-DD): " due_date

                if [ -z "$title" ]; then
                    echo -e "${RED}❌ 标题不能为空${NC}"
                    press_enter_to_continue
                    continue
                fi

                data="{\"title\": \"$title\""
                if [ -n "$description" ]; then
                    data+=", \"description\": \"$description\""
                fi
                if [ -n "$due_date" ]; then
                    data+=", \"due_on\": \"$due_date\""
                fi
                data+="}"

                response=$(curl -s -X POST \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d "$data" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/milestones")
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ 创建里程碑失败${NC}"
                else
                    error_msg=$(echo "$response" | jq -r '.message')
                    if [ "$error_msg" != "null" ]; then
                        echo -e "${RED}❌ 创建失败: $error_msg${NC}"
                    else
                        echo -e "${GREEN}✅ 里程碑创建成功${NC}"
                        user_audit_log "CREATE_MILESTONE" "$repo_name/$title"
                    fi
                fi
                press_enter_to_continue
                ;;
            3)
                # 关闭里程碑
                milestones=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/milestones?state=open")
                
                count=$(echo "$milestones" | jq 'length')
                if [ "$count" -eq 0 ]; then
                    echo -e "${YELLOW}📅 该仓库没有开放的里程碑${NC}"
                    press_enter_to_continue
                    continue
                fi

                echo -e "\n${GREEN}📅 开放的里程碑:${NC}"
                echo "--------------------------------"
                echo "$milestones" | jq -r '.[] | "#\(.number): \(.title)"'
                echo "--------------------------------"
                
                read -p "输入里程碑编号: " milestone_number
                if [ -z "$milestone_number" ]; then
                    echo -e "${RED}❌ 里程碑编号不能为空${NC}"
                    press_enter_to_continue
                    continue
                fi

                response=$(curl -s -X PATCH \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d '{"state": "closed"}' \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/milestones/$milestone_number")
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ 关闭里程碑失败${NC}"
                else
                    error_msg=$(echo "$response" | jq -r '.message')
                    if [ "$error_msg" != "null" ]; then
                        echo -e "${RED}❌ 关闭失败: $error_msg${NC}"
                    else
                        echo -e "${GREEN}✅ 里程碑已关闭${NC}"
                        user_audit_log "CLOSE_MILESTONE" "$repo_name/$milestone_number"
                    fi
                fi
                press_enter_to_continue
                ;;
            4)
                # 删除里程碑
                milestones=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/milestones?state=all")
                
                count=$(echo "$milestones" | jq 'length')
                if [ "$count" -eq 0 ]; then
                    echo -e "${YELLOW}📅 该仓库没有里程碑${NC}"
                    press_enter_to_continue
                    continue
                fi

                echo -e "\n${GREEN}📅 里程碑列表:${NC}"
                echo "--------------------------------"
                echo "$milestones" | jq -r '.[] | "#\(.number): \(.title) [状态: \(.state)]"'
                echo "--------------------------------"
                
                read -p "输入里程碑编号: " milestone_number
                if [ -z "$milestone_number" ]; then
                    echo -e "${RED}❌ 里程碑编号不能为空${NC}"
                    press_enter_to_continue
                    continue
                fi

                read -p "⚠️ 确定要删除里程碑 #$milestone_number 吗? (y/N): " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] || { echo -e "${YELLOW}❌ 操作已取消${NC}"; press_enter_to_continue; continue; }

                response=$(curl -s -X DELETE \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/milestones/$milestone_number")
                
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✅ 里程碑已删除${NC}"
                    user_audit_log "DELETE_MILESTONE" "$repo_name/$milestone_number"
                else
                    echo -e "${RED}❌ 删除失败${NC}"
                fi
                press_enter_to_continue
                ;;
            5) return ;;
            *)
                echo -e "${RED}❌ 无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}


# ====== 子模块管理增强 ======
manage_submodules() {
    while true; do
        clear
        echo -e "${BLUE}======================================${NC}"
        echo -e "${YELLOW}          子模块管理${NC}"
        echo -e "${BLUE}======================================${NC}"
        echo "1. 添加子模块"
        echo "2. 初始化子模块"
        echo "3. 更新子模块"
        echo "4. 同步子模块"
        echo "5. 查看子模块状态"
        echo -e "${YELLOW}6. 返回仓库维护菜单${NC}"
        echo -e "${BLUE}======================================${NC}"
        
        read -p "请选择操作: " choice
        
        case $choice in
            1)
                read -p "输入子模块仓库URL: " sub_url
                read -p "输入子模块路径: " sub_path
                if git submodule add "$sub_url" "$sub_path"; then
                    echo -e "${GREEN}✅ 子模块添加成功${NC}"
                else
                    echo -e "${RED}❌ 添加失败${NC}"
                fi
                ;;
            2)
                if git submodule init; then
                    echo -e "${GREEN}✅ 子模块初始化完成${NC}"
                else
                    echo -e "${RED}❌ 初始化失败${NC}"
                fi
                ;;
            3)
                if git submodule update --remote; then
                    echo -e "${GREEN}✅ 子模块更新完成${NC}"
                else
                    echo -e "${RED}❌ 更新失败${NC}"
                fi
                ;;
            4)
                if git submodule sync; then
                    echo -e "${GREEN}✅ 子模块同步完成${NC}"
                else
                    echo -e "${RED}❌ 同步失败${NC}"
                fi
                ;;
            5)
                git submodule status
                ;;
            6) return ;;
            *)
                echo -e "${RED}❌ 无效选择${NC}"
                ;;
        esac
        press_enter_to_continue
    done
}


# ====== 拉取请求管理功能 ======
manage_pull_requests() {
    # 获取仓库列表
    repo_json=$(get_repo_list)
    if [ -z "$repo_json" ]; then
        echo -e "${RED}❌ 无法获取仓库列表${NC}"
        press_enter_to_continue
        return
    fi
    
    # 解析仓库列表
    mapfile -t repo_array < <(echo "$repo_json" | jq -r '.[] | "\(.id) \(.name)"')
    
    # 显示仓库列表
    echo -e "\n${YELLOW}选择仓库:${NC}"
    echo "--------------------------------"
    printf "%-5s %s\n" "序号" "仓库名称"
    echo "--------------------------------"
    for i in "${!repo_array[@]}"; do
        repo_info=(${repo_array[$i]})
        printf "%-5s %s\n" "$((i+1))" "${repo_info[1]}"
    done
    echo "--------------------------------"
    
    read -p "➡️ 输入仓库序号: " repo_index
    if [[ ! "$repo_index" =~ ^[0-9]+$ ]] || [ "$repo_index" -lt 1 ] || [ "$repo_index" -gt "${#repo_array[@]}" ]; then
        echo -e "${RED}❌ 无效的仓库序号${NC}"
        press_enter_to_continue
        return
    fi
    
    # 获取仓库名称
    repo_info=(${repo_array[$((repo_index-1))]})
    repo_name=${repo_info[1]}
    encoded_repo=$(urlencode "$repo_name")
    
    while true; do
        clear
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${YELLOW}          拉取请求管理: ${CYAN}$repo_name${NC}"
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${PURPLE}1. 查看拉取请求${NC}"
        echo -e "${PURPLE}2. 创建拉取请求${NC}"
        echo -e "${PURPLE}3. 合并拉取请求${NC}"
        echo -e "${PURPLE}4. 关闭拉取请求${NC}"
        echo -e "${YELLOW}5. 返回仓库管理菜单${NC}"
        echo -e "${BLUE}==================================================${NC}"
        
        read -p "选择操作 (1-5): " pr_choice
        
        case $pr_choice in
            1)
                # 查看拉取请求
                echo -e "${BLUE}📝 获取拉取请求列表...${NC}"
                pulls=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/pulls?state=all")
                
                count=$(echo "$pulls" | jq 'length')
                if [ "$count" -eq 0 ]; then
                    echo -e "${YELLOW}📝 该仓库没有拉取请求${NC}"
                else
                    echo -e "\n${GREEN}📝 拉取请求列表:${NC}"
                    echo "--------------------------------"
                    echo "$pulls" | jq -r '.[] | "#\(.number): \(.title) [\(.state)]"'
                    echo "--------------------------------"
                    
                    read -p "输入拉取请求编号查看详情 (留空返回): " pr_number
                    if [ -n "$pr_number" ]; then
                        view_pull_request_detail "$repo_name" "$pr_number"
                    fi
                fi
                press_enter_to_continue
                ;;
            2)
                # 创建拉取请求
                read -p "📝 输入拉取请求标题: " title
                read -p "📝 输入拉取请求描述: " body
                read -p "📝 输入源分支: " head_branch
                read -p "📝 输入目标分支: " base_branch
                
                if [ -z "$title" ] || [ -z "$head_branch" ] || [ -z "$base_branch" ]; then
                    echo -e "${RED}❌ 标题和分支不能为空${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                data="{
                    \"title\": \"$title\",
                    \"body\": \"$body\",
                    \"head\": \"$head_branch\",
                    \"base\": \"$base_branch\"
                }"
                
                response=$(curl -s -X POST \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d "$data" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/pulls")
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ 创建拉取请求失败${NC}"
                else
                    error_msg=$(echo "$response" | jq -r '.message')
                    if [ "$error_msg" != "null" ]; then
                        echo -e "${RED}❌ 创建失败: $error_msg${NC}"
                    else
                        pr_url=$(echo "$response" | jq -r '.html_url')
                        echo -e "${GREEN}✅ 拉取请求创建成功: $pr_url${NC}"
                        user_audit_log "CREATE_PULL_REQUEST" "$repo_name/$title"
                    fi
                fi
                press_enter_to_continue
                ;;
            3)
                # 合并拉取请求
                echo -e "${BLUE}📝 获取开放的拉取请求...${NC}"
                open_pulls=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/pulls?state=open")
                
                count=$(echo "$open_pulls" | jq 'length')
                if [ "$count" -eq 0 ]; then
                    echo -e "${YELLOW}📝 该仓库没有开放的拉取请求${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                echo -e "\n${GREEN}📝 开放的拉取请求:${NC}"
                echo "--------------------------------"
                echo "$open_pulls" | jq -r '.[] | "#\(.number): \(.title)"'
                echo "--------------------------------"
                
                read -p "输入要合并的拉取请求编号: " pr_number
                if [ -z "$pr_number" ]; then
                    echo -e "${RED}❌ 拉取请求编号不能为空${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                read -p "输入合并提交信息 (留空使用默认): " commit_message
                if [ -z "$commit_message" ]; then
                    commit_message="Merge pull request #$pr_number"
                fi
                
                response=$(curl -s -X PUT \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d "{\"commit_message\": \"$commit_message\"}" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/pulls/$pr_number/merge")
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ 合并失败${NC}"
                else
                    merged=$(echo "$response" | jq -r '.merged')
                    if [ "$merged" == "true" ]; then
                        echo -e "${GREEN}✅ 拉取请求 #$pr_number 已合并${NC}"
                        user_audit_log "MERGE_PULL_REQUEST" "$repo_name/$pr_number"
                    else
                        message=$(echo "$response" | jq -r '.message')
                        echo -e "${RED}❌ 合并失败: $message${NC}"
                    fi
                fi
                press_enter_to_continue
                ;;
            4)
                # 关闭拉取请求
                echo -e "${BLUE}📝 获取开放的拉取请求...${NC}"
                open_pulls=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/pulls?state=open")
                
                count=$(echo "$open_pulls" | jq 'length')
                if [ "$count" -eq 0 ]; then
                    echo -e "${YELLOW}📝 该仓库没有开放的拉取请求${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                echo -e "\n${GREEN}📝 开放的拉取请求:${NC}"
                echo "--------------------------------"
                echo "$open_pulls" | jq -r '.[] | "#\(.number): \(.title)"'
                echo "--------------------------------"
                
                read -p "输入要关闭的拉取请求编号: " pr_number
                if [ -z "$pr_number" ]; then
                    echo -e "${RED}❌ 拉取请求编号不能为空${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                response=$(curl -s -X PATCH \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d '{"state": "closed"}' \
                    "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/pulls/$pr_number")
                
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ 关闭失败${NC}"
                else
                    state=$(echo "$response" | jq -r '.state')
                    if [ "$state" == "closed" ]; then
                        echo -e "${GREEN}✅ 拉取请求 #$pr_number 已关闭${NC}"
                        user_audit_log "CLOSE_PULL_REQUEST" "$repo_name/$pr_number"
                    else
                        echo -e "${RED}❌ 关闭失败${NC}"
                    fi
                fi
                press_enter_to_continue
                ;;
            5) return ;;
            *) 
                echo -e "${RED}❌ 无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# ====== 查看拉取请求详情 ======
view_pull_request_detail() {
    local repo_name=$1
    local pr_number=$2
    encoded_repo=$(urlencode "$repo_name")
    
    pull_request=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USER/$encoded_repo/pulls/$pr_number")
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 获取拉取请求详情失败${NC}"
        return
    fi
    
    title=$(echo "$pull_request" | jq -r '.title')
    state=$(echo "$pull_request" | jq -r '.state')
    user=$(echo "$pull_request" | jq -r '.user.login')
    created_at=$(echo "$pull_request" | jq -r '.created_at' | cut -d'T' -f1)
    updated_at=$(echo "$pull_request" | jq -r '.updated_at' | cut -d'T' -f1)
    body=$(echo "$pull_request" | jq -r '.body')
    base_branch=$(echo "$pull_request" | jq -r '.base.ref')
    head_branch=$(echo "$pull_request" | jq -r '.head.ref')
    mergeable=$(echo "$pull_request" | jq -r '.mergeable')
    merged=$(echo "$pull_request" | jq -r '.merged')
    comments_url=$(echo "$pull_request" | jq -r '.comments_url')
    
    echo -e "\n${YELLOW}拉取请求详情: #$pr_number - $title${NC}"
    echo "--------------------------------"
    echo -e "状态: ${state} | 创建者: $user"
    echo -e "创建时间: $created_at | 更新时间: $updated_at"
    echo -e "源分支: $head_branch -> 目标分支: $base_branch"
    echo -e "可合并: $mergeable | 已合并: $merged"
    echo -e "\n${BLUE}描述:${NC}"
    echo "$body"
    echo "--------------------------------"
    
    # 获取评论
    comments=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "$comments_url")
    
    comment_count=$(echo "$comments" | jq 'length')
    if [ "$comment_count" -gt 0 ]; then
        echo -e "\n${GREEN}评论 ($comment_count):${NC}"
        echo "--------------------------------"
        for i in $(seq 0 $((comment_count-1))); do
            comment_user=$(echo "$comments" | jq -r ".[$i].user.login")
            comment_date=$(echo "$comments" | jq -r ".[$i].created_at" | cut -d'T' -f1)
            comment_body=$(echo "$comments" | jq -r ".[$i].body")
            echo -e "${CYAN}$comment_user (于 $comment_date):${NC}"
            echo "$comment_body"
            echo "--------------------------------"
        done
    fi
    press_enter_to_continue
}
EOL
    echo -e "${GREEN}✓ 仓库管理模块创建完成${NC}"
}

# 创建高级功能模块
create_senior_module() {
cat > "$INSTALL_DIR/modules/senior.sh" << 'EOL'
#!/bin/bash

# 高级功能模块

# 加载配置和工具
source "$GIT_TOOLKIT_ROOT/common.sh"

# ====== 组织管理功能 ======
manage_organizations() {
    echo -e "${BLUE}🏢 获取组织列表...${NC}"
    orgs=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/user/orgs")
    
    if [ -z "$orgs" ] || [ "$orgs" == "[]" ]; then
        echo -e "${YELLOW}您不属于任何组织${NC}"
        press_enter_to_continue
        return
    fi
    
    mapfile -t org_array < <(echo "$orgs" | jq -r '.[].login')
    
    echo -e "\n${GREEN}您的组织:${NC}"
    echo "--------------------------------"
    for i in "${!org_array[@]}"; do
        echo "$((i+1)). ${org_array[$i]}"
    done
    echo "--------------------------------"
    
    read -p "选择组织序号 (0返回): " org_index
    if [[ $org_index -eq 0 ]]; then
        return
    fi
    
    if [[ ! $org_index =~ ^[0-9]+$ ]] || (( org_index < 1 || org_index > ${#org_array[@]} )); then
        echo -e "${RED}❌ 无效选择${NC}"
        press_enter_to_continue
        return
    fi
    
    selected_org="${org_array[$((org_index-1))]}"
    user_audit_log "SELECT_ORG" "$selected_org"
    
    while true; do
        clear
        echo -e "${BLUE}===================================${NC}"
        echo -e "${YELLOW}  组织管理: ${CYAN}$selected_org${NC}"
        echo -e "${BLUE}===================================${NC}"
        echo "1. 查看组织仓库"
        echo "2. 创建组织仓库"
        echo "3. 管理组织成员"
        echo "4. 查看组织设置"
        echo -e "${YELLOW}5. 返回主菜单${NC}"
        echo -e "${BLUE}===================================${NC}"
        
        read -p "选择操作: " choice
        
        case $choice in
            1) list_org_repos "$selected_org" ;;
            2) create_org_repo "$selected_org" ;;
            3) manage_org_members "$selected_org" ;;
            4) view_org_settings "$selected_org" ;;
            5) return ;;
            *) echo -e "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

# 列出组织仓库
list_org_repos() {
    local org="$1"
    echo -e "${BLUE}📦 获取组织仓库列表...${NC}"
    repos=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/orgs/$org/repos?per_page=100")
    
    if [ -z "$repos" ] || [ "$repos" == "[]" ]; then
        echo -e "${YELLOW}该组织没有仓库${NC}"
        press_enter_to_continue
        return
    fi
    
    echo -e "\n${GREEN}组织仓库列表:${NC}"
    echo "--------------------------------"
    echo "$repos" | jq -r '.[] | "\(.name) - \(.description // "无描述")"'
    echo "--------------------------------"
    press_enter_to_continue
}

# 创建组织仓库
create_org_repo() {
    local org="$1"
    echo -e "${BLUE}🚀 在组织 $org 中创建新仓库${NC}"
    
    read -p "📝 输入仓库名称: " repo_name
    read -p "📝 输入仓库描述: " repo_description
    read -p "🔒 是否设为私有仓库? (y/N): " private_input
    private_input=${private_input:-n}
    [[ "$private_input" =~ ^[Yy]$ ]] && private="true" || private="false"
    
    # 添加默认README文件
    read -p "📄 是否添加README文件? (Y/n): " readme_input
    readme_input=${readme_input:-y}
    [[ "$readme_input" =~ ^[Yy]$ ]] && auto_init="true" || auto_init="false"
    
    response=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{
            \"name\": \"$repo_name\",
            \"description\": \"$repo_description\",
            \"private\": $private,
            \"auto_init\": $auto_init
        }" "https://api.github.com/orgs/$org/repos")
    
    handle_github_response "$response" "仓库 $repo_name 创建成功"
    user_audit_log "CREATE_ORG_REPO" "$org/$repo_name"
    press_enter_to_continue
}

# 管理组织成员
manage_org_members() {
    local org="$1"
    echo -e "${BLUE}👥 管理组织成员: $org${NC}"
    
    while true; do
        echo -e "${CYAN}1. 添加成员${NC}"
        echo -e "${CYAN}2. 移除成员${NC}"
        echo -e "${CYAN}3. 查看成员列表${NC}"
        echo -e "${YELLOW}4. 返回${NC}"
        read -p "选择操作: " member_choice
        
        case $member_choice in
            1) add_org_member "$org" ;;
            2) remove_org_member "$org" ;;
            3) list_org_members "$org" ;;
            4) return ;;
            *) echo -e "${RED}无效选择${NC}";;
        esac
    done
}

# 添加组织成员
add_org_member() {
    local org="$1"
    read -p "输入要添加的GitHub用户名: " username
    
    echo -e "${BLUE}请选择成员角色:${NC}"
    echo "1. 成员 (member)"
    echo "2. 管理员 (admin)"
    read -p "选择角色 (1-2): " role_choice
    
    case $role_choice in
        1) role="member" ;;
        2) role="admin" ;;
        *) 
            echo -e "${RED}无效选择，默认为成员${NC}"
            role="member"
            ;;
    esac
    
    response=$(curl -s -X PUT \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/orgs/$org/memberships/$username" \
        -d "{\"role\": \"$role\"}")
    
    handle_github_response "$response" "已添加成员 $username"
    user_audit_log "ADD_ORG_MEMBER" "$org/$username"
    press_enter_to_continue
}

# 移除组织成员
remove_org_member() {
    local org="$1"
    read -p "输入要移除的GitHub用户名: " username
    
    response=$(curl -s -X DELETE \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/orgs/$org/members/$username")
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 已移除成员 $username${NC}"
        user_audit_log "REMOVE_ORG_MEMBER" "$org/$username"
    else
        echo -e "${RED}❌ 移除成员失败${NC}"
    fi
    press_enter_to_continue
}

# 列出组织成员
list_org_members() {
    local org="$1"
    echo -e "${BLUE}👥 获取组织成员列表...${NC}"
    
    members=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/orgs/$org/members")
    
    if [ -z "$members" ] || [ "$members" == "[]" ]; then
        echo -e "${YELLOW}该组织没有成员${NC}"
        press_enter_to_continue
        return
    fi
    
    echo -e "\n${GREEN}组织成员列表:${NC}"
    echo "--------------------------------"
    echo "$members" | jq -r '.[].login'
    echo "--------------------------------"
    press_enter_to_continue
}

# 查看组织设置
view_org_settings() {
    local org="$1"
    echo -e "${BLUE}⚙️ 获取组织设置信息...${NC}"
    
    settings=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/orgs/$org")
    
    if [ -z "$settings" ]; then
        echo -e "${RED}❌ 获取组织信息失败${NC}"
        press_enter_to_continue
        return
    fi
    
    echo -e "\n${GREEN}组织基本信息:${NC}"
    echo "--------------------------------"
    echo "名称: $(echo "$settings" | jq -r '.login')"
    echo "ID: $(echo "$settings" | jq -r '.id')"
    echo "描述: $(echo "$settings" | jq -r '.description // "无描述"')"
    echo "创建时间: $(echo "$settings" | jq -r '.created_at')"
    echo "邮箱: $(echo "$settings" | jq -r '.email // "未公开"')"
    echo "网站: $(echo "$settings" | jq -r '.blog // "未设置"')"
    echo "位置: $(echo "$settings" | jq -r '.location // "未设置"')"
    echo "公共仓库数: $(echo "$settings" | jq -r '.public_repos')"
    echo "私有仓库数: $(echo "$settings" | jq -r '.total_private_repos')"
    echo "--------------------------------"
    press_enter_to_continue
}

# ====== 分支管理功能 ======
manage_branches() {
    # 获取当前仓库信息
    if [ -z "$CURRENT_REPO" ]; then
        echo -e "${RED}❌ 未设置当前仓库${NC}"
        press_enter_to_continue
        return
    fi
    
    # 解析当前仓库URL获取仓库名
    repo_full_name=$(grep "^$CURRENT_REPO|" "$REPO_CONFIG_FILE" | cut -d'|' -f2)
    if [ -z "$repo_full_name" ]; then
        echo -e "${RED}❌ 无法获取仓库信息${NC}"
        press_enter_to_continue
        return
    fi
    
    # 提取用户名和仓库名
    local user_repo=${repo_full_name#https://github.com/}
    user_repo=${user_repo%.git}
    
    while true; do
        clear
        echo -e "${BLUE}===================================${NC}"
        echo -e "${YELLOW}  分支管理: ${CYAN}$user_repo${NC}"
        echo -e "${BLUE}===================================${NC}"
        echo "1. 查看分支列表"
        echo "2. 创建新分支"
        echo "3. 删除分支"
        echo "4. 合并分支"
        echo "5. 保护分支设置"
        echo -e "${YELLOW}6. 返回主菜单${NC}"
        echo -e "${BLUE}===================================${NC}"
        
        read -p "选择操作: " choice
        
        case $choice in
            1) list_branches "$user_repo" ;;
            2) create_branch "$user_repo" ;;
            3) delete_branch "$user_repo" ;;
            4) merge_branch "$user_repo" ;;
            5) protect_branch "$user_repo" ;;
            6) return ;;
            *) echo -e "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

# 列出分支
list_branches() {
    local user_repo=$1
    echo -e "${BLUE}🌿 获取分支列表...${NC}"
    branches=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$user_repo/branches")
    
    if [ -z "$branches" ] || [ "$branches" == "[]" ]; then
        echo -e "${YELLOW}该仓库没有分支${NC}"
        press_enter_to_continue
        return
    fi
    
    echo -e "\n${GREEN}分支列表:${NC}"
    echo "--------------------------------"
    echo "$branches" | jq -r '.[] | "\(.name) - \(.protected ? "保护分支" : "普通分支")"'
    echo "--------------------------------"
    press_enter_to_continue
}

# 创建分支
create_branch() {
    local user_repo=$1
    read -p "📝 输入新分支名称: " new_branch
    read -p "📝 输入源分支名称 (默认: main): " source_branch
    source_branch=${source_branch:-main}
    
    # 获取源分支的SHA
    ref_sha=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$user_repo/git/refs/heads/$source_branch" | jq -r '.object.sha')
    
    if [ -z "$ref_sha" ] || [ "$ref_sha" == "null" ]; then
        echo -e "${RED}❌ 获取源分支 $source_branch 信息失败${NC}"
        press_enter_to_continue
        return
    fi
    
    # 创建新分支
    response=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{
            \"ref\": \"refs/heads/$new_branch\",
            \"sha\": \"$ref_sha\"
        }" "https://api.github.com/repos/$user_repo/git/refs")
    
    handle_github_response "$response" "分支 $new_branch 创建成功"
    user_audit_log "CREATE_BRANCH" "$user_repo/$new_branch"
    press_enter_to_continue
}

# 删除分支
delete_branch() {
    local user_repo=$1
    read -p "📝 输入要删除的分支名称: " branch_to_delete
    
    # 检查是否默认分支
    default_branch=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$user_repo" | jq -r '.default_branch')
    
    if [ "$branch_to_delete" == "$default_branch" ]; then
        echo -e "${RED}❌ 不能删除默认分支 $default_branch${NC}"
        press_enter_to_continue
        return
    fi
    
    # 删除分支
    response=$(curl -s -X DELETE \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$user_repo/git/refs/heads/$branch_to_delete")
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 分支 $branch_to_delete 删除成功${NC}"
        user_audit_log "DELETE_BRANCH" "$user_repo/$branch_to_delete"
    else
        echo -e "${RED}❌ 分支删除失败${NC}"
    fi
    press_enter_to_continue
}

# 合并分支
merge_branch() {
    local user_repo=$1
    read -p "📝 输入源分支 (将被合并的分支): " source_branch
    read -p "📝 输入目标分支 (将接收更改的分支): " target_branch
    read -p "📝 输入合并提交信息: " commit_msg
    
    # 执行合并
    response=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{
            \"base\": \"$target_branch\",
            \"head\": \"$source_branch\",
            \"commit_message\": \"$commit_msg\"
        }" "https://api.github.com/repos/$user_repo/merges")
    
    merge_status=$(echo "$response" | jq -r '.merged')
    if [ "$merge_status" == "true" ]; then
        echo -e "${GREEN}✅ 分支 $source_branch 成功合并到 $target_branch${NC}"
        user_audit_log "MERGE_BRANCH" "$user_repo/$source_branch->$target_branch"
    else
        error_msg=$(echo "$response" | jq -r '.message')
        echo -e "${RED}❌ 合并失败: $error_msg${NC}"
    fi
    press_enter_to_continue
}

# 保护分支设置
protect_branch() {
    local user_repo=$1
    read -p "📝 输入要保护的分支名称: " branch
    
    echo -e "${BLUE}请选择保护选项:${NC}"
    echo "1. 启用基本保护 (禁止强制推送)"
    echo "2. 启用严格保护 (包括代码审查)"
    echo "3. 禁用保护"
    read -p "选择操作 (1-3): " protect_choice
    
    case $protect_choice in
        1)
            # 基本保护
            settings='{
                "required_status_checks": null,
                "enforce_admins": false,
                "required_pull_request_reviews": null,
                "restrictions": null,
                "allow_force_pushes": false
            }'
            ;;
        2)
            # 严格保护
            settings='{
                "required_status_checks": null,
                "enforce_admins": true,
                "required_pull_request_reviews": {
                    "required_approving_review_count": 1
                },
                "restrictions": null,
                "allow_force_pushes": false
            }'
            ;;
        3)
            # 禁用保护
            settings='{
                "required_status_checks": null,
                "enforce_admins": false,
                "required_pull_request_reviews": null,
                "restrictions": null,
                "allow_force_pushes": true
            }'
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return
            ;;
    esac
    
    # 更新分支保护
    response=$(curl -s -X PUT \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.luke-cage-preview+json" \
        -d "$settings" \
        "https://api.github.com/repos/$user_repo/branches/$branch/protection")
    
    if [ $? -eq 0 ]; then
        case $protect_choice in
            1|2) 
                echo -e "${GREEN}✅ 分支 $branch 保护设置已更新${NC}"
                user_audit_log "PROTECT_BRANCH" "$user_repo/$branch"
                ;;
            3)
                echo -e "${GREEN}✅ 分支 $branch 保护已禁用${NC}"
                user_audit_log "UNPROTECT_BRANCH" "$user_repo/$branch"
                ;;
        esac
    else
        echo -e "${RED}❌ 分支保护设置失败${NC}"
    fi
    press_enter_to_continue
}

# ====== 代码片段管理 ======
manage_gists() {
    while true; do
        clear
        echo -e "${BLUE}===================================${NC}"
        echo -e "${YELLOW}  GitHub代码片段管理${NC}"
        echo -e "${BLUE}===================================${NC}"
        echo "1. 查看代码片段列表"
        echo "2. 创建新代码片段"
        echo "3. 编辑代码片段"
        echo "4. 删除代码片段"
        echo -e "${YELLOW}5. 返回主菜单${NC}"
        echo -e "${BLUE}===================================${NC}"
        
        read -p "选择操作: " choice
        
        case $choice in
            1) list_gists ;;
            2) create_gist ;;
            3) edit_gist ;;
            4) delete_gist ;;
            5) return ;;
            *) echo -e "${RED}无效选择${NC}"; sleep 1 ;;
        esac
    done
}

# 列出代码片段
list_gists() {
    echo -e "${BLUE}💾 获取代码片段列表...${NC}"
    gists=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/gists")
    
    count=$(echo "$gists" | jq '. | length')
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}没有找到代码片段${NC}"
        press_enter_to_continue
        return
    fi
    
    echo -e "\n${GREEN}代码片段列表:${NC}"
    echo "--------------------------------"
    for i in $(seq 0 $((count-1))); do
        id=$(echo "$gists" | jq -r ".[$i].id")
        desc=$(echo "$gists" | jq -r ".[$i].description")
        files=$(echo "$gists" | jq -r ".[$i].files | keys[]")
        echo "$((i+1)). $desc [$id]"
        echo "    文件: $files"
    done
    echo "--------------------------------"
    press_enter_to_continue
}

# 创建代码片段
create_gist() {
    echo -e "${BLUE}🆕 创建新代码片段${NC}"
    read -p "📝 输入描述: " description
    read -p "📝 输入文件名: " filename
    read -p "🔒 是否设为公开? (y/N): " public_input
    public_input=${public_input:-n}
    [[ "$public_input" =~ ^[Yy]$ ]] && public="true" || public="false"
    
    # 使用临时文件编辑内容
    temp_file=$(mktemp)
    ${EDITOR:-vi} "$temp_file"
    
    if [ ! -s "$temp_file" ]; then
        echo -e "${RED}❌ 内容不能为空${NC}"
        rm -f "$temp_file"
        return
    fi
    
    content=$(cat "$temp_file" | jq -Rs .)
    rm -f "$temp_file"
    
    data=$(cat <<EOF
{
    "description": "$description",
    "public": $public,
    "files": {
        "$filename": {
            "content": $content
        }
    }
}
EOF
)
    
    response=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "$data" \
        "https://api.github.com/gists")
    
    handle_github_response "$response" "代码片段创建成功"
    user_audit_log "CREATE_GIST" "$(echo "$response" | jq -r '.id')"
    press_enter_to_continue
}

# 编辑代码片段
edit_gist() {
    list_gists
    read -p "📝 输入要编辑的代码片段ID: " gist_id
    
    # 获取现有内容
    gist_data=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/gists/$gist_id")
    
    if [ -z "$gist_data" ]; then
        echo -e "${RED}❌ 获取代码片段失败${NC}"
        return
    fi
    
    # 提取描述和文件
    description=$(echo "$gist_data" | jq -r '.description')
    files=$(echo "$gist_data" | jq -r '.files | keys[]')
    mapfile -t file_array < <(echo "$files")
    
    echo -e "\n${CYAN}当前描述: $description${NC}"
    echo -e "${CYAN}包含文件:${NC}"
    for i in "${!file_array[@]}"; do
        echo "$((i+1)). ${file_array[$i]}"
    done
    
    read -p "编辑描述? (留空保持原样): " new_desc
    [ -z "$new_desc" ] && new_desc="$description"
    
    # 选择要编辑的文件
    read -p "选择要编辑的文件序号 (0编辑所有文件): " file_index
    
    # 处理文件编辑
    files_json="{}"
    if [ "$file_index" -eq 0 ]; then
        # 编辑所有文件
        for file in "${file_array[@]}"; do
            temp_file=$(mktemp)
            echo -e "$(echo "$gist_data" | jq -r ".files[\"$file\"].content")" > "$temp_file"
            ${EDITOR:-vi} "$temp_file"
            content=$(cat "$temp_file" | jq -Rs .)
            rm -f "$temp_file"
            files_json=$(echo "$files_json" | jq --arg f "$file" --arg c "$content" '. + {($f): {"content": $c}}')
        done
    elif [[ $file_index =~ ^[0-9]+$ ]] && [ "$file_index" -le "${#file_array[@]}" ]; then
        # 编辑单个文件
        file_name="${file_array[$((file_index-1))]}"
        temp_file=$(mktemp)
        echo -e "$(echo "$gist_data" | jq -r ".files[\"$file_name\"].content")" > "$temp_file"
        ${EDITOR:-vi} "$temp_file"
        content=$(cat "$temp_file" | jq -Rs .)
        rm -f "$temp_file"
        files_json=$(echo "$files_json" | jq --arg f "$file_name" --arg c "$content" '. + {($f): {"content": $c}}')
    else
        echo -e "${RED}❌ 无效选择${NC}"
        return
    fi
    
    # 更新代码片段
    data=$(cat <<EOF
{
    "description": "$new_desc",
    "files": $files_json
}
EOF
)
    
    response=$(curl -s -X PATCH \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "$data" \
        "https://api.github.com/gists/$gist_id")
    
    handle_github_response "$response" "代码片段更新成功"
    user_audit_log "EDIT_GIST" "$gist_id"
    press_enter_to_continue
}

# 删除代码片段
delete_gist() {
    list_gists
    read -p "📝 输入要删除的代码片段ID: " gist_id
    
    response=$(curl -s -X DELETE \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/gists/$gist_id")
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 代码片段删除成功${NC}"
        user_audit_log "DELETE_GIST" "$gist_id"
    else
        echo -e "${RED}❌ 删除失败${NC}"
    fi
    press_enter_to_continue
}

# ====== 自动同步功能 ======
setup_auto_sync() {
    echo -e "${BLUE}🔄 设置自动同步${NC}"
    if [ "$AUTO_SYNC_INTERVAL" -gt 0 ]; then
        echo -e "当前自动同步间隔: ${CYAN}${AUTO_SYNC_INTERVAL}分钟${NC}"
        read -p "是否要修改间隔? (y/N): " modify
        if [[ ! "$modify" =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    read -p "输入自动同步间隔 (分钟，0表示禁用): " interval
    if [[ ! "$interval" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ 请输入有效数字${NC}"
        press_enter_to_continue
        return
    fi
    
    # 更新配置
    AUTO_SYNC_INTERVAL=$interval
    save_config
    
    if [ "$interval" -gt 0 ]; then
        # 创建systemd定时器
        echo -e "${BLUE}🛠 配置自动同步服务...${NC}"
        
        # 创建服务目录
        sudo mkdir -p /etc/systemd/system/
        
        # 创建定时器文件
        sudo bash -c "cat > /etc/systemd/system/github-toolkit-sync.timer <<EOF
[Unit]
Description=GitHub Toolkit Auto Sync Timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=${interval}min

[Install]
WantedBy=timers.target
EOF"
        
        # 创建服务文件
        sudo bash -c "cat > /etc/systemd/system/github-toolkit-sync.service <<EOF
[Unit]
Description=GitHub Toolkit Sync Service

[Service]
Type=oneshot
ExecStart=$(realpath "$0") --auto-sync
User=$USER
WorkingDirectory=$GIT_TOOLKIT_ROOT
EOF"
        
        # 启用服务
        sudo systemctl daemon-reload
        sudo systemctl enable github-toolkit-sync.timer
        sudo systemctl start github-toolkit-sync.timer
        
        echo -e "${GREEN}✅ 自动同步已启用，每${interval}分钟运行一次${NC}"
    else
        # 禁用服务
        sudo systemctl stop github-toolkit-sync.timer
        sudo systemctl disable github-toolkit-sync.timer
        echo -e "${GREEN}✅ 自动同步已禁用${NC}"
    fi
    press_enter_to_continue
}

# ====== 获取项目版本号 ======
get_project_version() {
    # 尝试从常见项目文件中提取版本号
    local version=""
    
    # 检查Node.js项目
    if [ -f "package.json" ]; then
        version=$(jq -r '.version' package.json 2>/dev/null)
    fi
    
    # 检查Java/Maven项目
    if [ -z "$version" ] && [ -f "pom.xml" ]; then
        version=$(grep -oP '<version>\K[^<]+' pom.xml | head -1 2>/dev/null)
    fi
    
    # 检查Gradle项目
    if [ -z "$version" ] && [ -f "build.gradle" ]; then
        version=$(grep -E "version\s*=\s*['\"][^'\"]+['\"]" build.gradle | sed -E "s/.*version\s*=\s*['\"]([^'\"]+)['\"].*/\1/" | head -1)
    fi
    
    # 如果找不到版本号，使用默认
    if [ -z "$version" ]; then
        version="1.0.0"
    fi
    
    echo "$version"
}

# ====== 标签管理功能 ======
manage_tags() {
    # 获取当前仓库信息
    if [ -z "$CURRENT_REPO" ]; then
        echo -e "${RED}❌ 未设置当前仓库${NC}"
        press_enter_to_continue
        return
    fi

    # 解析当前仓库URL获取仓库名
    repo_full_name=$(grep "^$CURRENT_REPO|" "$REPO_CONFIG_FILE" | cut -d'|' -f2)
    if [ -z "$repo_full_name" ]; then
        echo -e "${RED}❌ 无法获取仓库信息${NC}"
        press_enter_to_continue
        return
    fi

    # 提取用户名和仓库名
    local user_repo=${repo_full_name#https://github.com/}
    user_repo=${user_repo%.git}
    
    # 获取默认分支
    default_branch=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$user_repo" | jq -r '.default_branch')
        
    # 获取项目当前版本
    current_version=$(get_project_version)
    
    while true; do
        clear
        echo -e "${BLUE}===================================${NC}"
        echo -e "${YELLOW}  标签管理: ${CYAN}$user_repo${NC}"
        echo -e "${BLUE}===================================${NC}"
        echo "1. 查看标签列表"
        echo "2. 创建标签"
        echo "3. 删除标签"
        echo "4. 推送标签到远程"
        echo "5. 创建发布版本(Release)"
        echo "6. 管理发布版本"
        echo -e "${YELLOW}7. 返回主菜单${NC}"
        echo -e "${BLUE}===================================${NC}"

        read -p "选择操作: " choice

        case $choice in
            1)
                # 查看标签
                echo -e "${BLUE}🏷️ 获取标签列表...${NC}"
                tags=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$user_repo/tags")
                echo -e "\n${GREEN}标签列表:${NC}"
                echo "--------------------------------"
                echo "$tags" | jq -r '.[] | "\(.name) - \(.commit.sha[0:7])"'
                echo "--------------------------------"
                press_enter_to_continue
                ;;
            2)
                # 获取最新提交SHA
                latest_commit=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$user_repo/commits/$default_branch" | jq -r '.sha')
                
                # 建议标签名称（使用项目版本）
                suggested_tag="v${current_version}"
                
                echo -e "${CYAN}提示:${NC} 标签名称不能包含空格，请使用连字符(-)代替"
                echo -e "当前项目版本: ${GREEN}v${current_version}${NC}"
                read -p "输入标签名称 (默认: $suggested_tag): " tag_name
                tag_name=${tag_name:-$suggested_tag}
                
                # 清理标签名称（替换空格为连字符）
                tag_name=$(echo "$tag_name" | tr ' ' '-')
                
                read -p "输入标签描述 (默认: '$tag_name'): " tag_description
                tag_description=${tag_description:-"$tag_name"}
                
                echo -e "${CYAN}最新提交: ${GREEN}${latest_commit:0:7}${NC} (默认)"
                read -p "输入关联的提交SHA (留空使用最新提交): " commit_sha
                commit_sha=${commit_sha:-$latest_commit}

                # 创建标签对象
                response=$(curl -s -X POST \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d "{
                        \"tag\": \"$tag_name\",
                        \"message\": \"$tag_description\",
                        \"object\": \"$commit_sha\",
                        \"type\": \"commit\"
                    }" "https://api.github.com/repos/$user_repo/git/tags")

                # 检查是否创建成功
                tag_sha=$(echo "$response" | jq -r '.sha')
                if [ -n "$tag_sha" ] && [ "$tag_sha" != "null" ]; then
                    # 创建引用
                    ref_response=$(curl -s -X POST \
                        -H "Authorization: token $GITHUB_TOKEN" \
                        -H "Accept: application/vnd.github.v3+json" \
                        -d "{
                            \"ref\": \"refs/tags/$tag_name\",
                            \"sha\": \"$tag_sha\"
                        }" "https://api.github.com/repos/$user_repo/git/refs")
                    
                    if echo "$ref_response" | jq -e '.ref' >/dev/null; then
                        echo -e "${GREEN}✅ 标签创建成功${NC}"
                        user_audit_log "CREATE_TAG" "$user_repo/$tag_name"
                    else
                        error_msg=$(echo "$ref_response" | jq -r '.message')
                        echo -e "${RED}❌ 标签引用创建失败: ${error_msg}${NC}"
                    fi
                else
                    error_msg=$(echo "$response" | jq -r '.message')
                    echo -e "${RED}❌ 标签创建失败: ${error_msg}${NC}"
                fi
                press_enter_to_continue
                ;;
            3)
                # 显示标签列表辅助选择
                tags=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$user_repo/tags" | jq -r '.[].name')
                
                if [ -z "$tags" ]; then
                    echo -e "${YELLOW}该仓库没有标签${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                echo -e "\n${GREEN}可用标签:${NC}"
                echo "--------------------------------"
                echo "$tags"
                echo "--------------------------------"
                
                read -p "输入要删除的标签名称: " tag_name
                response=$(curl -s -X DELETE \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$user_repo/git/refs/tags/$tag_name")

                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✅ 标签删除成功${NC}"
                    user_audit_log "DELETE_TAG" "$user_repo/$tag_name"
                else
                    error_msg=$(echo "$response" | jq -r '.message')
                    echo -e "${RED}❌ 删除失败: $error_msg${NC}"
                fi
                press_enter_to_continue
                ;;
            4)
                # 显示未推送的标签
                echo -e "${BLUE}🔍 检测未推送的本地标签...${NC}"
                local_tags=$(git tag --list)
                remote_tags=$(git ls-remote --tags origin | awk -F'/' '{print $3}')
                unpushed_tags=""
                need_push=false
                
                for tag in $local_tags; do
                    if ! echo "$remote_tags" | grep -q "^$tag$"; then
                        unpushed_tags="$unpushed_tags $tag"
                        need_push=true
                    fi
                done
                
                if [ -z "$unpushed_tags" ]; then
                    echo -e "${GREEN}所有标签已同步到远程${NC}"
                else
                    echo -e "${YELLOW}以下标签尚未推送:${NC}"
                    echo "$unpushed_tags"
                fi
                
                read -p "输入要推送的标签名称 (或输入 'all' 推送所有): " tag_name
                if [ "$tag_name" == "all" ]; then
                    if [ "$need_push" == "true" ]; then
                        git push --tags
                    else
                        echo -e "${GREEN}没有需要推送的标签${NC}"
                    fi
                else
                    # 检查标签是否存在
                    if git show-ref --tags | grep -q "refs/tags/$tag_name"; then
                        git push origin "$tag_name"
                    else
                        echo -e "${RED}❌ 错误：标签 '$tag_name' 不存在${NC}"
                    fi
                fi
                press_enter_to_continue
                ;;

            5)
                create_release "$user_repo"
                ;;
            6)
                manage_releases "$user_repo"
                ;;
            7) return ;;
            *)
                echo -e "${RED}❌ 无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# ====== 创建发布版本 ======
create_release() {
    local user_repo=$1
    
    # 获取项目当前版本
    current_version=$(get_project_version)
    default_tag="v${current_version}"
    
    # 获取标签列表
    tags=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$user_repo/tags" | jq -r '.[].name')
    
    if [ -z "$tags" ]; then
        echo -e "${YELLOW}该仓库没有标签，请先创建标签${NC}"
        press_enter_to_continue
        return
    fi
    
    echo -e "\n${GREEN}可用标签:${NC}"
    echo "--------------------------------"
    # 显示带序号的标签列表
    i=1
    while IFS= read -r tag; do
        echo "$i. $tag"
        ((i++))
    done <<< "$tags"
    echo "--------------------------------"
    
    echo -e "当前项目版本: ${GREEN}$default_tag${NC}"
    read -p "输入标签序号 (或输入新标签名称，默认: $default_tag): " tag_input
    
    if [[ "$tag_input" =~ ^[0-9]+$ ]] && [ "$tag_input" -le "$(echo "$tags" | wc -l)" ]; then
        # 用户选择序号
        tag_name=$(echo "$tags" | sed -n "${tag_input}p")
    else
        # 用户输入新标签名
        tag_name=${tag_input:-$default_tag}
    fi
    
    # 清理标签名称
    tag_name=$(echo "$tag_name" | tr ' ' '-')
    
    read -p "输入发布标题 (默认: '$tag_name'): " title
    title=${title:-"$tag_name"}
    
    read -p "输入发布描述 (支持Markdown): " body
    
    echo -e "${BLUE}发布选项:${NC}"
    echo "1. 正式版"
    echo "2. 预发布版"
    read -p "选择发布类型 (1-2): " release_type
    
    case $release_type in
        1) prerelease="false" ;;
        2) prerelease="true" ;;
        *) 
            echo -e "${RED}❌ 无效选择，默认为正式版${NC}"
            prerelease="false"
            ;;
    esac
    
    # 创建发布
    response=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{
            \"tag_name\": \"$tag_name\",
            \"name\": \"$title\",
            \"body\": \"$body\",
            \"prerelease\": $prerelease
        }" "https://api.github.com/repos/$user_repo/releases")
    
    release_id=$(echo "$response" | jq -r '.id')
    if [ -n "$release_id" ] && [ "$release_id" != "null" ]; then
        echo -e "${GREEN}✅ 发布版本创建成功${NC}"
        user_audit_log "CREATE_RELEASE" "$user_repo/$tag_name"
        
        # 上传附件
read -p "是否要上传附件? (y/N): " upload_choice
if [[ "$upload_choice" =~ ^[Yy]$ ]]; then
    upload_assets "$user_repo" "$release_id"
fi
    else
        error_msg=$(echo "$response" | jq -r '.message')
        echo -e "${RED}❌ 创建失败: ${error_msg}${NC}"
    fi
    press_enter_to_continue
}

# ====== 上传附件到发布版本 ======
upload_assets() {
    local user_repo=$1
    local release_id=$2
    
    read -p "📎 输入要上传的文件路径: " file_path
    if [ ! -f "$file_path" ]; then
        echo -e "${RED}❌ 文件不存在${NC}"
        press_enter_to_continue
        return
    fi
    
    file_name=$(basename "$file_path")
    upload_url="https://uploads.github.com/repos/$user_repo/releases/$release_id/assets?name=$file_name"
    
    echo -e "${BLUE}⬆️ 上传附件: $file_name...${NC}"
    response=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@$file_path" \
        "$upload_url")
    
    asset_id=$(echo "$response" | jq -r '.id')
    if [ -n "$asset_id" ] && [ "$asset_id" != "null" ]; then
        echo -e "${GREEN}✅ 附件上传成功${NC}"
        user_audit_log "UPLOAD_ASSET" "$user_repo/$file_name"
    else
        error_msg=$(echo "$response" | jq -r '.message')
        echo -e "${RED}❌ 上传失败: ${error_msg}${NC}"
    fi
    press_enter_to_continue
}

# ====== 管理发布版本 ======
manage_releases() {
    local user_repo=$1
    
    echo -e "${BLUE}📦 获取发布列表...${NC}"
    releases=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$user_repo/releases")
    
    count=$(echo "$releases" | jq '. | length')
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}没有发布版本${NC}"
        press_enter_to_continue
        return
    fi
    
    echo -e "\n${GREEN}发布版本列表:${NC}"
    echo "--------------------------------"
    for i in $(seq 0 $((count-1))); do
        id=$(echo "$releases" | jq -r ".[$i].id")
        tag=$(echo "$releases" | jq -r ".[$i].tag_name")
        name=$(echo "$releases" | jq -r ".[$i].name")
        prerelease=$(echo "$releases" | jq -r ".[$i].prerelease")
        assets_count=$(echo "$releases" | jq -r ".[$i].assets | length")
        
        prerelease_status=$([ "$prerelease" == "true" ] && echo "预发布" || echo "正式版")
        echo "$((i+1)). [$tag] $name ($prerelease_status) - 附件: $assets_count"
    done
    echo "--------------------------------"
    
    read -p "选择发布版本序号 (0取消): " release_index
    if [[ $release_index -eq 0 ]]; then
        return
    fi
    
    if [[ ! $release_index =~ ^[0-9]+$ ]] || (( release_index < 1 || release_index > count )); then
        echo -e "${RED}❌ 无效选择${NC}"
        press_enter_to_continue
        return
    fi
    
    release_id=$(echo "$releases" | jq -r ".[$((release_index-1))].id")
    
    while true; do
        clear
        release_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$user_repo/releases/$release_id")
        
        tag_name=$(echo "$release_info" | jq -r '.tag_name')
        name=$(echo "$release_info" | jq -r '.name')
        body=$(echo "$release_info" | jq -r '.body')
        prerelease=$(echo "$release_info" | jq -r '.prerelease')
        created_at=$(echo "$release_info" | jq -r '.created_at')
        assets=$(echo "$release_info" | jq -r '.assets')
        
        prerelease_status=$([ "$prerelease" == "true" ] && echo "预发布" || echo "正式版")
        
        echo -e "${BLUE}===================================${NC}"
        echo -e "${YELLOW}  发布版本管理: ${CYAN}$name${NC}"
        echo -e "${BLUE}===================================${NC}"
        echo -e "标签: ${GREEN}$tag_name${NC}"
        echo -e "类型: ${CYAN}$prerelease_status${NC}"
        echo -e "创建时间: ${CYAN}$created_at${NC}"
        echo -e "\n${YELLOW}描述:${NC}"
        echo -e "$body"
        
        echo -e "\n${GREEN}附件列表:${NC}"
        echo "--------------------------------"
        assets_count=$(echo "$assets" | jq '. | length')
        if [ "$assets_count" -eq 0 ]; then
            echo "无附件"
        else
            for i in $(seq 0 $((assets_count-1))); do
                asset_name=$(echo "$assets" | jq -r ".[$i].name")
                asset_size=$(echo "$assets" | jq -r ".[$i].size")
                asset_downloads=$(echo "$assets" | jq -r ".[$i].download_count")
                echo "$((i+1)). $asset_name (${asset_size}字节, 下载: ${asset_downloads})"
            done
        fi
        echo "--------------------------------"
        
        echo -e "\n${CYAN}操作选项:${NC}"
        echo "1. 上传新附件"
        echo "2. 下载附件"
        echo "3. 删除附件"
        echo "4. 编辑发布信息"
        echo "5. 切换发布状态"
        echo "6. 删除此发布"
        echo -e "${YELLOW}7. 返回${NC}"
        echo -e "${BLUE}===================================${NC}"
        
        read -p "选择操作: " operation
        
        case $operation in
            1)
                upload_assets "$user_repo" "$release_id"
                ;;
            2)
                if [ "$assets_count" -eq 0 ]; then
                    echo -e "${YELLOW}没有附件可下载${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                read -p "输入附件序号: " asset_index
                if [[ $asset_index =~ ^[0-9]+$ ]] && (( asset_index >= 1 && asset_index <= assets_count )); then
                    asset_url=$(echo "$assets" | jq -r ".[$((asset_index-1))].browser_download_url")
                    asset_name=$(echo "$assets" | jq -r ".[$((asset_index-1))].name")
                    
                    echo -e "${BLUE}⬇️ 下载附件 $asset_name...${NC}"
                    curl -L -O -H "Authorization: token $GITHUB_TOKEN" "$asset_url"
                    
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}✅ 下载成功${NC}"
                    else
                        echo -e "${RED}❌ 下载失败${NC}"
                    fi
                else
                    echo -e "${RED}❌ 无效序号${NC}"
                fi
                press_enter_to_continue
                ;;
            3)
                if [ "$assets_count" -eq 0 ]; then
                    echo -e "${YELLOW}没有附件可删除${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                read -p "输入要删除的附件序号: " asset_index
                if [[ $asset_index =~ ^[0-9]+$ ]] && (( asset_index >= 1 && asset_index <= assets_count )); then
                    asset_id=$(echo "$assets" | jq -r ".[$((asset_index-1))].id")
                    asset_name=$(echo "$assets" | jq -r ".[$((asset_index-1))].name")
                    
                    response=$(curl -s -X DELETE \
                        -H "Authorization: token $GITHUB_TOKEN" \
                        -H "Accept: application/vnd.github.v3+json" \
                        "https://api.github.com/repos/$user_repo/releases/assets/$asset_id")
                    
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}✅ 附件删除成功${NC}"
                        user_audit_log "DELETE_ASSET" "$user_repo/$asset_name"
                    else
                        echo -e "${RED}❌ 删除失败${NC}"
                    fi
                else
                    echo -e "${RED}❌ 无效序号${NC}"
                fi
                press_enter_to_continue
                ;;
            4)
                read -p "输入新标题 (留空保持不变): " new_title
                read -p "输入新描述 (留空保持不变): " new_body
                
                # 使用当前值作为默认值
                [ -z "$new_title" ] && new_title="$name"
                [ -z "$new_body" ] && new_body="$body"
                
                response=$(curl -s -X PATCH \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d "{
                        \"name\": \"$new_title\",
                        \"body\": \"$new_body\"
                    }" "https://api.github.com/repos/$user_repo/releases/$release_id")
                
                if echo "$response" | jq -e '.id' >/dev/null; then
                    echo -e "${GREEN}✅ 发布信息更新成功${NC}"
                else
                    error_msg=$(echo "$response" | jq -r '.message')
                    echo -e "${RED}❌ 更新失败: ${error_msg}${NC}"
                fi
                press_enter_to_continue
                ;;
            5)
                # 切换发布状态
                new_prerelease=$([ "$prerelease" == "true" ] && echo "false" || echo "true")
                new_status=$([ "$new_prerelease" == "true" ] && echo "预发布版" || echo "正式版")
                
                echo -e "当前状态: ${CYAN}$prerelease_status${NC}"
                echo -e "新状态: ${GREEN}$new_status${NC}"
                
                read -p "确定要切换发布状态? (y/N): " confirm
                if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                    press_enter_to_continue
                    continue
                fi
                
                response=$(curl -s -X PATCH \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    -d "{
                        \"prerelease\": $new_prerelease
                    }" "https://api.github.com/repos/$user_repo/releases/$release_id")
                
                if echo "$response" | jq -e '.id' >/dev/null; then
                    echo -e "${GREEN}✅ 发布状态已切换为 $new_status${NC}"
                    user_audit_log "CHANGE_RELEASE_STATUS" "$user_repo/$tag_name -> $new_status"
                else
                    error_msg=$(echo "$response" | jq -r '.message')
                    echo -e "${RED}❌ 状态切换失败: ${error_msg}${NC}"
                fi
                press_enter_to_continue
                ;;
            6)
                read -p "⚠️  确定要删除此发布? (y/N): " confirm
                if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                    continue
                fi
                
                response=$(curl -s -X DELETE \
                    -H "Authorization: token $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/$user_repo/releases/$release_id")
                
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✅ 发布删除成功${NC}"
                    user_audit_log "DELETE_RELEASE" "$user_repo/$tag_name"
                    break
                else
                    echo -e "${RED}❌ 删除失败${NC}"
                fi
                press_enter_to_continue
                ;;
            7)
                break
                ;;
            *)
                echo -e "${RED}❌ 无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}


# ====== 文件历史查看 ======
view_file_history() {
    # 检查当前目录是否是Git仓库
    if [ ! -d ".git" ]; then
        echo -e "${RED}❌ 当前目录不是Git仓库${NC}"
        press_enter_to_continue
        return 1
    fi

    read -p "📄 输入文件路径: " file_path
    if [ ! -f "$file_path" ]; then
        echo -e "${RED}❌ 文件不存在${NC}"
        press_enter_to_continue
        return 1
    fi

    echo -e "${BLUE}📜 文件提交历史:${NC}"
    git log --pretty=format:"%h - %an, %ar : %s" -- "$file_path"

    echo -e "\n${YELLOW}1. 查看文件变更"
    echo "2. 恢复文件到指定版本"
    echo -e "${BLUE}3. 返回${NC}"
    read -p "选择操作: " history_choice

    case $history_choice in
        1)
            git log -p -- "$file_path" | less
            ;;
        2)
            read -p "输入要恢复的提交ID: " commit_id
            if git checkout "$commit_id" -- "$file_path"; then
                echo -e "${GREEN}✅ 文件已恢复${NC}"
            else
                echo -e "${RED}❌ 恢复失败${NC}"
            fi
            press_enter_to_continue
            ;;
        3) return ;;
        *) 
            echo -e "${RED}❌ 无效选择${NC}"
            sleep 1
            ;;
    esac
}


# ====== Git LFS管理 ======
manage_git_lfs() {
    # 检查是否安装Git LFS
    if ! command -v git-lfs &>/dev/null; then
        echo -e "${YELLOW}⚠️ Git LFS 未安装${NC}"
        read -p "是否安装Git LFS? (y/N): " install_lfs
        if [[ "$install_lfs" =~ ^[Yy]$ ]]; then
            sudo apt-get install git-lfs -y
            git lfs install
        else
            return
        fi
    fi

    while true; do
        clear
        echo -e "${BLUE}===================================${NC}"
        echo -e "${YELLOW}          Git LFS 管理${NC}"
        echo -e "${BLUE}===================================${NC}"
        echo "1. 添加LFS跟踪"
        echo "2. 查看LFS跟踪"
        echo "3. 拉取LFS文件"
        echo "4. 查看LFS文件列表"
        echo -e "${YELLOW}5. 返回主菜单${NC}"
        echo -e "${BLUE}===================================${NC}"

        read -p "请选择操作: " choice

        case $choice in
            1)
                read -p "输入要跟踪的文件模式 (例如: *.psd): " pattern
                if git lfs track "$pattern"; then
                    echo -e "${GREEN}✅ 跟踪模式添加成功${NC}"
                    git add .gitattributes
                else
                    echo -e "${RED}❌ 添加失败${NC}"
                fi
                press_enter_to_continue
                ;;
            2)
                echo -e "${GREEN}当前跟踪模式:${NC}"
                git lfs track
                press_enter_to_continue
                ;;
            3)
                if git lfs pull; then
                    echo -e "${GREEN}✅ LFS文件拉取成功${NC}"
                else
                    echo -e "${RED}❌ 拉取失败${NC}"
                fi
                press_enter_to_continue
                ;;
            4)
                echo -e "${GREEN}LFS文件列表:${NC}"
                git lfs ls-files
                press_enter_to_continue
                ;;
            5) return ;;
            *)
                echo -e "${RED}❌ 无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}


# ====== 代码搜索功能 ======
search_code() {
    read -p "🔍 输入要搜索的代码关键词: " query
    if [ -z "$query" ]; then
        echo -e "${RED}❌ 搜索词不能为空${NC}"
        press_enter_to_continue
        return
    fi

    echo -e "${BLUE}🔍 正在搜索代码: $query ...${NC}"
    # 使用GitHub代码搜索API
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/search/code?q=${query}+user:${GITHUB_USER}")

    total_count=$(echo "$response" | jq -r '.total_count')
    if [ "$total_count" -eq 0 ]; then
        echo -e "${YELLOW}🔍 没有找到匹配的代码${NC}"
        press_enter_to_continue
        return
    fi

    echo -e "\n${GREEN}🔍 找到 $total_count 个匹配的代码片段:${NC}"
    echo "--------------------------------"
    items=$(echo "$response" | jq -r '.items[] | "\(.repository.name)/\(.path): 片段 \(.fragment)"')
    # 注意：由于代码片段可能很长，我们只显示前5个结果
    count=0
    while IFS= read -r line; do
        if [ $count -lt 5 ]; then
            echo -e "${CYAN}$line${NC}"
            echo "--------------------------------"
            ((count++))
        else
            break
        fi
    done <<< "$items"
    if [ "$total_count" -gt 5 ]; then
        echo -e "${YELLOW}... (只显示前5个结果)${NC}"
    fi
    press_enter_to_continue
}
EOL

echo -e "${GREEN}✓ 高级功能模块创建完成${NC}"
}

# 创建系统功能模块
create_system_module() {
cat > "$INSTALL_DIR/modules/system.sh" << 'EOL'
#!/bin/bash

# 系统功能模块

# 加载配置和工具
source "$GIT_TOOLKIT_ROOT/common.sh"
source "$GIT_TOOLKIT_ROOT/modules/platforms.sh"  # 加载多平台支持

# 首次运行配置向导
first_run_wizard() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}✨ 欢迎使用AliGitHub同步管理工具! 让我们完成初始配置...${NC}"
        
        # 获取GitHub用户名
        while true; do
            read -p "🔑 请输入GitHub用户名: " GITHUB_USER
            if [[ -n "$GITHUB_USER" ]]; then
                break
            else
                echo -e "${RED}❌ 用户名不能为空${NC}"
            fi
        done
        
        # 获取GitHub访问令牌
        while true; do
            read -s -p "🔑 请输入GitHub访问令牌: " GITHUB_TOKEN
            echo
            if [[ -n "$GITHUB_TOKEN" ]]; then
                break
            else
                echo -e "${RED}❌ 令牌不能为空${NC}"
            fi
        done
        
        # 获取同步目录
        read -p "📁 请输入同步目录路径 [默认: /root/github_sync]: " SYNC_DIR
        SYNC_DIR=${SYNC_DIR:-/root/github_sync}
        
        # 创建配置文件
        cat > "$CONFIG_FILE" <<EOF
CONFIG_VERSION="$VERSION"
GITHUB_USER="$GITHUB_USER"
GITHUB_TOKEN="$GITHUB_TOKEN"
SYNC_DIR="$SYNC_DIR"
CURRENT_REPO=""
AUTO_SYNC_INTERVAL=0
AUTO_SYNC_SOURCE=""
AUTO_SYNC_TARGET=""
EOF
        
        # 创建空仓库配置文件
        touch "$REPO_CONFIG_FILE"
        
        # 配置多平台支持
        echo -e "${YELLOW}✨ 配置多平台支持...${NC}"
        read -p "🔑 是否启用Gitee支持? (y/N): " enable_gitee
        if [[ "$enable_gitee" =~ ^[Yy]$ ]]; then
            read -p "🔑 输入Gitee用户名: " GITEE_USER
            read -s -p "🔑 输入Gitee访问令牌: " GITEE_TOKEN
            echo
            PLATFORMS=(
                "github|$GITHUB_USER|$GITHUB_TOKEN|true"
                "gitee|$GITEE_USER|$GITEE_TOKEN|true"
            )
    # 设置全局变量
    export GITEE_USER
        else
            PLATFORMS=(
                "github|$GITHUB_USER|$GITHUB_TOKEN|true"
                "gitee|||false"
            )
        fi
        save_platform_config
        
        # 初始化日志
        log "INFO" "首次运行配置完成，用户: $GITHUB_USER"
        
        echo -e "${GREEN}✅ 初始配置已完成!${NC}"
        return 0
    fi
    return 1
}



# 加载配置文件
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        # 配置版本迁移
        if [ "$CONFIG_VERSION" != "$VERSION" ]; then
            migrate_config
        fi
        return 0
    fi
    return 1
}

# 配置迁移
migrate_config() {
    log "INFO" "迁移配置文件到版本 $VERSION"
    # 添加新字段
    if ! grep -q "AUTO_SYNC_INTERVAL" "$CONFIG_FILE"; then
        echo "AUTO_SYNC_INTERVAL=0" >> "$CONFIG_FILE"
    fi
    if ! grep -q "AUTO_SYNC_SOURCE" "$CONFIG_FILE"; then
        echo "AUTO_SYNC_SOURCE=\"\"" >> "$CONFIG_FILE"
        echo "AUTO_SYNC_TARGET=\"\"" >> "$CONFIG_FILE"
    fi
    # 更新版本号
    sed -i "s/CONFIG_VERSION=.*/CONFIG_VERSION=\"$VERSION\"/" "$CONFIG_FILE"
    log "INFO" "配置文件迁移完成"
}

# 保存配置文件
save_config() {
    cat > "$CONFIG_FILE" <<EOF
CONFIG_VERSION="$VERSION"
GITHUB_USER="$GITHUB_USER"
GITHUB_TOKEN="$GITHUB_TOKEN"
SYNC_DIR="$SYNC_DIR"
CURRENT_REPO="$CURRENT_REPO"
AUTO_SYNC_INTERVAL="$AUTO_SYNC_INTERVAL"
AUTO_SYNC_SOURCE="$AUTO_SYNC_SOURCE"
AUTO_SYNC_TARGET="$AUTO_SYNC_TARGET"
EOF
}

# ====== 增强系统信息功能 ======
show_system_info() {
    load_platform_config
    
    echo -e "${YELLOW}===== 系统信息 =====${NC}"
    echo -e "工具箱版本: ${CYAN}v$VERSION${NC}"
    echo -e "系统: ${CYAN}$(lsb_release -ds 2>/dev/null || uname -a)${NC}"
    
    # CPU信息
    cpu_model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')
    cpu_cores=$(grep -c "^processor" /proc/cpuinfo)
    echo -e "CPU: ${CYAN}${cpu_model} (${cpu_cores}核)${NC}"
    
    # 内存信息
    mem_total=$(free -h | awk '/Mem/{print $2}')
    mem_used=$(free -h | awk '/Mem/{print $3}')
    mem_percent=$(free | awk '/Mem/{printf "%.1f", $3/$2*100}')
    echo -e "内存: ${CYAN}${mem_used}/${mem_total} (${mem_percent}%)${NC}"
    
    # 磁盘信息
    disk_info=$(df -h / | awk 'NR==2{print $4 " 可用 / " $2 " 总容量 / " $5 " 已用"}')
    echo -e "存储: ${CYAN}${disk_info}${NC}"
    
    # 网络信息
    ip_address=$(hostname -I | awk '{print $1}' 2>/dev/null)
    public_ip=$(curl -s ifconfig.me 2>/dev/null || echo "未知")
    echo -e "IP地址: ${CYAN}内网: ${ip_address:-未知} | 公网: ${public_ip}${NC}"
    
    # 温度监控（如果可用）
    if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
        temp=$(awk '{print $1/1000}' /sys/class/thermal/thermal_zone0/temp)
        echo -e "CPU温度: ${CYAN}${temp}°C${NC}"
    fi
    
    # 系统运行时间
    uptime_info=$(uptime -p | sed 's/up //')
    echo -e "运行时间: ${CYAN}${uptime_info}${NC}"
    
    # 显示自动同步状态
    if [ "$AUTO_SYNC_INTERVAL" -gt 0 ]; then
        next_sync=$((AUTO_SYNC_INTERVAL * 60))
        next_run=$(date -d "+${next_sync} seconds" "+%H:%M:%S")
        echo -e "自动同步: ${GREEN}启用 (每${AUTO_SYNC_INTERVAL}分钟, 下次运行: ${next_run})${NC}"
    else
        echo -e "自动同步: ${RED}禁用${NC}"
    fi
    
    # 显示多平台配置
    echo -e "${YELLOW}===== 平台配置 =====${NC}"
    for platform_info in "${PLATFORMS[@]}"; do
        IFS='|' read -r platform username token enabled <<< "$platform_info"
        status=$([ "$enabled" = "true" ] && echo -e "${GREEN}启用${NC}" || echo -e "${RED}禁用${NC}")
        echo -e "$(echo "$platform" | tr '[:lower:]' '[:upper:]'): $status"
    done
    
    # 显示镜像同步配置
    if [ -n "$AUTO_SYNC_SOURCE" ] && [ -n "$AUTO_SYNC_TARGET" ]; then
        echo -e "${YELLOW}===== 镜像同步 ====="
        echo -e "${GREEN}$AUTO_SYNC_SOURCE → $AUTO_SYNC_TARGET${NC}"
    fi
    
    # 添加工具箱状态检查
    echo -e "${YELLOW}===== 工具箱状态 ====="
    check_toolkit_status
    
    echo -e "${YELLOW}====================${NC}"
    press_enter_to_continue
}

# ====== 工具箱状态检查 ======
check_toolkit_status() {
    # 检查Git配置
    git_user=$(git config --global user.name 2>/dev/null || echo "未设置")
    git_email=$(git config --global user.email 2>/dev/null || echo "未设置")
    echo -e "Git用户: ${CYAN}${git_user} <${git_email}>${NC}"
    
    # 检查同步目录状态
    if [ -d "$SYNC_DIR" ]; then
        dir_size=$(du -sh "$SYNC_DIR" | awk '{print $1}')
        repo_count=$(find "$SYNC_DIR" -maxdepth 1 -type d -name '.git' | wc -l)
        echo -e "同步目录: ${GREEN}$SYNC_DIR (${repo_count}个仓库, ${dir_size})${NC}"
    else
        echo -e "同步目录: ${RED}未创建${NC}"
    fi
    
    # 检查API连通性
    check_api_connectivity
}

# ====== 检查API连通性 ======
check_api_connectivity() {
    echo -n "GitHub API: "
    response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user)
    if [ "$response" = "200" ]; then
        echo -e "${GREEN}正常${NC}"
    else
        echo -e "${RED}异常 (状态码: $response)${NC}"
    fi
    
    # 检查Gitee连通性（如果启用）
    for platform_info in "${PLATFORMS[@]}"; do
        IFS='|' read -r platform username token enabled <<< "$platform_info"
        if [ "$platform" = "gitee" ] && [ "$enabled" = "true" ]; then
            echo -n "Gitee API: "
            response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $token" https://gitee.com/api/v5/user)
            if [ "$response" = "200" ]; then
                echo -e "${GREEN}正常${NC}"
            else
                echo -e "${RED}异常 (状态码: $response)${NC}"
            fi
        fi
    done
}

# ====== 系统资源监控 ======
monitor_system_resources() {
    clear
    echo -e "${YELLOW}===== 系统资源实时监控 =====${NC}"
    echo -e "按 Ctrl+C 停止监控"
    echo -e "${BLUE}--------------------------------------------------${NC}"
    
    while true; do
        # CPU使用率
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')
        
        # 内存使用
        mem_info=$(free -m | awk 'NR==2{printf "%.1f%% (%.1fG/%.1fG)", $3/$2*100, $3/1024, $2/1024}')
        
        # 磁盘使用
        disk_info=$(df -h / | awk 'NR==2{print $5 " (" $4 " 可用)"}')
        
        # 网络流量
        network_info=$(ifstat -T 0.1 1 | tail -1 | awk '{print "↑" $2 " ↓" $1}')
        
        # 获取当前时间
        current_time=$(date "+%Y-%m-%d %H:%M:%S")
        
        # 输出资源信息
        echo -e "${CYAN}[$current_time] CPU: ${cpu_usage} | 内存: ${mem_info} | 磁盘: ${disk_info} | 网络: ${network_info}${NC}"
        
        sleep 2
    done
}

# ====== 工具箱诊断 ======
diagnose_toolkit() {
    echo -e "${YELLOW}===== 工具箱诊断 =====${NC}"
    
    # 检查依赖项
    echo -e "${BLUE}检查系统依赖...${NC}"
    check_dependencies
    echo -e "${GREEN}✓ 系统依赖检查完成${NC}"
    
    # 检查配置文件
    echo -e "${BLUE}检查配置文件...${NC}"
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo -e "${GREEN}✓ 配置文件存在 (版本: $CONFIG_VERSION)${NC}"
    else
        echo -e "${RED}✗ 配置文件缺失${NC}"
    fi
    
    # 检查日志目录
    echo -e "${BLUE}检查日志系统...${NC}"
    if [ -d "$LOG_DIR" ]; then
        log_count=$(find "$LOG_DIR" -type f | wc -l)
        echo -e "${GREEN}✓ 日志目录存在 (${log_count}个日志文件)${NC}"
    else
        echo -e "${YELLOW}⚠ 日志目录不存在${NC}"
    fi
    
    # 检查同步目录
    echo -e "${BLUE}检查同步目录...${NC}"
    if [ -d "$SYNC_DIR" ]; then
        repo_count=$(find "$SYNC_DIR" -maxdepth 1 -type d -name '.git' | wc -l)
        echo -e "${GREEN}✓ 同步目录存在 (${repo_count}个仓库)${NC}"
    else
        echo -e "${RED}✗ 同步目录不存在${NC}"
    fi
    
    # 检查API连接
    echo -e "${BLUE}检查API连接...${NC}"
    check_api_connectivity
    
    # 生成诊断报告
    generate_diagnostic_report
    
    echo -e "${YELLOW}====================${NC}"
    press_enter_to_continue
}

# ====== 生成诊断报告 ======
generate_diagnostic_report() {
    report_file="$LOG_DIR/diagnostic_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "===== 工具箱诊断报告 ====="
        echo "生成时间: $(date)"
        echo "工具箱版本: $VERSION"
        echo "系统信息: $(uname -a)"
        echo ""
        echo "=== 配置文件 ==="
        if [ -f "$CONFIG_FILE" ]; then
            cat "$CONFIG_FILE"
        else
            echo "配置文件不存在"
        fi
        
        echo ""
        echo "=== 平台配置 ==="
        if [ -f "$PLATFORM_CONFIG_FILE" ]; then
            cat "$PLATFORM_CONFIG_FILE"
        else
            echo "平台配置文件不存在"
        fi
        
        echo ""
        echo "=== 仓库配置 ==="
        if [ -f "$REPO_CONFIG_FILE" ]; then
            cat "$REPO_CONFIG_FILE"
        else
            echo "仓库配置文件不存在"
        fi
        
        echo ""
        echo "=== 系统状态 ==="
        echo "内存: $(free -h | awk '/Mem/{print $3 "/" $2}')"
        echo "存储: $(df -h / | awk 'NR==2{print $4 " 可用"}')"
        if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
            temp=$(awk '{print $1/1000}' /sys/class/thermal/thermal_zone0/temp)
            echo "CPU温度: ${temp}°C"
        fi
        
    } > "$report_file"
    
    echo -e "${GREEN}诊断报告已生成: ${report_file}${NC}"
    log "DIAGNOSTIC" "诊断报告生成: $report_file"
}

# ====== 日志查看器 ======
view_logs() {
    while true; do
        clear
        echo -e "${YELLOW}===== 日志查看器 =====${NC}"
        echo "1. 查看工具箱日志 ($LOG_FILE)"
        echo "2. 查看审计日志 ($AUDIT_LOG_FILE)"
        echo "3. 查看错误日志"
        echo "4. 清理日志文件"
        echo "5. 返回主菜单"
        echo -e "${BLUE}--------------------------------------------------${NC}"
        
        read -p "请选择操作 (1-5): " choice
        
        case $choice in
            1)
                view_log_file "$LOG_FILE" "工具箱日志"
                ;;
            2)
                view_log_file "$AUDIT_LOG_FILE" "审计日志"
                ;;
            3)
                view_error_logs
                ;;
            4)
                clear_logs
                ;;
            5)
                return
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# ====== 查看日志文件 ======
view_log_file() {
    local log_file=$1
    local log_name=$2
    
    if [ ! -f "$log_file" ]; then
        echo -e "${RED}日志文件不存在: $log_file${NC}"
        press_enter_to_continue
        return
    fi
    
    clear
    echo -e "${YELLOW}===== ${log_name} (最新20行) =====${NC}"
    tail -n 20 "$log_file"
    echo -e "${BLUE}--------------------------------------------------${NC}"
    echo "1. 查看完整日志"
    echo "2. 实时监控日志"
    echo "3. 搜索日志内容"
    echo "4. 返回"
    
    while true; do
        read -p "请选择操作 (1-4): " sub_choice
        
        case $sub_choice in
            1)
                less "$log_file"
                ;;
            2)
                echo -e "${GREEN}开始实时监控 (按 Ctrl+C 停止)...${NC}"
                tail -f "$log_file"
                ;;
            3)
                read -p "输入搜索关键词: " search_term
                grep -i --color=auto "$search_term" "$log_file" | less -R
                ;;
            4)
                return
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                ;;
        esac
    done
}

# ====== 查看错误日志 ======
view_error_logs() {
    clear
    echo -e "${YELLOW}===== 错误日志 =====${NC}"
    
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${RED}日志文件不存在${NC}"
        press_enter_to_continue
        return
    fi
    
    # 提取ERROR级别的日志
    grep -a "ERROR" "$LOG_FILE" > /tmp/error_logs.tmp
    
    if [ ! -s "/tmp/error_logs.tmp" ]; then
        echo -e "${GREEN}没有找到错误日志${NC}"
        press_enter_to_continue
        return
    fi
    
    echo -e "找到 $(wc -l < /tmp/error_logs.tmp) 条错误日志:"
    echo -e "${BLUE}--------------------------------------------------${NC}"
    cat /tmp/error_logs.tmp | tail -n 20
    
    echo -e "\n${YELLOW}操作选项:${NC}"
    echo "1. 查看完整错误日志"
    echo "2. 分析常见错误"
    echo "3. 返回"
    
    while true; do
        read -p "请选择操作 (1-3): " choice
        
        case $choice in
            1)
                less /tmp/error_logs.tmp
                ;;
            2)
                analyze_common_errors
                ;;
            3)
                rm -f /tmp/error_logs.tmp
                return
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                ;;
        esac
    done
}

# ====== 分析常见错误 ======
analyze_common_errors() {
    clear
    echo -e "${YELLOW}===== 错误分析 =====${NC}"
    
    # 分析常见的错误类型
    echo -e "${BLUE}常见错误统计:${NC}"
    grep -a "ERROR" "$LOG_FILE" | awk -F']' '{print $NF}' | sort | uniq -c | sort -nr
    
    echo -e "\n${BLUE}解决方案建议:${NC}"
    echo -e "1. 认证失败: 检查令牌是否过期，重新生成令牌"
    echo -e "2. 网络连接问题: 检查网络连接，尝试使用代理"
    echo -e "3. API限制: 等待速率限制重置，减少请求频率"
    echo -e "4. 仓库不存在: 检查仓库名称是否正确，确认有访问权限"
    
    press_enter_to_continue
}

# ====== 清理日志 ======
clear_logs() {
    echo -e "${YELLOW}===== 清理日志 =====${NC}"
    
    # 计算当前日志大小
    log_size=$(du -sh "$LOG_DIR" | awk '{print $1}')
    echo -e "当前日志大小: ${CYAN}$log_size${NC}"
    
    read -p "确定要清理日志吗? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # 保留最近7天的日志
        find "$LOG_DIR" -type f -mtime +7 -exec rm -f {} \;
        
        # 清理当前日志文件
        > "$LOG_FILE"
        > "$AUDIT_LOG_FILE"
        
        echo -e "${GREEN}日志已清理${NC}"
        log "SYSTEM" "日志文件已清理"
    else
        echo -e "${YELLOW}取消日志清理${NC}"
    fi
    
    press_enter_to_continue
}


# ====== 更新检测功能 ======
check_for_updates() {
    echo -e "${BLUE}🔍 正在检查更新...${NC}"
    
    # 获取最新版本信息
    latest_version=$(curl -s "https://api.github.com/repos/$GITHUB_USER/$TOOL_REPO/releases/latest" | jq -r '.tag_name')
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        echo -e "${RED}❌ 无法获取最新版本信息${NC}"
        press_enter_to_continue
        return
    fi
    
    # 去除版本号中的v前缀（如果存在）
    latest_version=${latest_version#v}
    
    if [ "$VERSION" == "$latest_version" ]; then
        echo -e "${GREEN}✅ 当前已是最新版本 (v$VERSION)${NC}"
    else
        echo -e "${YELLOW}🔄 发现新版本: v$latest_version${NC}"
        read -p "是否更新? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            update_toolkit "$latest_version"
        fi
    fi
    press_enter_to_continue
}

# ====== 更新工具箱 ======
update_toolkit() {
    local new_version=$1
    echo -e "${BLUE}🔄 正在更新工具箱到 v$new_version...${NC}"
    
    # 备份当前版本
    backup_dir="/tmp/github_toolkit_backup_$(date +%Y%m%d%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r "$GIT_TOOLKIT_ROOT" "$backup_dir" || {
        echo -e "${RED}❌ 备份当前版本失败${NC}"
        return 1
    }
    
    # 下载最新版本
    download_url="https://github.com/$GITHUB_USER/$TOOL_REPO/archive/refs/tags/v$new_version.tar.gz"
    temp_file=$(mktemp)
    
    echo -e "${BLUE}⬇️ 下载新版本...${NC}"
    curl -sL -o "$temp_file" "$download_url" || {
        echo -e "${RED}❌ 下载更新失败${NC}"
        press_enter_to_continue
        return 1
    }
    
    # 解压到临时目录
    echo -e "${BLUE}📦 解压文件...${NC}"
    temp_dir=$(mktemp -d)
    tar -xzf "$temp_file" -C "$temp_dir" --strip-components=1 || {
        echo -e "${RED}❌ 解压更新文件失败${NC}"
        rm -f "$temp_file"
        press_enter_to_continue
        return 1
    }
    
    # 保留用户配置文件
    protected_files=(
        "$CONFIG_FILE"
        "$REPO_CONFIG_FILE"
        "$PLATFORM_CONFIG_FILE"
        "$LOG_DIR"
    )
    
    # 生成更新日志（在文件替换前）
    changelog_file=$(generate_changelog "$VERSION" "$new_version" "$temp_dir")
    
    # 更新文件（排除配置文件）
    echo -e "${BLUE}🔄 更新文件...${NC}"
    rsync -a --delete \
        --exclude="$(basename "$CONFIG_FILE")" \
        --exclude="$(basename "$REPO_CONFIG_FILE")" \
        --exclude="$(basename "$PLATFORM_CONFIG_FILE")" \
        --exclude="$(basename "$LOG_DIR")" \
        "$temp_dir/" "$GIT_TOOLKIT_ROOT/" || {
        echo -e "${RED}❌ 文件更新失败${NC}"
        press_enter_to_continue
        return 1
    }
    
    # 确保日志目录存在
    mkdir -p "$LOG_DIR"
    
    # 移动更新日志到安全位置
    mv "$changelog_file" "$LOG_DIR/"
    changelog_file="$LOG_DIR/$(basename "$changelog_file")"
    
    # 清理临时文件
    rm -f "$temp_file"
    rm -rf "$temp_dir"
    
    # 更新版本号
    VERSION="$new_version"
    
    echo -e "${GREEN}✅ 更新完成! 请重新运行工具箱${NC}"
    echo -e "${YELLOW}📝 更新日志摘要:${NC}"
    echo "--------------------------------"
    grep -v "^#" "$changelog_file" | head -n 15
    echo "--------------------------------"
    echo -e "完整日志请查看: ${CYAN}$changelog_file${NC}"
    
    # 记录更新日志
    log "UPDATE" "工具箱已更新到 v$new_version"
    log "UPDATE" "更新日志: $changelog_file"
    
    exit 0
}

# ====== 生成更新日志 ======
generate_changelog() {
    local old_version=$1
    local new_version=$2
    local new_dir=$3
    local temp_dir=$(mktemp -d)
    local changelog_file="$temp_dir/changelog_${old_version}_to_${new_version}.md"
    
    echo -e "# 更新日志 (v$old_version → v$new_version)\n" > "$changelog_file"
    echo -e "## 新增功能\n" >> "$changelog_file"
    
    # 提取新增功能描述块
    for file in "$new_dir"/*.sh; do
        # 检测功能描述块 (格式: # ===== 功能名称 =====)
        awk '
            /^# =+ [^=]+ =+$/ {
                if (in_block) {
                    print ""
                }
                in_block = 1
                gsub(/^# =+ | =+$/, "", $0)
                print "### " $0
                next
            }
            in_block && /^# / {
                sub(/^# ?/, "")
                print "- " $0
            }
            !/^#/ && in_block {
                in_block = 0
            }
        ' "$file" >> "$changelog_file"
    done
    
    # 添加变更统计
    echo -e "\n## 变更统计\n" >> "$changelog_file"
    for file in "$GIT_TOOLKIT_ROOT"/*.sh; do
        local filename=$(basename "$file")
        local old_file="$temp_dir/old_$filename"
        local new_file="$temp_dir/new_$filename"
        
        # 提取旧版本内容
        sed -n "/^# \[file name\]: $filename/,/^# \[file content end\]/p" "$0" | 
            sed -e '1d' -e '$d' > "$old_file"
        
        # 复制新版本内容
        cp "$new_dir/$filename" "$new_file" 2>/dev/null || continue
        
        # 比较差异
        added=$(diff -u "$old_file" "$new_file" | grep -c '^+[^+#]')
        removed=$(diff -u "$old_file" "$new_file" | grep -c '^-[^-]')
        
        echo "- $filename: 新增 $added 行, 删除 $removed 行" >> "$changelog_file"
    done
    
    # 添加系统信息
    echo -e "\n## 系统更新\n" >> "$changelog_file"
    echo "- 更新日期: $(date +"%Y-%m-%d %H:%M:%S")" >> "$changelog_file"
    echo "- 更新工具: $TOOL_REPO" >> "$changelog_file"
    echo "- 旧版本: v$old_version" >> "$changelog_file"
    echo "- 新版本: v$new_version" >> "$changelog_file"
    
    echo "$changelog_file"
}
EOL

    echo -e "${GREEN}✓ 系统功能模块创建完成${NC}"
}


# 创建跨平台功能模块
create_platforms_module() {
cat > "$INSTALL_DIR/modules/platforms.sh" << 'EOL'
#!/bin/bash

# 跨平台功能模块
source "$GIT_TOOLKIT_ROOT/common.sh"

# 支持的平台列表
SUPPORTED_PLATFORMS=("github" "gitee" "gitlab")

# 加载平台配置
load_platform_config() {
    if [ -f "$PLATFORM_CONFIG_FILE" ]; then
        source "$PLATFORM_CONFIG_FILE"
    else
        # 默认配置
        PLATFORMS=(
            "github|$GITHUB_USER|$GITHUB_TOKEN|true"
            "gitee|||false"
            "gitlab|||false"
        )
    fi
    save_platform_config
}

# 保存平台配置
save_platform_config() {
    declare -p PLATFORMS > "$PLATFORM_CONFIG_FILE"
}

# 平台API创建仓库适配器
platform_create_repo() {
    local platform=$1 name=$2 description=$3 private=$4 token=$5
    local response=""
    
    case $platform in
        github)
            response=$(curl -s -X POST \
                -H "Authorization: token $token" \
                -H "Accept: application/vnd.github.v3+json" \
                -d "{
                    \"name\": \"$name\",
                    \"description\": \"$description\",
                    \"private\": $private
                }" "https://api.github.com/user/repos")
            ;;
        gitee)
            local private_int=$([ "$private" = "true" ] && echo 1 || echo 0)
            response=$(curl -s -X POST \
                -H "Content-Type: application/json" \
                -d "{
                    \"name\": \"$name\",
                    \"description\": \"$description\",
                    \"private\": $private_int,
                    \"access_token\": \"$token\"
                }" "https://gitee.com/api/v5/user/repos")
            ;;
        gitlab)
            local visibility=$([ "$private" = "true" ] && echo "private" || echo "public")
            response=$(curl -s -X POST \
                -H "PRIVATE-TOKEN: $token" \
                -H "Content-Type: application/json" \
                -d "{
                    \"name\": \"$name\",
                    \"description\": \"$description\",
                    \"visibility\": \"$visibility\"
                }" "https://gitlab.com/api/v4/projects")
            ;;
    esac
    echo "$response"
}

# 统一跨平台同步函数
cross_platform_sync() {
    load_platform_config
    
    # 显示平台选择菜单
    echo -e "${YELLOW}===== 跨平台同步 =====${NC}"
    echo "支持的平台:"
    for i in "${!SUPPORTED_PLATFORMS[@]}"; do
        echo "$(($i+1)). ${SUPPORTED_PLATFORMS[$i]}"
    done
    
    read -p "选择源平台序号: " src_platform_index
    read -p "选择目标平台序号: " dst_platform_index
    
    # 验证平台选择
    if [[ ! "$src_platform_index" =~ ^[0-9]+$ ]] || 
       [[ ! "$dst_platform_index" =~ ^[0-9]+$ ]] ||
       [ "$src_platform_index" -lt 1 ] || 
       [ "$src_platform_index" -gt "${#SUPPORTED_PLATFORMS[@]}" ] ||
       [ "$dst_platform_index" -lt 1 ] || 
       [ "$dst_platform_index" -gt "${#SUPPORTED_PLATFORMS[@]}" ]; then
        echo -e "${RED}❌ 无效的平台选择${NC}"
        press_enter_to_continue
        return
    fi
    
    local src_platform="${SUPPORTED_PLATFORMS[$((src_platform_index-1))]}"
    local dst_platform="${SUPPORTED_PLATFORMS[$((dst_platform_index-1))]}"
    
    # 获取源仓库信息
    read -p "输入源仓库 (格式: 用户名/仓库名): " src_repo
    if [[ ! "$src_repo" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}❌ 无效的仓库格式，请使用 '用户名/仓库名' 格式${NC}"
        press_enter_to_continue
        return
    fi
    
    # 获取目标仓库信息
    IFS='/' read -r src_user src_repo_name <<< "$src_repo"
    read -p "输入目标仓库用户名 [默认: $src_user]: " dst_user
    dst_user=${dst_user:-$src_user}
    read -p "输入目标仓库名称 [默认: $src_repo_name]: " dst_repo_name
    dst_repo_name=${dst_repo_name:-$src_repo_name}
    
    # 获取平台令牌
    local src_token=""
    local dst_token=""
    
    for platform_info in "${PLATFORMS[@]}"; do
        IFS='|' read -r platform username token enabled <<< "$platform_info"
        if [ "$platform" == "$src_platform" ] && [ "$enabled" == "true" ]; then
            src_token="$token"
        fi
        if [ "$platform" == "$dst_platform" ] && [ "$enabled" == "true" ]; then
            dst_token="$token"
        fi
    done
    
    if [ -z "$src_token" ]; then
        echo -e "${RED}❌ 未配置 $src_platform 访问令牌${NC}"
        press_enter_to_continue
        return
    fi
    
    if [ -z "$dst_token" ]; then
        echo -e "${RED}❌ 未配置 $dst_platform 访问令牌${NC}"
        press_enter_to_continue
        return
    fi
    
    # 获取源仓库信息
    echo -e "${BLUE}📡 获取 $src_platform 仓库信息...${NC}"
    local repo_info=""
    case $src_platform in
        github)
            repo_info=$(curl -s -H "Authorization: token $src_token" \
                "https://api.github.com/repos/$src_repo")
            ;;
        gitee)
            repo_info=$(curl -s "https://gitee.com/api/v5/repos/$src_repo?access_token=$src_token")
            ;;
        gitlab)
            repo_info=$(curl -s -H "PRIVATE-TOKEN: $src_token" \
                "https://gitlab.com/api/v4/projects/$(echo "$src_repo" | sed 's/\//%2F/g')")
            ;;
    esac
    
    # 解析仓库信息
    local error_msg=$(echo "$repo_info" | jq -r '.message // .error // empty')
    if [ -n "$error_msg" ]; then
        echo -e "${RED}❌ 获取仓库信息失败: $error_msg${NC}"
        press_enter_to_continue
        return
    fi
    
    local description=$(echo "$repo_info" | jq -r '.description // ""')
    local private=$(echo "$repo_info" | jq -r '.private // false')
    
    # 创建目标仓库
    echo -e "${BLUE}🚀 在 $dst_platform 创建仓库...${NC}"
    local create_response=$(platform_create_repo "$dst_platform" "$dst_repo_name" "$description" "$private" "$dst_token")
    
    # 处理创建响应
    error_msg=$(echo "$create_response" | jq -r '.message // .error // empty')
    if [ -n "$error_msg" ]; then
        if [[ "$error_msg" == *"已经存在"* ]]; then
            echo -e "${YELLOW}ℹ️ 仓库已存在，继续同步${NC}"
        else
            echo -e "${RED}❌ 创建仓库失败: $error_msg${NC}"
            press_enter_to_continue
            return
        fi
    fi
    
    # 获取目标仓库URL
    local dst_repo_url=""
    case $dst_platform in
        github)
            dst_repo_url="https://github.com/$dst_user/$dst_repo_name.git"
            ;;
        gitee)
            dst_repo_url="https://gitee.com/$dst_user/$dst_repo_name.git"
            ;;
        gitlab)
            dst_repo_url="https://gitlab.com/$dst_user/$dst_repo_name.git"
            ;;
    esac
    
    # 创建临时目录
    local temp_dir=$(mktemp -d)
    cd "$temp_dir" || return
    
    # 克隆源仓库
    echo -e "${BLUE}⬇️ 克隆源仓库...${NC}"
    case $src_platform in
        github)
            git clone --mirror "https://github.com/$src_repo.git" . || {
                echo -e "${RED}❌ 克隆源仓库失败${NC}"
                cd ..
                rm -rf "$temp_dir"
                press_enter_to_continue
                return
            }
            ;;
        gitee)
            git clone --mirror "https://gitee.com/$src_repo.git" . || {
                echo -e "${RED}❌ 克隆源仓库失败${NC}"
                cd ..
                rm -rf "$temp_dir"
                press_enter_to_continue
                return
            }
            ;;
        gitlab)
            git clone --mirror "https://gitlab.com/$src_repo.git" . || {
                echo -e "${RED}❌ 克隆源仓库失败${NC}"
                cd ..
                rm -rf "$temp_dir"
                press_enter_to_continue
                return
            }
            ;;
    esac
    
    # 添加认证信息
    local auth_dst_url=""
    case $dst_platform in
        github)
            auth_dst_url="https://$dst_user:$dst_token@github.com/$dst_user/$dst_repo_name.git"
            ;;
        gitee)
            auth_dst_url="https://$dst_user:$dst_token@gitee.com/$dst_user/$dst_repo_name.git"
            ;;
        gitlab)
            auth_dst_url="https://$dst_user:$dst_token@gitlab.com/$dst_user/$dst_repo_name.git"
            ;;
    esac
    
    # 推送到目标仓库
    echo -e "${BLUE}🔄 同步到 $dst_platform...${NC}"
    git push --mirror "$auth_dst_url" || {
        echo -e "${RED}❌ 同步失败${NC}"
        cd ..
        rm -rf "$temp_dir"
        press_enter_to_continue
        return
    }
    
    # 清理
    cd ..
    rm -rf "$temp_dir"
    
    echo -e "${GREEN}✅ 同步完成: $src_platform → $dst_platform${NC}"
    echo -e "目标仓库URL: ${CYAN}$dst_repo_url${NC}"
    
    audit_log "CROSS_PLATFORM_SYNC" "$src_platform:$src_repo → $dst_platform:$dst_user/$dst_repo_name"
    press_enter_to_continue
}


# 多平台镜像配置
setup_multi_platform_sync() {
    load_platform_config
    
    while true; do
        clear
        echo -e "${YELLOW}===== 多平台镜像配置 ====="
        echo "序号 | 平台    | 用户名      | 状态  "
        echo "--------------------------------"
        for i in "${!PLATFORMS[@]}"; do
            IFS='|' read -r platform username token enabled <<< "${PLATFORMS[$i]}"
            status=$([ "$enabled" = "true" ] && echo -e "${GREEN}启用${NC}" || echo -e "${RED}禁用${NC}")
            printf "%-2s   | %-8s | %-10s | %b\n" "$((i+1))" "$platform" "$username" "$status"
        done
        echo -e "${YELLOW}============================${NC}"
        echo "1. 添加/编辑平台"
        echo "2. 启用/禁用平台"
        echo "3. 配置自动镜像同步"
        echo "4. 设置Gitee仓库可见性"
        echo -e "${YELLOW}5. 返回${NC}"
        echo "--------------------------------"
        
        read -p "选择操作: " choice
        
        case $choice in
            1)
                # 添加/编辑平台
                read -p "输入平台序号 (新平台输入0): " index
                if [ "$index" -eq 0 ]; then
                    read -p "输入平台名称 (github/gitee): " new_platform
                    if [[ ! "$new_platform" =~ ^(github|gitee)$ ]]; then
                        echo -e "${RED}❌ 只支持 github 和 gitee 平台${NC}"
                        press_enter_to_continue
                        continue
                    fi
                    
                    read -p "输入用户名: " new_user
                    read -s -p "输入访问令牌: " new_token
                    echo
                    
                    PLATFORMS+=("$new_platform|$new_user|$new_token|true")
                    echo -e "${GREEN}✅ 已添加 $new_platform 平台${NC}"
                else
                    if [ "$index" -gt "${#PLATFORMS[@]}" ]; then
                        echo -e "${RED}❌ 无效序号${NC}"
                        press_enter_to_continue
                        continue
                    fi
                    
                    idx=$((index-1))
                    IFS='|' read -r platform username token enabled <<< "${PLATFORMS[$idx]}"
                    
                    read -p "输入新用户名 [$username]: " new_user
                    new_user=${new_user:-$username}
                    
                    read -s -p "输入新令牌 (留空保持原令牌): " new_token
                    echo
                    new_token=${new_token:-$token}
                    
                    PLATFORMS[$idx]="$platform|$new_user|$new_token|$enabled"
                    echo -e "${GREEN}✅ 已更新 $platform 配置${NC}"
                fi
                save_platform_config
                press_enter_to_continue
                ;;
            2)
                # 启用/禁用平台
                read -p "输入平台序号: " index
                if [ "$index" -lt 1 ] || [ "$index" -gt "${#PLATFORMS[@]}" ]; then
                    echo -e "${RED}❌ 无效序号${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                idx=$((index-1))
                IFS='|' read -r platform username token enabled <<< "${PLATFORMS[$idx]}"
                
                new_status=$([ "$enabled" = "true" ] && echo "false" || echo "true")
                status_text=$([ "$new_status" = "true" ] && echo "启用" || echo "禁用")
                
                PLATFORMS[$idx]="$platform|$username|$token|$new_status"
                save_platform_config
                
                echo -e "${GREEN}✅ 已$status_text $platform 平台${NC}"
                press_enter_to_continue
                ;;
            3)
                # 配置自动镜像同步
                echo -e "${BLUE}🔄 配置自动镜像同步${NC}"
                
                # 显示已配置平台
                enabled_platforms=()
                for i in "${!PLATFORMS[@]}"; do
                    IFS='|' read -r platform username token enabled <<< "${PLATFORMS[$i]}"
                    if [ "$enabled" = "true" ]; then
                        enabled_platforms+=("$platform")
                    fi
                done
                
                if [ ${#enabled_platforms[@]} -lt 2 ]; then
                    echo -e "${RED}❌ 需要至少启用两个平台${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                echo -e "${YELLOW}已启用平台:${NC}"
                for i in "${!enabled_platforms[@]}"; do
                    echo "$((i+1)). ${enabled_platforms[$i]}"
                done
                
                # 选择源平台和目标平台
                read -p "选择源平台序号: " src_index
                read -p "选择目标平台序号: " dst_index
                
                if [ "$src_index" -lt 1 ] || [ "$src_index" -gt "${#enabled_platforms[@]}" ] ||
                   [ "$dst_index" -lt 1 ] || [ "$dst_index" -gt "${#enabled_platforms[@]}" ]; then
                    echo -e "${RED}❌ 无效选择${NC}"
                    press_enter_to_continue
                    continue
                fi
                
                src_platform=${enabled_platforms[$((src_index-1))]}
                dst_platform=${enabled_platforms[$((dst_index-1))]}
                
                # 配置自动同步
                AUTO_SYNC_SOURCE="$src_platform"
                AUTO_SYNC_TARGET="$dst_platform"
                save_config
                
                echo -e "${GREEN}✅ 已配置自动镜像同步: $src_platform → $dst_platform${NC}"
                audit_log "SETUP_AUTO_SYNC" "$src_platform → $dst_platform"
                press_enter_to_continue
                ;;
            4)
                # 设置Gitee仓库可见性
                echo -e "${YELLOW}===== Gitee仓库可见性设置 ====="
                echo "1. 设置为公开仓库"
                echo "2. 设置为私有仓库"
                echo "3. 返回"
                echo "--------------------------------"
                read -p "请选择操作: " visibility_choice
                
                case $visibility_choice in
                    1)
                        # 设置为公开仓库
                        for i in "${!PLATFORMS[@]}"; do
                            IFS='|' read -r platform username token enabled <<< "${PLATFORMS[$i]}"
                            if [ "$platform" == "gitee" ]; then
                                # 获取Gitee令牌
                                if [ -z "$token" ]; then
                                    echo -e "${RED}❌ 未配置Gitee令牌${NC}"
                                    press_enter_to_continue
                                    return
                                fi
                                
                                # 设置所有仓库为公开
                                echo -e "${BLUE}🔄 正在设置所有Gitee仓库为公开...${NC}"
                                gitee_repos=$(curl -s -X GET "https://gitee.com/api/v5/users/$username/repos?access_token=$token&per_page=100" | jq -c '.[]')
                                
                                if [ -z "$gitee_repos" ]; then
                                    echo -e "${YELLOW}⚠️ 未找到任何Gitee仓库${NC}"
                                    press_enter_to_continue
                                    return
                                fi
                                
                                # 处理每个仓库
                                while IFS= read -r repo; do
                                    repo_name=$(echo "$repo" | jq -r '.name')
                                    repo_id=$(echo "$repo" | jq -r '.id')
                                    
                                    # 更新仓库为公开
                                    response=$(curl -s -X PATCH \
                                        -H "Content-Type: application/json" \
                                        -d "{\"private\": false, \"access_token\": \"$token\"}" \
                                        "https://gitee.com/api/v5/repos/$username/$repo_name")
                                    
                                    error_msg=$(echo "$response" | jq -r '.message')
                                    if [ -n "$error_msg" ] && [ "$error_msg" != "null" ]; then
                                        echo -e "${RED}❌ 更新仓库 $repo_name 失败: $error_msg${NC}"
                                    else
                                        echo -e "${GREEN}✅ 已设置仓库 $repo_name 为公开${NC}"
                                        audit_log "SET_GITEE_VISIBILITY" "设置 $repo_name 为公开"
                                    fi
                                done <<< "$gitee_repos"
                                
                                echo -e "${GREEN}✅ 所有Gitee仓库已设置为公开${NC}"
                                break
                            fi
                        done
                        press_enter_to_continue
                        ;;
                    2)
                        # 设置为私有仓库
                        for i in "${!PLATFORMS[@]}"; do
                            IFS='|' read -r platform username token enabled <<< "${PLATFORMS[$i]}"
                            if [ "$platform" == "gitee" ]; then
                                # 获取Gitee令牌
                                if [ -z "$token" ]; then
                                    echo -e "${RED}❌ 未配置Gitee令牌${NC}"
                                    press_enter_to_continue
                                    return
                                fi
                                
                                # 设置所有仓库为私有
                                echo -e "${BLUE}🔄 正在设置所有Gitee仓库为私有...${NC}"
                                gitee_repos=$(curl -s -X GET "https://gitee.com/api/v5/users/$username/repos?access_token=$token&per_page=100" | jq -c '.[]')
                                
                                if [ -z "$gitee_repos" ]; then
                                    echo -e "${YELLOW}⚠️ 未找到任何Gitee仓库${NC}"
                                    press_enter_to_continue
                                    return
                                fi
                                
                                # 处理每个仓库
                                while IFS= read -r repo; do
                                    repo_name=$(echo "$repo" | jq -r '.name')
                                    repo_id=$(echo "$repo" | jq -r '.id')
                                    
                                    # 更新仓库为私有
                                    response=$(curl -s -X PATCH \
                                        -H "Content-Type: application/json" \
                                        -d "{\"private\": true, \"access_token\": \"$token\"}" \
                                        "https://gitee.com/api/v5/repos/$username/$repo_name")
                                    
                                    error_msg=$(echo "$response" | jq -r '.message')
                                    if [ -n "$error_msg" ] && [ "$error_msg" != "null" ]; then
                                        echo -e "${RED}❌ 更新仓库 $repo_name 失败: $error_msg${NC}"
                                    else
                                        echo -e "${GREEN}✅ 已设置仓库 $repo_name 为私有${NC}"
                                        audit_log "SET_GITEE_VISIBILITY" "设置 $repo_name 为私有"
                                    fi
                                done <<< "$gitee_repos"
                                
                                echo -e "${GREEN}✅ 所有Gitee仓库已设置为私有${NC}"
                                break
                            fi
                        done
                        press_enter_to_continue
                        ;;
                    3)
                        # 返回
                        ;;
                    *)
                        echo -e "${RED}❌ 无效选择${NC}"
                        sleep 1
                        ;;
                esac
                ;;
            5)
                return
                ;;
            *)
                echo -e "${RED}❌ 无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}
EOL

    echo -e "${GREEN}✓ 跨平台功能模块创建完成${NC}"
}



# 创建启动器
create_launcher() {
    # 移除可能存在的冲突目录
    if [ -d "/usr/local/bin/github-toolkit" ]; then
        echo -e "${YELLOW}⚠️ 移除冲突目录: /usr/local/bin/github-toolkit${NC}"
        rm -rf "/usr/local/bin/github-toolkit"
    fi
    
    # 创建启动器脚本
    cat > "/usr/local/bin/github-toolkit" << EOF
#!/bin/bash
${INSTALL_DIR}/main.sh "\$@"
EOF

    chmod +x "/usr/local/bin/github-toolkit"
    echo -e "${GREEN}✓ 脚本启动器创建完成${NC}"
}

# 完成安装
finish_installation() {
    echo -e "${GREEN}\n================================================"
    echo " 遥辉GitHub同步管理工具安装完成!"
    echo "================================================${NC}"
    echo -e "${YELLOW}安装目录:${NC} $INSTALL_DIR"
    echo -e "${YELLOW}配置文件:${NC} ~/.github_toolkit_config"
    echo -e "${YELLOW}仓库配置:${NC} ~/.github_repo_config"
    echo -e "${YELLOW}日志目录:${NC} /log/github_toolkit"
    echo -e "\n${CYAN}启动命令:${NC}"
    echo -e "  $ github-toolkit\n"
    echo -e "${YELLOW}首次启动将进行初始配置...${NC}"
}

# 主安装函数
main() {
    clear
    echo -e "${BLUE}"
    echo "   ____ _ _   _   _       _          _   "
    echo "  / ___(_) |_| | | |_   _| |__   ___| |_ "
    echo " | |  _| | __| |_| | | | | '_ \ / _ \ __|"
    echo " | |_| | | |_|  _  | |_| | |_) |  __/ |_ "
    echo "  \____|_|\__|_| |_|\__,_|_.__/ \___|\__|"
    echo -e "${NC}"
    echo -e "${YELLOW}        遥辉GitHub同步管理工具安装程序 v3.2.0${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    check_root
    install_dependencies
    create_directory_structure
    create_main_script
    create_config_script
    create_core_module
    create_warehouse_module
    create_senior_module
    create_system_module
    create_platforms_module
    create_launcher
    
    finish_installation
}

# 启动主安装函数
main