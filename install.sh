#!/bin/bash

# GitHub工具箱模块化安装脚本
# 版本: 3.0.0
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
VERSION="3.0"
LAST_UPDATE="2025-08-04"
TOOL_REPO="GithubToolKit"  # 工具箱的仓库名称

# 确保脚本使用bash执行
if [ -z "$BASH_VERSION" ]; then
    echo -e "${RED}错误: 请使用bash执行此脚本${NC}"
    exit 1
fi

# 加载配置和模块
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GIT_TOOLKIT_ROOT="$SCRIPT_DIR"

source "$GIT_TOOLKIT_ROOT/config.sh" # 全局配置文件
source "$GIT_TOOLKIT_ROOT/modules/core.sh" # 核心功能模块
source "$GIT_TOOLKIT_ROOT/modules/warehouse.sh" # 仓库管理模块
source "$GIT_TOOLKIT_ROOT/modules/senior.sh" # 高级功能模块
source "$GIT_TOOLKIT_ROOT/modules/system.sh" # 系统功能模块
source "$GIT_TOOLKIT_ROOT/modules/platforms.sh" # 跨平台同步Gitee


# ====== 主程序 ======
main() {
    # 确保日志文件存在
    touch "$LOG_FILE" "$AUDIT_LOG_FILE"
    chmod 600 "$LOG_FILE" "$AUDIT_LOG_FILE"
    
    # 运行首次配置向导
    if first_run_wizard; then
        # 首次运行后加载配置
        load_config
    else
        # 加载现有配置
        load_config || {
            echo -e "${RED}❌ 无法加载配置文件${NC}"
            exit 1
        }
    fi
    
    check_dependencies
    
    # 显示欢迎信息
    echo -e "${YELLOW}🔑 使用GitHub账号: $GITHUB_USER${NC}"
    if [ -n "$CURRENT_REPO" ]; then
        echo -e "${CYAN}📦 当前仓库: $CURRENT_REPO${NC}"
    fi
    
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
        echo -e "${BLUE}======== 核心功能 ========${NC}"
        echo -e "${GREEN}1. 创建并同步新仓库${NC}"
        echo -e "${GREEN}2. 推送新的更改${NC}"
        echo -e "${GREEN}3. 拉取远程更改${NC}"
        echo -e "${GREEN}4. 更新仓库描述${NC}"
        echo -e "${GREEN}5. 删除项目仓库${NC}"
        
        echo -e "${BLUE}======== 仓库管理 ========${NC}"
        echo -e "${CYAN}6. 综合仓库功能${NC}"
        echo -e "${CYAN}7. 多个仓库管理${NC}"
        echo -e "${CYAN}8. 查看仓库统计${NC}"
        
        echo -e "${BLUE}======== 高级功能 ========${NC}"
        echo -e "${PURPLE}9. 我的组织管理${NC}"
        echo -e "${PURPLE}10. 项目分支管理${NC}"
        echo -e "${PURPLE}11. 代码片段管理${NC}"
        echo -e "${PURPLE}12. 自动同步设置${NC}"
        
        echo -e "${BLUE}======== 跨平台功能 ========${NC}"
        echo -e "${YELLOW}13. GitHub → Gitee 自动同步${NC}"  # 修改此项
        echo -e "${YELLOW}14. 跨平台同步到现有Gitee仓库${NC}"
        echo -e "${YELLOW}15. 多平台镜像配置${NC}"
        
        echo -e "${BLUE}======== 系统功能 ========${NC}"
        echo -e "${YELLOW}16. 检查版本更新${NC}"
        echo -e "${YELLOW}17. 系统状态信息${NC}"
        echo -e "${RED}18. 退出${NC}"
        echo -e "${BLUE}==================================================${NC}"
        
        read -p "请选择操作 (1-18): " choice
        
        case $choice in
            1) create_and_sync_repo ;;
            2) push_changes ;;
            3) pull_changes ;;
            4) update_repo_description ;;
            5) delete_github_repo ;;
            6) repo_management_menu ;;
            7) multi_repo_management_menu ;;
            8) show_repo_stats ;;
            9) manage_organizations ;;
            10) manage_branches ;;
            11) manage_gists ;;
            12) setup_auto_sync ;;
            13) github_to_gitee_sync ;;
            14) cross_platform_sync ;;
            15) setup_multi_platform_sync ;;
            16) check_for_updates ;;
            17) show_system_info ;;
            18) 
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
    cat > "$INSTALL_DIR/config.sh" << 'EOL'
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
LOG_FILE="$HOME/log/github_toolkit/toolkit.log"

# 审计日志文件路径（记录重要操作如创建/删除仓库）
AUDIT_LOG_FILE="$HOME/log/github_toolkit/audit.log"

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



# 等待用户按回车键继续
press_enter_to_continue() {
    echo -e "${BLUE}--------------------------------${NC}"
    read -p "按回车键返回菜单..." enter_key
}
EOL
    echo -e "${GREEN}✓ 全局配置文件创建完成${NC}"
}

