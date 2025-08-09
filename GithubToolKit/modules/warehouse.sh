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