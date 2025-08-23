#!/bin/bash

# 仓库操作功能模块

# 加载配置和工具
source "$GIT_TOOLKIT_ROOT/common.sh"

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

    # 检查目录是否已存在
    if [ -d "$local_dir" ]; then
        echo -e "${YELLOW}⚠️ 目录 '$local_dir' 已存在${NC}"
        read -p "是否覆盖? (y/N): " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}❌ 取消克隆操作${NC}"
            return 1
        fi
        rm -rf "$local_dir"
    fi

    echo -e "${BLUE}⬇️ 正在克隆仓库...${NC}"

    if git clone "$repo_url" "$local_dir"; then
        echo -e "${GREEN}✅ 仓库克隆成功${NC}"
        cd "$local_dir" || return 1
        
        # 将新仓库添加到配置
        add_repo_to_config "$repo_name" "$repo_url"
        
        # 设置当前仓库
        save_config_key "CURRENT_REPO" "$repo_name"
        
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



# ====== 保存配置键值对 ======
save_config_key() {
    local key="$1"
    local value="$2"
    
    # 如果配置文件不存在，则创建
    if [ ! -f "$CONFIG_FILE" ]; then
        touch "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
    fi
    
    # 如果键已存在，则更新，否则追加
    if grep -q "^$key=" "$CONFIG_FILE"; then
        sed -i "s|^$key=.*|$key=$value|" "$CONFIG_FILE"
    else
        echo "$key=$value" >> "$CONFIG_FILE"
    fi
}