# 创建核心功能模块
create_core_module() {
cat > "$INSTALL_DIR/modules/core.sh" << 'EOL'
#!/bin/bash

# 核心功能模块

# 加载配置和工具
source "$GIT_TOOLKIT_ROOT/config.sh"

# ====== 依赖检查 ======
check_dependencies() {
    local missing=0
    command -v git &>/dev/null || { echo -e "${RED}错误: Git未安装${NC}"; missing=1; }
    command -v curl &>/dev/null || { echo -e "${RED}错误: curl未安装${NC}"; missing=1; }
    command -v jq &>/dev/null || { echo -e "${RED}错误: jq未安装${NC}"; missing=1; }
    [ $missing -eq 1 ] && exit 1
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

# ====== 获取仓库列表 ======
get_repo_list() {
    # 检查缓存是否有效
    if [ -f "$REPO_CACHE_FILE" ] && [ $(($(date +%s) - $(stat -c %Y "$REPO_CACHE_FILE"))) -lt $REPO_CACHE_TIMEOUT ]; then
        cat "$REPO_CACHE_FILE"
        return 0
    fi
    
    echo -e "${BLUE}📡 获取仓库列表...${NC}"
    repos_json=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/user/repos?per_page=100")
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 获取仓库列表失败${NC}"
        return 1
    fi
    
    # 保存到缓存
    echo "$repos_json" > "$REPO_CACHE_FILE"
    echo "$repos_json"
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

# ====== 推送新更改 ======
push_changes() {
    # 检查当前目录是否是Git仓库
    if [ ! -d ".git" ]; then
        echo -e "${RED}❌ 当前目录不是Git仓库${NC}"
        return 1
    fi
    
    # 检查是否有远程仓库
    if ! git remote | grep -q origin; then
        echo -e "${RED}❌ 没有配置远程仓库，请先创建并同步新仓库${NC}"
        return 1
    fi
    
    if check_git_status; then
        read -p "📝 输入提交信息: " commit_message
        if [ -z "$commit_message" ]; then
            echo -e "${RED}❌ 提交信息不能为空${NC}"
            return 1
        fi
        
        run_command "git add ." || return 1
        run_command "git commit -m \"$commit_message\"" || return 1
        
        # 获取当前远程URL并添加认证信息
        current_url=$(git config --get remote.origin.url)
        repo_path=${current_url#https://}
        AUTH_REPO_URL="https://$GITHUB_USER:$GITHUB_TOKEN@$repo_path"
        run_command "git remote set-url origin \"$AUTH_REPO_URL\"" || return 1
        
        echo -e "${BLUE}🚀 正在推送更改...${NC}"
        if run_command "git push"; then
            echo -e "${GREEN}✅ 更改已推送${NC}"
            return 0
        else
            echo -e "${RED}❌ 推送失败${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}✅ 没有检测到更改${NC}"
        return 0
    fi
    press_enter_to_continue
}

# ====== 拉取远程更改 ======
pull_changes() {
    # 检查当前目录是否是Git仓库
    if [ ! -d ".git" ]; then
        echo -e "${RED}❌ 当前目录不是Git仓库${NC}"
        return 1
    fi
    
    # 检查是否有远程仓库
    if ! git remote | grep -q origin; then
        echo -e "${RED}❌ 没有配置远程仓库，请先创建并同步新仓库${NC}"
        return 1
    fi
    
    echo -e "${BLUE}🔄 拉取远程更改...${NC}"
    
    # 获取当前远程URL并添加认证信息
    current_url=$(git config --get remote.origin.url)
    repo_path=${current_url#https://}
    AUTH_REPO_URL="https://$GITHUB_USER:$GITHUB_TOKEN@$repo_path"
    run_command "git remote set-url origin \"$AUTH_REPO_URL\"" || return 1
    
    if run_command "git pull"; then
        echo -e "${GREEN}✅ 拉取完成${NC}"
        return 0
    else
        echo -e "${RED}❌ 拉取失败${NC}"
        return 1
    fi
    press_enter_to_continue
}


# ====== URL编码函数 ======
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

# ====== 检查Git状态 ======
check_git_status() {
    if [ -n "$(git status --porcelain)" ]; then
        echo -e "${YELLOW}🔄 检测到未提交的更改:${NC}"
        git status -s
        return 0
    fi
    return 1
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
source "$GIT_TOOLKIT_ROOT/config.sh"

# ====== 搜索仓库功能 ======
search_repos() {
    read -p "🔍 输入搜索关键词: " search_term
    if [ -z "$search_term" ]; then
        echo -e "${RED}❌ 搜索词不能为空${NC}"
        press_enter_to_continue
        return
    fi
    
    echo -e "${BLUE}🔍 正在搜索仓库: $search_term...${NC}"
    encoded_search=$(urlencode "$search_term")
    response=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/search/repositories?q=$encoded_search+user:$GITHUB_USER")
    
    count=$(echo "$response" | jq '.total_count')
    if [ -z "$count" ] || [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}🔍 未找到匹配的仓库${NC}"
        press_enter_to_continue
        return
    fi
    
    echo -e "\n${GREEN}🔍 找到 $count 个匹配的仓库:${NC}"
    echo "--------------------------------"
    echo "$response" | jq -r '.items[] | "\(.name) - \(.description)"'
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
                        audit_log "CREATE_ISSUE" "$repo_name/$issue_title"
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
                        audit_log "CLOSE_ISSUE" "$repo_name/$issue_number"
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
                        audit_log "ADD_COLLABORATOR" "$repo_name/$username"
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
                        audit_log "REMOVE_COLLABORATOR" "$repo_name/$username"
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
                    audit_log "ARCHIVE_REPO" "$repo_name/$action"
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
                    audit_log "DISABLE_REPO" "$repo_name/$action"
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
                    audit_log "TEMPLATE_REPO" "$repo_name/$action"
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
                        audit_log "CHANGE_VISIBILITY" "$repo_name/$new_visibility"
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
                        audit_log "TRANSFER_REPO" "$repo_name -> $new_owner/$new_name"
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
                    audit_log "DELETE_WEBHOOK" "$repo_name/$hook_id"
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
    audit_log "ADD_REPO" "$repo_name"
    
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
    audit_log "REMOVE_REPO" "$repo_name"
    
    # 如果移除的是当前仓库，清空当前仓库设置
    if [ "$CURRENT_REPO" == "$repo_name" ]; then
        CURRENT_REPO=""
        save_config
    fi
}

# ====== 列出所有配置仓库 ======
list_configured_repos() {
    if [ ! -s "$REPO_CONFIG_FILE" ]; then
        echo -e "${YELLOW}ℹ️ 没有配置任何仓库${NC}"
        return
    fi
    
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
    audit_log "SWITCH_REPO" "$CURRENT_REPO"
}

# ===== 仓库管理工具子菜单 ======
repo_management_menu() {
    while true; do
        clear
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${YELLOW}           遥辉GitHub 同步管理工具 - 仓库管理${NC}"
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${PURPLE}1. 搜索本地仓库${NC}"
        echo -e "${PURPLE}2. 项目议题管理${NC}"
        echo -e "${PURPLE}3. 协作人员管理${NC}"
        echo -e "${PURPLE}4. 仓库状态管理${NC}"
        echo -e "${PURPLE}5. 查看Webhook${NC}"
        echo -e "${YELLOW}6. 返回主菜单${NC}"
        echo -e "${BLUE}==================================================${NC}"
        
        read -p "请选择操作 (1-6): " choice
        
        case $choice in
            1) search_repos ;;
            2) manage_issues ;;
            3) manage_collaborators ;;
            4) manage_repo_status ;;
            5) view_webhooks ;;
            6) return ;;
            *)
                echo -e "${RED}❌ 无效选择，请重新输入${NC}"
                sleep 1
                ;;
        esac
    done
}

