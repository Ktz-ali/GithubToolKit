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