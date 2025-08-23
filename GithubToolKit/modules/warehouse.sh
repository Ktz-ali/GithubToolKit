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