# ====== 多仓库管理子菜单 ======
multi_repo_management_menu() {
    while true; do
        clear
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${YELLOW}           遥辉GitHub 同步管理工具 - 多仓库管理${NC}"
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${CYAN}1. 列出配置仓库${NC}"
        echo -e "${CYAN}2. 切换当前仓库${NC}"
        echo -e "${YELLOW}3. 返回主菜单${NC}"
        echo -e "${BLUE}==================================================${NC}"
        
        read -p "请选择操作 (1-3): " choice
        
        case $choice in
            1) 
                list_configured_repos
                press_enter_to_continue
                ;;
            2) 
                switch_current_repo
                press_enter_to_continue
                ;;
            3) return ;;
            *)
                echo -e "${RED}❌ 无效选择，请重新输入${NC}"
                sleep 1
                ;;
        esac
    done
}

# ====== 仓库统计功能 ======
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
EOL
    echo -e "${GREEN}✓ 仓库管理模块创建完成${NC}"
}

# 创建高级功能模块
create_senior_module() {
cat > "$INSTALL_DIR/modules/senior.sh" << 'EOL'
#!/bin/bash

# 高级功能模块

# 加载配置和工具
source "$GIT_TOOLKIT_ROOT/config.sh"


# 处理GitHub API响应
handle_github_response() {
    local response="$1"
    local success_message="$2"
    
    if [ $? -ne 0 ]; then
        log "ERROR" "API请求失败"
        echo -e "${RED}❌ 请求失败，请检查网络${NC}"
        return 1
    fi
    
    local error_msg=$(echo "$response" | jq -r '.message')
    if [ "$error_msg" != "null" ]; then
        log "ERROR" "API错误: $error_msg"
        echo -e "${RED}❌ 操作失败: $error_msg${NC}"
        return 1
    fi
    
    log "INFO" "$success_message"
    echo -e "${GREEN}✅ $success_message${NC}"
    return 0
}


# ====== 组织管理功能 ======
manage_organizations() {
    echo -e "${BLUE}🏢 获取组织列表...${NC}"
    orgs=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/user/orgs")
    
    if [ -z "$orgs" ]; then
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
    audit_log "SELECT_ORG" "$selected_org"
    
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
        "https://api.github.com/orgs/$org/repos")
    
    if [ -z "$repos" ]; then
        echo -e "${YELLOW}该组织没有仓库${NC}"
        press_enter_to_continue
        return
    fi
    
    echo -e "\n${GREEN}组织仓库列表:${NC}"
    echo "--------------------------------"
    echo "$repos" | jq -r '.[].name'
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
    
    response=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{
            \"name\": \"$repo_name\",
            \"description\": \"$repo_description\",
            \"private\": $private,
            \"auto_init\": true
        }" "https://api.github.com/orgs/$org/repos")
    
    handle_github_response "$response" "仓库 $repo_name 创建成功"
    audit_log "CREATE_ORG_REPO" "$org/$repo_name"
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
        echo -e "${YELLOW}5. 返回主菜单${NC}"
        echo -e "${BLUE}===================================${NC}"
        
        read -p "选择操作: " choice
        
        case $choice in
            1) list_branches "$user_repo" ;;
            2) create_branch "$user_repo" ;;
            3) delete_branch "$user_repo" ;;
            4) merge_branch "$user_repo" ;;
            5) return ;;
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
    
    echo -e "\n${GREEN}分支列表:${NC}"
    echo "--------------------------------"
    echo "$branches" | jq -r '.[].name'
    echo "--------------------------------"
    press_enter_to_continue
}

