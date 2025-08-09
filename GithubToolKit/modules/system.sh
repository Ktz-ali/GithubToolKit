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