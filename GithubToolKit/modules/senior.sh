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