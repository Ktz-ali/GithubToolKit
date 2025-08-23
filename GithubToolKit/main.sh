#!/bin/bash

# GitHub工具箱主入口
VERSION="3.2.0"
LAST_UPDATE="2025-08-10"
TOOL_REPO="GithubToolKit"  # 工具箱的仓库名称

# 确保脚本使用bash执行
if [ -z "$BASH_VERSION" ]; then
    echo -e "${RED}错误: 请使用bash执行此脚本${NC}"
    exit 1
fi

# 加载配置和模块
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GIT_TOOLKIT_ROOT="$SCRIPT_DIR"

source "$GIT_TOOLKIT_ROOT/common.sh" # 通用函数库
source "$GIT_TOOLKIT_ROOT/modules/core.sh" # 核心功能模块
source "$GIT_TOOLKIT_ROOT/modules/warehouse.sh" # 仓库管理模块
source "$GIT_TOOLKIT_ROOT/modules/senior.sh" # 高级功能模块
source "$GIT_TOOLKIT_ROOT/modules/system.sh" # 系统功能模块
source "$GIT_TOOLKIT_ROOT/modules/platforms.sh" # 跨平台同步Gitee

# ====== 主程序 ======
main() {
    # 确保日志文件存在
    mkdir -p "$LOG_DIR"
    touch "$LOG_FILE" "$AUDIT_LOG_FILE"
    chmod 600 "$LOG_FILE" "$AUDIT_LOG_FILE"
    
    # 运行首次配置向导
    if first_run_wizard; then
        # 首次运行后加载配置
        load_config
        
        # 创建初始缓存文件
        touch "$REPO_CACHE_FILE"
    else
        load_config || {
            echo -e "${RED}❌ 无法加载配置文件${NC}"
            exit 1
        }
    fi
    
    # 验证令牌有效性
    if ! verify_github_token; then
        echo -e "${RED}❌ GitHub令牌无效或过期，请检查配置${NC}"
        press_enter_to_continue
        exit 1
    fi
    
    # 检查令牌有效期
    if ! check_token_expiration; then
        echo -e "${YELLOW}⚠️ 令牌已过期，部分功能可能受限${NC}"
    fi
    
    check_dependencies
    
    # 显示欢迎信息
    echo -e "${YELLOW}🔑 使用GitHub账号: $GITHUB_USER${NC}"
    if [ -n "$CURRENT_REPO" ]; then
        echo -e "${CYAN}📦 当前仓库: $CURRENT_REPO${NC}"
    fi
    
    # 预加载仓库列表
    echo -e "${BLUE}⏳ 预加载仓库列表...${NC}"
    get_repo_list > /dev/null 2>&1
    
    # 切换到指定同步目录
    if [ -n "$SYNC_DIR" ] && [ "$SYNC_DIR" != "." ]; then
        echo -e "${BLUE}切换到同步目录: $SYNC_DIR${NC}"
        mkdir -p "$SYNC_DIR"
        cd "$SYNC_DIR" || { echo -e "${RED}❌ 无法进入目录: $SYNC_DIR${NC}"; exit 1; }
    fi
    
    # 检查是否自动同步模式
    if [ "$1" == "--auto-sync" ]; then
        log "INFO" "自动同步任务启动"
        if push_changes; then
            log "INFO" "自动同步完成"
        else
            log "ERROR" "自动同步失败"
        fi
        exit 0
    fi
    
    show_menu
}