# ====== 代码片段管理 ======
manage_gists() {
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
        sudo bash -c "cat > /etc/systemd/system/github-toolkit-sync.timer <<EOF
[Unit]
Description=GitHub Toolkit Auto Sync Timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=${interval}min

[Install]
WantedBy=timers.target
EOF"
        
        sudo bash -c "cat > /etc/systemd/system/github-toolkit-sync.service <<EOF
[Unit]
Description=GitHub Toolkit Sync Service

[Service]
Type=oneshot
ExecStart=$(realpath "$0") --auto-sync
User=$USER
EOF"
        
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
EOL

echo -e "${GREEN}✓ 高级功能模块创建完成${NC}"
}

# 创建系统功能模块
create_system_module() {
cat > "$INSTALL_DIR/modules/system.sh" << 'EOL'
#!/bin/bash

# 系统功能模块

# 加载配置和工具
source "$GIT_TOOLKIT_ROOT/config.sh"
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
        echo -e "${YELLOW}配置多平台支持...${NC}"
        read -p "是否启用Gitee支持? (y/N): " enable_gitee
        if [[ "$enable_gitee" =~ ^[Yy]$ ]]; then
            read -p "输入Gitee用户名: " GITEE_USER
            read -s -p "输入Gitee访问令牌: " GITEE_TOKEN
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

# 日志记录
log() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE" >/dev/null
}

# 审计日志
audit_log() {
    local action=$1
    local target=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [AUDIT] 用户: $USER, 操作: $action, 目标: $target" >> "$AUDIT_LOG_FILE"
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

# ====== 系统信息功能 ======
show_system_info() {
    load_platform_config
    
    echo -e "${YELLOW}===== 系统信息 =====${NC}"
    echo -e "工具箱版本: ${CYAN}v$VERSION${NC}"
    echo -e "系统: ${CYAN}$(lsb_release -ds 2>/dev/null || uname -a)${NC}"
    echo -e "内存: ${CYAN}$(free -h | awk '/Mem/{print $3 "/" $2}')${NC}"
    echo -e "存储: ${CYAN}$(df -h / | awk 'NR==2{print $4 " 可用"}')${NC}"
    
    if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
        temp=$(awk '{print $1/1000}' /sys/class/thermal/thermal_zone0/temp)
        echo -e "CPU温度: ${CYAN}${temp}°C${NC}"
    fi
    
    # 显示自动同步状态
    if [ "$AUTO_SYNC_INTERVAL" -gt 0 ]; then
        echo -e "自动同步: ${GREEN}启用 (每${AUTO_SYNC_INTERVAL}分钟)${NC}"
    else
        echo -e "自动同步: ${RED}禁用${NC}"
    fi
    
    # 显示多平台配置
    echo -e "${YELLOW}===== 平台配置 =====${NC}"
    for platform_info in "${PLATFORMS[@]}"; do
        IFS='|' read -r platform username token enabled <<< "$platform_info"
        status=$([ "$enabled" = "true" ] && echo -e "${GREEN}启用${NC}" || echo -e "${RED}禁用${NC}")
        echo -e "$platform: $status"
    done
    
    # 显示镜像同步配置
    if [ -n "$AUTO_SYNC_SOURCE" ] && [ -n "$AUTO_SYNC_TARGET" ]; then
        echo -e "${YELLOW}===== 镜像同步 ====="
        echo -e "${GREEN}$AUTO_SYNC_SOURCE → $AUTO_SYNC_TARGET${NC}"
    fi
    
    echo -e "${YELLOW}====================${NC}"
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
    cp "$0" "$backup_dir/github.sh"
    
    # 下载最新版本
    download_url="https://github.com/$GITHUB_USER/$TOOL_REPO/archive/refs/tags/v$new_version.tar.gz"
    temp_file=$(mktemp)
    
    echo -e "${BLUE}⬇️ 下载新版本...${NC}"
    curl -sL -o "$temp_file" "$download_url" || {
        echo -e "${RED}❌ 下载更新失败${NC}"
        press_enter_to_continue
        return 1
    }
    
    # 解压并替换文件
    echo -e "${BLUE}📦 解压文件...${NC}"
    temp_dir=$(mktemp -d)
    tar -xzf "$temp_file" -C "$temp_dir" --strip-components=1 || {
        echo -e "${RED}❌ 解压更新文件失败${NC}"
        rm -f "$temp_file"
        press_enter_to_continue
        return 1
    }
    
    # 替换当前脚本
    cp "$temp_dir/github.sh" "$0"
    chmod +x "$0"
    
    # 清理临时文件
    rm -f "$temp_file"
    rm -rf "$temp_dir"
    
    # 生成更新日志
    generate_changelog "v$VERSION" "v$new_version"
    
    echo -e "${GREEN}✅ 更新完成! 请重新运行工具箱${NC}"
    echo -e "${YELLOW}📝 更新日志:${NC}"
    echo "--------------------------------"
    echo "- 从 v$VERSION 更新到 v$new_version"
    echo "- 添加多仓库管理功能"
    echo "- 添加Gitee跨平台支持"
    echo "- 优化菜单结构和用户体验"
    echo "--------------------------------"
    exit 0
}
EOL

    echo -e "${GREEN}✓ 系统功能模块创建完成${NC}"
}


