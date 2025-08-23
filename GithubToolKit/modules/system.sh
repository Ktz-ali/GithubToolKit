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