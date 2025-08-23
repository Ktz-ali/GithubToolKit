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