# 创建跨平台功能模块
create_platforms_module() {
cat > "$INSTALL_DIR/modules/platforms.sh" << 'EOL'
#!/bin/bash

# 跨平台功能模块

source "$GIT_TOOLKIT_ROOT/config.sh"

# 加载平台配置
load_platform_config() {
    if [ -f "$PLATFORM_CONFIG_FILE" ]; then
        source "$PLATFORM_CONFIG_FILE"
    else
        # 默认配置
        PLATFORMS=(
            "github|$GITHUB_USER|$GITHUB_TOKEN|true"
            "gitee|||false"
        )
        # 初始化 Gitee 用户变量
        GITEE_USER=""
    fi
        # 提取 Gitee 用户名
    GITEE_USER=""
    for platform_info in "${PLATFORMS[@]}"; do
        IFS='|' read -r platform username token enabled <<< "$platform_info"
        if [ "$platform" == "gitee" ] && [ -n "$username" ]; then
            GITEE_USER="$username"
            break
        fi
    done
    
    export GITEE_USER
}


# 保存平台配置
save_platform_config() {
    declare -p PLATFORMS > "$PLATFORM_CONFIG_FILE"
}

# GitHub适配器
github_create_repo() {
    local name=$1 description=$2 private=$3
    response=$(curl -s -X POST \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{
            \"name\": \"$name\",
            \"description\": \"$description\",
            \"private\": $private
        }" "$API_URL")
    echo "$response"
}

# Gitee适配器
gitee_create_repo() {
    local name=$1 description=$2 private=$3 token=$4
    # 将字符串布尔值转换为Gitee需要的整数
    local private_int
    if [ "$private" = "true" ]; then
        private_int=1
    else
        private_int=0
    fi
    
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$name\",
            \"description\": \"$description\",
            \"private\": $private_int,
            \"access_token\": \"$token\"
        }" "$GITEE_API_URL")
    echo "$response"
}

# 多平台仓库创建
create_multi_platform_repo() {
    local name=$1 description=$2 private=$3
    load_platform_config
    
    for platform_info in "${PLATFORMS[@]}"; do
        IFS='|' read -r platform username token enabled <<< "$platform_info"
        
        if [ "$enabled" = "true" ]; then
            echo -e "${BLUE}🚀 在 $platform 创建仓库 $name...${NC}"
            
            case $platform in
                github)
                    response=$(github_create_repo "$name" "$description" "$private")
                    ;;
                gitee)
                    if [ -z "$token" ]; then
                        echo -e "${YELLOW}⚠️ Gitee令牌未配置，跳过创建${NC}"
                        continue
                    fi
                    response=$(gitee_create_repo "$name" "$description" "$private" "$token")
                    ;;
                *)
                    echo -e "${RED}❌ 不支持的平台: $platform${NC}"
                    continue
                    ;;
            esac
            
            # 处理响应
            if [ $? -ne 0 ]; then
                echo -e "${RED}❌ $platform 创建失败: 网络错误${NC}"
                continue
            fi
            
            error_msg=""
            case $platform in
                github)
                    error_msg=$(echo "$response" | jq -r '.message')
                    clone_url=$(echo "$response" | jq -r '.clone_url')
                    ;;
                gitee)
                    error_msg=$(echo "$response" | jq -r '.message')
                    clone_url=$(echo "$response" | jq -r '.html_url')
                    if [ "$clone_url" != "null" ]; then
                        # 添加.git后缀
                        clone_url="$clone_url.git"
                    fi
                    ;;
            esac
            
            if [ "$error_msg" != "null" ] && [ -n "$error_msg" ]; then
                echo -e "${RED}❌ $platform 创建失败: $error_msg${NC}"
            elif [ -z "$clone_url" ] || [ "$clone_url" = "null" ]; then
                echo -e "${RED}❌ $platform 无法获取仓库URL${NC}"
            else
                echo -e "${GREEN}✅ $platform 仓库创建成功: $clone_url${NC}"
                # 添加到配置
                add_repo_to_config "$name" "$clone_url"
            fi
        fi
    done
}

