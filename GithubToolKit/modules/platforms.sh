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
