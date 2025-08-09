#!/bin/bash

# 核心功能模块

# 加载配置和工具
source "$GIT_TOOLKIT_ROOT/config.sh"

# 确保日志目录存在
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$AUDIT_LOG_FILE")"
touch "$LOG_FILE" "$AUDIT_LOG_FILE"
chmod 600 "$LOG_FILE" "$AUDIT_LOG_FILE"

# 同步内容到仓库日志 - 修复语法错误
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
    git status -s
    
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