# 跨平台同步
cross_platform_sync() {
    echo -e "${YELLOW}===== 跨平台同步 =====${NC}"
    echo "1. GitHub → Gitee"
    echo "2. Gitee → GitHub"
    echo "3. 双向同步"
    read -p "选择同步方向: " direction

    read -p "输入源仓库URL: " source_repo
    read -p "输入目标仓库用户名: " target_user
    read -p "输入目标仓库名称: " target_repo_name

    if [ -z "$source_repo" ] || [ -z "$target_user" ] || [ -z "$target_repo_name" ]; then
        echo -e "${RED}❌ 仓库信息不能为空${NC}"
        press_enter_to_continue
        return
    fi

    # 加载平台配置以获取令牌
    load_platform_config
    
    # 获取目标平台令牌
    target_platform=""
    target_token=""
    if [ "$direction" -eq 1 ]; then  # GitHub → Gitee
        target_platform="gitee"
        for platform_info in "${PLATFORMS[@]}"; do
            IFS='|' read -r platform username token enabled <<< "$platform_info"
            if [ "$platform" == "gitee" ] && [ "$enabled" == "true" ]; then
                target_token="$token"
                break
            fi
        done
    elif [ "$direction" -eq 2 ]; then  # Gitee → GitHub
        target_platform="github"
        for platform_info in "${PLATFORMS[@]}"; do
            IFS='|' read -r platform username token enabled <<< "$platform_info"
            if [ "$platform" == "github" ] && [ "$enabled" == "true" ]; then
                target_token="$token"
                break
            fi
        done
    fi
    
    if [ -z "$target_token" ]; then
        echo -e "${RED}❌ 未找到目标平台的访问令牌${NC}"
        press_enter_to_continue
        return
    fi

    # 修正目标仓库URL格式
    if [ "$target_platform" == "gitee" ]; then
        target_repo="https://$target_user:$target_token@gitee.com/$target_user/$target_repo_name.git"
    else
        target_repo="https://$target_user:$target_token@github.com/$target_user/$target_repo_name.git"
    fi
    
    echo -e "${BLUE}🔄 开始跨平台同步...${NC}"
    echo -e "${CYAN}源仓库: $source_repo${NC}"
    echo -e "${CYAN}目标仓库: $target_repo${NC}"
    
    # 检查目标仓库是否存在
    echo -e "${YELLOW}🔍 检查目标仓库是否存在...${NC}"
    repo_exists=false
    repo_private=false
    
    if [ "$target_platform" == "gitee" ]; then
        # 检查Gitee仓库
        response=$(curl -s -X GET "https://gitee.com/api/v5/repos/$target_user/$target_repo_name?access_token=$target_token")
        if echo "$response" | jq -e . >/dev/null 2>&1; then
            if [ -n "$(echo "$response" | jq -r '.message')" ]; then
                repo_exists=false
            else
                repo_exists=true
                repo_private=$(echo "$response" | jq -r '.private')
                echo -e "${GREEN}✅ 目标仓库已存在 (私有: $([ "$repo_private" = "true" ] && echo "是" || echo "否"))${NC}"
            fi
        fi
    elif [ "$target_platform" == "github" ]; then
        # 检查GitHub仓库
        response=$(curl -s -H "Authorization: token $target_token" \
            "https://api.github.com/repos/$target_user/$target_repo_name")
        if echo "$response" | jq -e . >/dev/null 2>&1; then
            if [ "$(echo "$response" | jq -r '.message')" == "Not Found" ]; then
                repo_exists=false
            else
                repo_exists=true
                repo_private=$(echo "$response" | jq -r '.private')
                echo -e "${GREEN}✅ 目标仓库已存在 (私有: $([ "$repo_private" = "true" ] && echo "是" || echo "否"))${NC}"
            fi
        fi
    fi
    
    # 如果仓库不存在则创建
    if [ "$repo_exists" = false ]; then
        echo -e "${YELLOW}⛱️ 目标仓库不存在，正在创建...${NC}"
        
        # 获取源仓库描述
        if [ "$direction" -eq 1 ]; then  # GitHub → Gitee
            # 从GitHub获取仓库描述
            repo_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
                "https://api.github.com/repos/$(echo $source_repo | sed -e 's|https://github.com/||' -e 's|.git$||')")
            description=$(echo "$repo_info" | jq -r '.description // ""')
            # 获取源仓库的私有状态作为默认值
            default_private=$(echo "$repo_info" | jq -r '.private // false')
        else
            # 默认描述
            description="同步自 $source_repo"
            default_private=false
        fi
        
        # 让用户选择仓库可见性
        echo -e "${YELLOW}请选择目标仓库的可见性:${NC}"
        echo "1. 公开 (Public)"
        echo "2. 私有 (Private)"
        read -p "输入选项 (默认: $([ "$default_private" = "true" ] && echo "2" || echo "1")): " visibility_choice
        
        case $visibility_choice in
            1) private=false ;;
            2) private=true ;;
            *) private=$default_private ;;
        esac
        
        # 创建目标仓库
        if [ "$target_platform" == "gitee" ]; then
            response=$(gitee_create_repo "$target_repo_name" "$description" "$private" "$target_token")
            error_msg=$(echo "$response" | jq -r '.message')
            if [ -n "$error_msg" ] && [ "$error_msg" != "null" ]; then
                echo -e "${RED}❌ 创建仓库失败: $error_msg${NC}"
                press_enter_to_continue
                return
            else
                # 正确获取Gitee克隆URL
                clone_url=$(echo "$response" | jq -r '.html_url')
                if [ -n "$clone_url" ] && [ "$clone_url" != "null" ]; then
                    clone_url="$clone_url.git"
                    # 更新目标仓库URL
                    target_repo="https://$target_user:$target_token@${clone_url#https://}"
                else
                    # 备用方案：手动构建URL
                    target_repo="https://$target_user:$target_token@gitee.com/$target_user/$target_repo_name.git"
                fi
                
                # 获取实际私有状态
                repo_private=$(echo "$response" | jq -r '.private')
                echo -e "${GREEN}✅ 目标仓库创建成功 (私有: $([ "$repo_private" = "true" ] && echo "是" || echo "否"))${NC}"
                echo -e "仓库URL: ${CYAN}$target_repo${NC}"
            fi
        elif [ "$target_platform" == "github" ]; then
            response=$(github_create_repo "$target_repo_name" "$description" "$private")
            error_msg=$(echo "$response" | jq -r '.message')
            if [ -n "$error_msg" ] && [ "$error_msg" != "null" ]; then
                echo -e "${RED}❌ 创建仓库失败: $error_msg${NC}"
                press_enter_to_continue
                return
            else
                clone_url=$(echo "$response" | jq -r '.clone_url')
                if [ -n "$clone_url" ] && [ "$clone_url" != "null" ]; then
                    # 更新目标仓库URL
                    target_repo="https://$target_user:$target_token@${clone_url#https://}"
                fi
                
                # 获取实际私有状态
                repo_private=$(echo "$response" | jq -r '.private')
                echo -e "${GREEN}✅ 目标仓库创建成功 (私有: $([ "$repo_private" = "true" ] && echo "是" || echo "否"))${NC}"
                echo -e "仓库URL: ${CYAN}$target_repo${NC}"
            fi
        fi
    else
        # 如果仓库已存在，显示当前可见性设置
        echo -e "${CYAN}目标仓库可见性: $([ "$repo_private" = "true" ] && echo "私有" || echo "公开")${NC}"
    fi
    
    # 创建临时目录
    temp_dir=$(mktemp -d)
    cd "$temp_dir" || return
    
    # 克隆源仓库
    echo -e "${CYAN}⬇️ 克隆源仓库...${NC}"
    git clone --mirror "$source_repo" temp_sync_repo || {
        echo -e "${RED}❌ 克隆源仓库失败${NC}"
        cd ..
        rm -rf "$temp_dir"
        press_enter_to_continue
        return
    }
    
    cd temp_sync_repo || return
    
    # 添加目标远程
    git remote add target "$target_repo"
    
    # 根据方向同步
    case $direction in
        1|2)
            # 单向同步
            echo -e "${CYAN}🔄 单向同步中...${NC}"
            git push target --mirror || {
                echo -e "${RED}❌ 同步到目标仓库失败${NC}"
                cd ../..
                rm -rf "$temp_dir"
                press_enter_to_continue
                return
            }
            ;;
        3)
            # 双向同步
            echo -e "${CYAN}🔄 双向同步中...${NC}"
            git push target --mirror || {
                echo -e "${RED}❌ 同步到目标仓库失败${NC}"
                cd ../..
                rm -rf "$temp_dir"
                press_enter_to_continue
                return
            }
            git fetch target || {
                echo -e "${RED}❌ 从目标仓库拉取失败${NC}"
                cd ../..
                rm -rf "$temp_dir"
                press_enter_to_continue
                return
            }
            git push origin --mirror || {
                echo -e "${RED}❌ 同步回源仓库失败${NC}"
                cd ../..
                rm -rf "$temp_dir"
                press_enter_to_continue
                return
            }
            ;;
        *)
            echo -e "${RED}❌ 无效的同步方向${NC}"
            cd ../..
            rm -rf "$temp_dir"
            press_enter_to_continue
            return
            ;;
    esac
    
    cd ../..
    rm -rf "$temp_dir"
    echo -e "${GREEN}✅ 同步完成${NC}"
    audit_log "CROSS_PLATFORM_SYNC" "$source_repo → $target_repo"
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

