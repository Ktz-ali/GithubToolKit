<p align="center">
    <a href="https://github.com/Ktz-ali" target="_blank" rel="noopener noreferrer">
        <img width="100" src="https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png" alt="github logo" />
    </a>
</p>

<p align="center"><b>GithubToolKit</b> 一款多功能命令行Github仓库同步管理工具</p>

------------------------------

> **注意**：本工具箱需要GitHub访问令牌，请确保令牌具有以下权限：repo, admin:org, gist, delete_repo[点击创建令牌](https://github.com/settings/tokens)

## 遥辉寄语
> 初心是为了方便自己使用而去做的，由于本人常在linux终端上操作所以使用的是bash写的，花费了一个星期左右的时间完善部分功能及模块化管理，期间包括新增功能、调试测试功能、优化改进功能逻辑，争取一气呵成做到相对完美，但是脑瓜子不够用已经想不出来要新增什么功能了，有想过使用php来整被一些功能实现卡着了没折就放弃了，所以在此开源希望更多有兴趣的开发者加入进来共同创作

## 目录结构
```bash
~/GithubToolKit/
├── common.sh                  # 全局配置文件
├── main.sh                    # 主入口脚本
├── modules/                   # 功能模块目录
│   ├── core.sh                # 核心功能模块（仓库创建、同步等）
│   ├── senior.sh              # 高级功能模块（组织管理、代码片段等）
│   ├── system.sh              # 系统功能模块（配置、更新等）
│   ├── warehouse.sh           # 仓库管理模块（议题、协作者等）
│   └── platforms.sh           # 跨平台同步模块（GitHub到Gitee等）
└── log/                       # 日志目录（首次运行后创建）
    ├── toolkit.log            # 常规日志
    └── audit.log              # 审计日志
```

## 环境要求
- **操作系统**：
  - Debian/Ubuntu
  - CentOS/RHEL/Fedora/Rocky/AlmaLinux
  - openSUSE/SLES
- **依赖软件包**：
  - `git` (版本控制)
  - `curl` (API调用)
  - `jq` (JSON处理)
- **权限要求**：
  - 安装脚本需以`root`权限运行
  - 常规操作可使用普通用户权限
- **存储空间**：
  - 最小50MB可用空间
- **网络要求**：
  - 能访问GitHub和Gitee API
  - 稳定的网络连接

## 工具箱介绍
GithubToolKit是一个通过GitHub API开发的多功能GitHub仓库管理工具。它提供：
- 简化的仓库创建、同步和管理流程
- 跨平台仓库同步（GitHub ↔ Gitee）
- 自动化同步任务
- 组织管理和团队协作工具
- 详细的仓库统计和状态监控
- 模块化设计便于扩展和维护

## 最近更新

详细更新日志请查看[更新日志](https://github.com/Ktz-ali/GithubToolKit/blob/main/Update.md)


## 使用说明

### 安装
```bash
# 1. 下载安装脚本
curl -O https://github.com/Ktz-ali/GithubToolKit/blob/main/install.sh

# 2. 赋予权限并执行
chmod +x install.sh
sudo ./install.sh

```

### 首次配置
首次启动将引导完成配置：
```bash
github-toolkit
```
1. 输入GitHub用户名
2. 提供GitHub访问令牌
3. 设置默认同步目录（默认：`/root/github_sync`）
4. 选择是否启用Gitee支持
5. 配置Gitee账户信息（如启用）

### 常规使用
```bash
# 启动工具箱
github-toolkit

# 自动同步模式（需先配置）
github-toolkit --auto-sync
```

## 功能解析及作用

### 核心功能 (`core.sh`)
1. **仓库创建与同步**
   - 初始化本地Git仓库
   - 自动生成`.gitignore`和`README.md`
   - 支持私有/公有仓库选项
   - 可选Git LFS支持

2. **变更管理**
   - 推送本地更改到GitHub
   - 拉取远程更改到本地
   - 自动检测未提交更改

3. **仓库管理**
   - 更新仓库描述
   - 删除GitHub仓库
   - 查看仓库列表
   - 仓库缓存机制（5分钟有效期）

### 仓库管理 (`warehouse.sh`)
1. **仓库操作**
   - 搜索仓库
   - 管理议题（创建/关闭/查看）
   - 管理协作者（添加/移除）
   - 管理Webhooks

2. **仓库状态管理**
   - 归档/取消归档仓库
   - 启用/禁用仓库
   - 设置/取消模板仓库
   - 更改仓库可见性（公开/私有）
   - 转移仓库所有权

3. **多仓库管理**
   - 列出配置的仓库
   - 切换当前操作的仓库
   - 查看仓库统计（星标、关注者等）

### 高级功能 (`senior.sh`)
1. **组织管理**
   - 查看组织仓库
   - 创建组织仓库
   - 管理组织成员

2. **分支管理**
   - 查看分支列表
   - 创建新分支
   - 删除分支
   - 合并分支

3. **自动化**
   - 设置定时自动同步
   - 配置Systemd定时器
   - 支持分钟级同步间隔

### 跨平台功能 (`platforms.sh`)
1. **GitHub ↔ Gitee同步**
   - 单向同步（GitHub → Gitee）
   - 双向同步
   - 自动创建目标仓库
   - 仓库可见性配置

2. **多平台管理**
   - 添加/编辑平台配置
   - 启用/禁用平台
   - 配置自动镜像同步

3. **Gitee特定功能**
   - 批量设置仓库可见性
   - Gitee API适配器

### 系统功能 (`system.sh`)
1. **配置管理**
   - 首次运行向导
   - 配置版本迁移
   - 配置保存/加载

2. **日志系统**
   - 常规操作日志
   - 审计日志（关键操作记录）
   - 日志轮转管理

3. **更新与维护**
   - 自动检查更新
   - 一键更新工具箱
   - 系统状态监控（内存、存储等）

## 使用流程

### 首次使用流程
![首次使用流程图](https://github.com/Ktz-ali/GithubToolKit/blob/main/流程图/1.首次使用流程图.jpg)

### 创建仓库流程
![创建仓库流程图](https://github.com/Ktz-ali/GithubToolKit/blob/main/流程图/2.创建仓库流程图.jpg)

### 跨平台同步流程
![跨平台同步流程图](https://github.com/Ktz-ali/GithubToolKit/blob/main/流程图/3.跨平台同步流程图.jpg)

### 功能菜单界面
![功能菜单界面图](https://github.com/Ktz-ali/GithubToolKit/blob/main/流程图/4.功能菜单界面图.jpg)

## 技术特点

1. **模块化架构**
   - 功能按模块划分（核心、仓库、高级等）
   - 模块间低耦合设计
   - 易于扩展新功能

2. **API适配器模式**
   - GitHub API适配器
   - Gitee API适配器
   - 统一接口支持多平台

3. **缓存机制**
   - 仓库列表缓存（300秒）
   - 减少API调用频率
   - 提升响应速度

4. **错误处理**
   - 全面的错误检测
   - 友好的错误提示
   - 操作回退机制

5. **自动化集成**
   - Systemd定时器支持
   - 后台自动同步
   - 邮件通知（待实现）

6. **安全设计**
   - 凭证加密存储
   - 审计日志记录
   - 操作确认机制

7. **多平台支持**
   - 特殊处理CentOS 7仓库
   - 自动识别系统类型
   - 平台特定依赖处理

## 贡献指南

### 开发流程
1. Fork主仓库
2. 创建特性分支
```bash
git checkout -b feature/new-feature
```
3. 提交代码变更
4. 创建Pull Request

### 代码规范
- 使用4空格缩进
- 函数注释说明：
  ```bash
  # 函数功能简述
  # 参数: 
  #   $1 - 参数1描述
  #   $2 - 参数2描述
  # 返回值: 描述
  ```
- 模块间通过配置文件交互
- 避免全局变量污染

### 测试要求
1. 新增功能需包含测试用例
2. 测试覆盖率不低于70%
3. 跨平台测试（至少2个发行版）

### 问题报告
1. 使用GitHub Issues报告问题
2. 提供：
   - 操作系统版本
   - 工具箱版本
   - 复现步骤
   - 相关日志

## 赞助支持

如果 GithubToolKit 对你有帮助，欢迎[赞助支持](https://github.com/Ktz-ali)，感谢以下赞助者对 GithubToolKit 项目的支持：

<p align="center">
  <a target="_blank" href="https://github.com/Ktz-ali">
  </a>
</p>

## MIT许可证
[MIT](LICENSE)