# ====== 同步到现有仓库 ======
sync_to_existing_repo() {
    local current_dir=$(pwd)
    
    # 检查当前目录是否是Git仓库，如果不是则初始化
    if [ ! -d ".git" ]; then
        echo -e "${YELLOW}⚠️ 当前目录不是Git仓库${NC}"
        read -p "是否要初始化为Git仓库? (Y/n): " init_choice
        init_choice=${init_choice:-Y}
        
        if [[ "$init_choice" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}🛠️ 初始化Git仓库...${NC}"
            if ! git init; then
                echo -e "${RED}❌ Git初始化失败${NC}"
                press_enter_to_continue
                return 1
            fi
            
            # 添加所有文件并提交
            if [ -n "$(ls -A)" ]; then
                echo -e "${BLUE}📝 添加文件到仓库...${NC}"
                git add .
                git commit -m "初始提交"
                echo -e "${GREEN}✅ Git仓库初始化完成${NC}"
            else
                # 创建初始文件
                echo "# $REPO_NAME" > README.md
                echo "初始提交" > .gitkeep
                git add .
                git commit -m "初始提交"
                echo -e "${GREEN}✅ 已创建初始文件并提交${NC}"
            fi
        else
            echo -e "${YELLOW}❌ 取消同步操作${NC}"
            press_enter_to_continue
            return 1
        fi
    fi

    # 获取仓库列表
    echo -e "${BLUE}📡 获取GitHub仓库列表...${NC}"
    repo_json=$(get_repo_list)
    if [ -z "$repo_json" ]; then
        echo -e "${RED}❌ 无法获取仓库列表${NC}"
        press_enter_to_continue
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
        press_enter_to_continue
        return 1
    fi
    
    # 获取仓库名称
    repo_info=(${repo_array[$((repo_index-1))]})
    repo_name=${repo_info[1]}
    
    # 验证仓库存在
    echo -e "${BLUE}🔍 验证仓库 '$repo_name' 是否存在...${NC}"
    encoded_repo_name=$(urlencode "$repo_name")
    repo_info=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/repos/$GITHUB_USER/$encoded_repo_name")
    
    if [ "$(echo "$repo_info" | jq -r '.message')" == "Not Found" ]; then
        echo -e "${RED}❌ 仓库 '$repo_name' 不存在${NC}"
        press_enter_to_continue
        return 1
    fi
    
    # 获取仓库URL
    REPO_URL=$(echo "$repo_info" | jq -r '.clone_url')
    if [ -z "$REPO_URL" ] || [ "$REPO_URL" == "null" ]; then
        echo -e "${RED}❌ 无法获取仓库URL${NC}"
        press_enter_to_continue
        return 1
    fi
    
    echo -e "${GREEN}✅ 找到仓库: $REPO_URL${NC}"
    
    # 添加远程仓库
    if git remote | grep -q origin; then
        read -p "⚠️ 已存在origin远程仓库，是否覆盖? (y/N): " overwrite
        if [[ "$overwrite" =~ ^[Yy]$ ]]; then
            git remote remove origin
            echo -e "${GREEN}✅ 已移除原有origin远程仓库${NC}"
        else
            echo -e "${YELLOW}❌ 取消同步操作${NC}"
            press_enter_to_continue
            return 1
        fi
    fi
    
    # 添加带认证的远程URL
    repo_path=${REPO_URL#https://}
    AUTH_REPO_URL="https://$GITHUB_USER:$GITHUB_TOKEN@$repo_path"
    
    echo -e "${BLUE}🔗 添加远程仓库...${NC}"
    if ! git remote add origin "$AUTH_REPO_URL"; then
        echo -e "${RED}❌ 添加远程仓库失败${NC}"
        press_enter_to_continue
        return 1
    fi
    
    # 设置分支并推送
    echo -e "${BLUE}🌿 设置分支...${NC}"
    
    # 检查当前分支
    current_branch=$(git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ -z "$current_branch" ]; then
        # 如果没有分支，创建main分支
        git checkout -b main
        current_branch="main"
    fi
    
    # 重命名分支为main（如果需要）
    if [ "$current_branch" != "main" ]; then
        git branch -M "$current_branch" main
        current_branch="main"
    fi
    
    echo -e "${BLUE}🚀 正在推送代码到仓库 '$repo_name'...${NC}"
    
    # 尝试推送并捕获输出
    push_output=$(git push -u origin "$current_branch" 2>&1)
    push_exit_code=$?
    
    if [ $push_exit_code -eq 0 ]; then
        echo -e "${GREEN}✅ 代码同步成功${NC}"
        # 将新仓库添加到配置
        add_repo_to_config "$repo_name" "$REPO_URL"
        # 更新当前仓库
        save_config_key "CURRENT_REPO" "$repo_name"
        # 记录审计日志
        audit_log "SYNC_TO_REPO" "$repo_name"
    else
        echo -e "${RED}❌ 同步失败${NC}"
        echo -e "${YELLOW}错误详情:${NC}"
        echo "$push_output"
        
        # 提供特定错误的解决方案
        if echo "$push_output" | grep -q "rejected"; then
            echo -e "${YELLOW}💡 提示: 远程仓库已有内容，可能需要先拉取合并${NC}"
            read -p "是否尝试强制推送? (y/N): " force_push
            if [[ "$force_push" =~ ^[Yy]$ ]]; then
                if git push -u -f origin "$current_branch"; then
                    echo -e "${GREEN}✅ 强制推送成功${NC}"
                    add_repo_to_config "$repo_name" "$REPO_URL"
                    save_config_key "CURRENT_REPO" "$repo_name"
                    audit_log "SYNC_TO_REPO" "$repo_name (强制推送)"
                else
                    echo -e "${RED}❌ 强制推送也失败${NC}"
                    echo -e "${YELLOW}错误详情:${NC}"
                    git push -u -f origin "$current_branch" 2>&1
                fi
            else
                echo -e "${YELLOW}💡 提示: 您可以先拉取远程更改并合并后再尝试推送${NC}"
                read -p "是否尝试拉取并合并? (y/N): " pull_merge
                if [[ "$pull_merge" =~ ^[Yy]$ ]]; then
                    if git pull origin "$current_branch" --rebase; then
                        echo -e "${GREEN}✅ 拉取并合并成功${NC}"
                        if git push -u origin "$current_branch"; then
                            echo -e "${GREEN}✅ 推送成功${NC}"
                            add_repo_to_config "$repo_name" "$REPO_URL"
                            save_config_key "CURRENT_REPO" "$repo_name"
                            audit_log "SYNC_TO_REPO" "$repo_name"
                        else
                            echo -e "${RED}❌ 推送仍然失败${NC}"
                        fi
                    else
                        echo -e "${RED}❌ 拉取合并失败，可能存在冲突${NC}"
                    fi
                fi
            fi
        fi
    fi
    
    press_enter_to_continue
    return $push_exit_code
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