# ====== GitHub 到 Gitee 自动同步 ======
github_to_gitee_sync() {
    # 获取 GitHub 项目信息
    read -p "输入 GitHub 项目名称 (格式: 用户名/仓库名): " github_repo
    if [[ ! "$github_repo" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}❌ 无效的项目名称格式，请使用 '用户名/仓库名' 格式${NC}"
        press_enter_to_continue
        return
    fi
    
    # 解析用户名和仓库名
    IFS='/' read -r github_user github_repo_name <<< "$github_repo"
    
    # 获取仓库信息
    echo -e "${BLUE}📡 获取 GitHub 仓库信息...${NC}"
    repo_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$github_repo")
    
    error_msg=$(echo "$repo_info" | jq -r '.message')
    if [ "$error_msg" != "null" ]; then
        echo -e "${RED}❌ 获取仓库信息失败: $error_msg${NC}"
        press_enter_to_continue
        return
    fi
    
    # 提取仓库信息
    repo_description=$(echo "$repo_info" | jq -r '.description')
    repo_private=$(echo "$repo_info" | jq -r '.private')
    
    # 仓库可见性选择
    echo -e "${YELLOW}===== 仓库可见性设置 ====="
    echo "1. 使用 GitHub 设置 (当前: $([ "$repo_private" == "true" ] && echo "私有" || echo "公开"))"
    echo "2. 设为私有仓库"
    echo "3. 设为公开仓库"
    echo -e "${YELLOW}============================${NC}"
    
    while true; do
        read -p "选择可见性设置 (1-3): " visibility_choice
        case $visibility_choice in
            1)
                gitee_private=$repo_private
                break
                ;;
            2)
                gitee_private="true"
                break
                ;;
            3)
                gitee_private="false"
                break
                ;;
            *)
                echo -e "${RED}❌ 无效选择，请重新输入${NC}"
                ;;
        esac
    done
    
    # 创建 Gitee 仓库
    echo -e "${BLUE}🚀 在 Gitee 上创建仓库 '$github_repo_name'...${NC}"
    
    # 获取 Gitee 令牌
    gitee_token=""
    for platform_info in "${PLATFORMS[@]}"; do
        IFS='|' read -r platform username token enabled <<< "$platform_info"
        if [ "$platform" == "gitee" ] && [ "$enabled" == "true" ]; then
            gitee_token="$token"
            break
        fi
    done
    
    if [ -z "$gitee_token" ]; then
        echo -e "${RED}❌ 未配置 Gitee 访问令牌${NC}"
        press_enter_to_continue
        return
    fi
    
    # 修复：将字符串布尔值转换为Gitee需要的整数
    local private_int
    if [ "$gitee_private" = "true" ]; then
        private_int=1
    else
        private_int=0
    fi
    
    # 在 Gitee 上创建仓库
    gitee_response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$github_repo_name\",
            \"description\": \"$repo_description\",
            \"private\": $private_int,
            \"access_token\": \"$gitee_token\"
        }" "https://gitee.com/api/v5/user/repos")
    
    gitee_error=$(echo "$gitee_response" | jq -r '.message')
    if [ -n "$gitee_error" ] && [ "$gitee_error" != "null" ]; then
        # 检查是否已存在同名仓库
        if [[ "$gitee_error" == *"已经存在"* ]]; then
            echo -e "${YELLOW}ℹ️ Gitee 仓库已存在，继续同步${NC}"
        else
            echo -e "${RED}❌ 创建 Gitee 仓库失败: $gitee_error${NC}"
            press_enter_to_continue
            return
        fi
    fi
    
    # 获取 Gitee 仓库 URL
    gitee_repo_url="https://gitee.com/$GITEE_USER/$github_repo_name.git"
    
    # 创建临时目录
    temp_dir=$(mktemp -d)
    cd "$temp_dir" || return
    
    # 克隆 GitHub 仓库
    echo -e "${BLUE}⬇️ 克隆 GitHub 仓库...${NC}"
    git clone --mirror "https://github.com/$github_repo.git" . || {
        echo -e "${RED}❌ 克隆 GitHub 仓库失败${NC}"
        cd ..
        rm -rf "$temp_dir"
        press_enter_to_continue
        return
    }
    
    # 推送到 Gitee
    echo -e "${BLUE}🔄 同步到 Gitee...${NC}"
    
    # 添加认证信息
    auth_gitee_url="https://$GITEE_USER:$gitee_token@gitee.com/$GITEE_USER/$github_repo_name.git"
    
    git push --mirror "$auth_gitee_url" || {
        echo -e "${RED}❌ 同步到 Gitee 失败${NC}"
        cd ..
        rm -rf "$temp_dir"
        press_enter_to_continue
        return
    }
    
    # 清理
    cd ..
    rm -rf "$temp_dir"
    
    # 显示仓库类型
    repo_type=$([ "$gitee_private" = "true" ] && echo "私有" || echo "公开")
    echo -e "${GREEN}✅ 同步完成: GitHub → Gitee ($repo_type 仓库)${NC}"
    echo -e "Gitee 仓库 URL: ${CYAN}https://gitee.com/$GITEE_USER/$github_repo_name${NC}"
    
    audit_log "GITHUB_TO_GITEE_SYNC" "$github_repo → gitee.com/$GITEE_USER/$github_repo_name (private:$gitee_private)"
    press_enter_to_continue
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
    echo -e "${YELLOW}        遥辉GitHub同步管理工具安装程序 v3.0.0${NC}"
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