#!/bin/bash

# GitHub工具箱主入口
VERSION="3.0"
LAST_UPDATE="2025-08-04"
TOOL_REPO="GithubToolKit"  # 工具箱的仓库名称

# 确保脚本使用bash执行
if [ -z "$BASH_VERSION" ]; then
    echo -e "${RED}错误: 请使用bash执行此脚本${NC}"
    exit 1
fi

# 加载配置和模块
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GIT_TOOLKIT_ROOT="$SCRIPT_DIR"

source "$GIT_TOOLKIT_ROOT/config.sh" # 全局配置文件
source "$GIT_TOOLKIT_ROOT/modules/core.sh" # 核心功能模块
source "$GIT_TOOLKIT_ROOT/modules/warehouse.sh" # 仓库管理模块
source "$GIT_TOOLKIT_ROOT/modules/senior.sh" # 高级功能模块
source "$GIT_TOOLKIT_ROOT/modules/system.sh" # 系统功能模块
source "$GIT_TOOLKIT_ROOT/modules/platforms.sh" # 跨平台同步Gitee


# ====== 主程序 ======
main() {
    # 确保日志文件存在
    touch "$LOG_FILE" "$AUDIT_LOG_FILE"
    chmod 600 "$LOG_FILE" "$AUDIT_LOG_FILE"
    
    # 运行首次配置向导
    if first_run_wizard; then
        # 首次运行后加载配置
        load_config
    else
        # 加载现有配置
        load_config || {
            echo -e "${RED}❌ 无法加载配置文件${NC}"
            exit 1
        }
    fi
    
    check_dependencies
    
    # 显示欢迎信息
    echo -e "${YELLOW}🔑 使用GitHub账号: $GITHUB_USER${NC}"
    if [ -n "$CURRENT_REPO" ]; then
        echo -e "${CYAN}📦 当前仓库: $CURRENT_REPO${NC}"
    fi
    
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
        echo -e "${BLUE}======== 核心功能 ========${NC}"
        echo -e "${GREEN}1. 创建仓库并同步${NC}"
        echo -e "${GREEN}2. 同步到现有仓库${NC}"
        echo -e "${GREEN}3. 拉取远程更改${NC}"
        echo -e "${GREEN}4. 更新仓库描述${NC}"
        echo -e "${GREEN}5. 删除项目仓库${NC}"
        
        echo -e "${BLUE}======== 仓库管理 ========${NC}"
        echo -e "${CYAN}6. 综合仓库功能${NC}"
        echo -e "${CYAN}7. 多个仓库管理${NC}"
        echo -e "${CYAN}8. 查看仓库统计${NC}"
        
        echo -e "${BLUE}======== 高级功能 ========${NC}"
        echo -e "${PURPLE}9. 我的组织管理${NC}"
        echo -e "${PURPLE}10. 项目分支管理${NC}"
        echo -e "${PURPLE}11. 代码片段管理${NC}"
        echo -e "${PURPLE}12. 自动同步设置${NC}"
        
        echo -e "${BLUE}======== 跨平台功能 ========${NC}"
        echo -e "${YELLOW}13. GitHub → Gitee 自动同步${NC}"  # 修改此项
        echo -e "${YELLOW}14. 跨平台同步到现有Gitee仓库${NC}"
        echo -e "${YELLOW}15. 多平台镜像配置${NC}"
        
        echo -e "${BLUE}======== 系统功能 ========${NC}"
        echo -e "${YELLOW}16. 检查版本更新${NC}"
        echo -e "${YELLOW}17. 系统状态信息${NC}"
        echo -e "${RED}18. 退出${NC}"
        echo -e "${BLUE}==================================================${NC}"
        
        read -p "请选择操作 (1-18): " choice
        
        case $choice in
            1) create_and_sync_repo ;;
            2) sync_to_existing_repo ;;
            3) pull_changes ;;
            4) update_repo_description ;;
            5) delete_github_repo ;;
            6) repo_management_menu ;;
            7) multi_repo_management_menu ;;
            8) show_repo_stats ;;
            9) manage_organizations ;;
            10) manage_branches ;;
            11) manage_gists ;;
            12) setup_auto_sync ;;
            13) github_to_gitee_sync ;;
            14) cross_platform_sync ;;
            15) setup_multi_platform_sync ;;
            16) check_for_updates ;;
            17) show_system_info ;;
            18) 
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