# ====== 主菜单 ======
show_menu() {
    while true; do
        clear
        echo -e "${BLUE}"
        echo "   ____ _ _   _   _       _          _   "
        echo "  / ___(_) |_| | | |_   _| |__   ___| |_ "
        echo " | |  _| | __| |_| | | | | '_ \ / _ \ __|"
        echo " | |_| | | |_|  _  | |_| | |_) |  __/ |_ "
        echo "  \____|_|\__|_| |_|\__,_|_.__/ \___|\__|"
        echo -e "${NC}"
        echo -e "${YELLOW} 遥辉GitHub 同步管理工具箱 v${VERSION} (${LAST_UPDATE})${NC}"
        echo -e "${BLUE}==================================================${NC}"
        echo -e "${GREEN}同步目录: $SYNC_DIR${NC}"
        if [ -n "$CURRENT_REPO" ]; then
            echo -e "${CYAN}当前仓库: $CURRENT_REPO${NC}"
        fi
        echo -e "${BLUE}--------------------------------------------------${NC}"
        
        # 居中显示分类标题函数
        center_title() {
            local title="$1"
            local color="$2"
            local total_width=50
            local title_len=${#title}
            local padding_left=$(( (total_width - title_len) / 2 ))
            local padding_right=$(( total_width - title_len - padding_left ))
            
            printf "%${padding_left}s" | tr ' ' '='
            echo -ne "${color}${title}${NC}"
            printf "%${padding_right}s" | tr ' ' '='
            echo
        }
        
        # ====== 仓库操作管理 ======
        center_title " 仓库基本操作 " "${GREEN}"
        echo -e "${GREEN}01. 创建仓库并同步${NC}\t\t${GREEN}02. 克隆远程仓库${NC}"
        echo -e "${GREEN}03. 同步到现有仓库${NC}\t\t${GREEN}04. 更新仓库描述${NC}"
        echo -e "${GREEN}05. 删除项目仓库${NC}\t\t${GREEN}06. 仓库配置管理${NC}"
        
        # ====== 代码版本管理 ======
        center_title " 代码版本管理 " "${CYAN}"
        echo -e "${CYAN}07. 拉取远程更改${NC}\t\t${CYAN}08. 推送本地更改${NC}"
        echo -e "${CYAN}09. 本地分支管理${NC}\t\t${CYAN}10. 远程分支管理${NC}"
        echo -e "${CYAN}11. 标签发布管理${NC}\t\t${CYAN}12. 文件历史查看${NC}"
        
        # ====== 协作功能管理 ======
        center_title " 协作功能管理 " "${PURPLE}"
        echo -e "${PURPLE}13. 我的组织管理${NC}\t\t${PURPLE}14. 协作人员管理${NC}"
        echo -e "${PURPLE}15. 项目议题管理${NC}\t\t${PURPLE}16. 里程碑管理${NC}"
        echo -e "${PURPLE}17. 拉取请求管理${NC}\t\t${PURPLE}18. Webhook管理${NC}"
        
        # ====== 高级功能管理 ======
        center_title " 高级功能管理 " "${YELLOW}"
        echo -e "${YELLOW}19. 代码片段管理${NC}\t\t${YELLOW}20. 仓库状态管理${NC}"
        echo -e "${YELLOW}21. LFS储存管理${NC}\t\t\t${YELLOW}22. 仓库维护管理${NC}"
        echo -e "${YELLOW}23. 代码搜索功能${NC}\t\t${YELLOW}24. 仓库搜索管理${NC}"
        
        # ====== 跨平台同步管理 ======
        center_title " 跨平台同步管理 " "${BLUE}"
        echo -e "${BLUE}25. 跨平台同步${NC}\t\t\t${BLUE}26. 多平台镜像配置${NC}"
        
        # ====== 系统功能管理 ======
        center_title " 系统功能管理 " "${MAGENTA}"
        echo -e "${MAGENTA}27. 自动同步设置${NC}\t\t${MAGENTA}28. 系统状态信息${NC}"
        echo -e "${MAGENTA}29. 仓库统计与活动${NC}\t\t${MAGENTA}30. 系统资源监控${NC}"
        echo -e "${MAGENTA}31. 检查版本更新${NC}\t\t${MAGENTA}32. 工具箱诊断${NC}"
        echo -e "${MAGENTA}33. 日志查看器${NC}\t\t\t${RED}34. 退出工具箱${NC}"
        echo -e "${BLUE}==================================================${NC}"
        
        read -p "请选择操作 (1-34): " choice
        
        case $choice in
            01) create_and_sync_repo ;;
            02) clone_repository ;;
            03) sync_to_existing_repo ;;
            04) update_repo_description ;;
            05) delete_github_repo ;;
            06) list_configured_repos ;;
            07) pull_changes ;;
            08) push_changes ;;
            09) manage_local_branches ;;
            10) manage_branches ;;
            11) manage_tags ;;
            12) view_file_history ;;
            13) manage_organizations ;;
            14) manage_collaborators ;;
            15) manage_issues ;;
            16) manage_milestones ;;
            17) manage_pull_requests ;;
            18) view_webhooks ;;
            19) manage_gists ;;
            20) manage_repo_status ;;
            21) manage_git_lfs ;;
            22) repo_maintenance ;;
            23) search_code ;;
            24) search_repos ;;
            25) cross_platform_sync ;;
            26) setup_multi_platform_sync ;;
            27) setup_auto_sync ;;
            28) show_system_info ;;
            29) repo_stats_and_activity ;;
            30) monitor_system_resources ;;
            31) check_for_updates ;;
            32) diagnose_toolkit ;;
            33) view_logs ;;
            34) 
                echo -e "${BLUE}👋 退出程序${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ 无效选择，请重新输入${NC}"
                sleep 1
                ;;
        esac
    done
}

# 启动主程序
main "$@"