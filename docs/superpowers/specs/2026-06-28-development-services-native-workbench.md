# HHC Server Manager — 开发服务原生管理工作台改版

> 本文档用于指导“开发服务”模块的下一阶段开发。目标是把当前混合的 GitLab/Gitea/Verdaccio/pub 安装页，升级为 macOS 原生的开发服务管理工作台：安装前负责推荐、预检和部署；安装后在 HHC Server Manager 内完成主要管理操作，而不是频繁跳转到服务器上的 Web 管理后台。

## 1. 产品定位

开发服务模块是 HHC Server Manager 面向个人开发者和小团队的自托管开发基础设施入口。

新版开发服务不再只是“安装 GitLab / Gitea / Verdaccio 的面板”，而是分为三类原生工作台：

- **Git**：管理 Gitea 和 GitLab CE，覆盖代码托管、用户、组织/团队、仓库、权限、Key、Token、基础 Issue/MR/PR/Pipeline 查看。
- **npm**：管理 Verdaccio，覆盖私有 npm 包、版本、用户、访问策略、上游源、备份恢复、Nginx 反代和 smoke test。
- **pub**：管理 Dart/Flutter hosted pub 配置辅助，帮助项目接入私有 hosted repository，不在第一阶段承诺完整自托管 pub registry。

本模块仍遵守全局产品原则：

- **SSH-first for infrastructure**：安装、启停、服务状态、配置文件、Nginx、备份恢复等基础设施操作继续走 SSH。
- **API-first for product management**：仓库、用户、组织、包、权限等业务管理走 Gitea/GitLab/Verdaccio 的 HTTP API。
- **Keychain-first for secrets**：管理员 token、API token 和初始化密钥只保存在本地 Keychain，数据库只保存引用、服务 URL 和非敏感元数据。
- **Native-first**：安装完成后的高频操作在 SwiftUI 原生界面完成；Web 后台只作为兜底入口，不作为主要体验。

本模块不是：

- 不是完整替代 GitLab/Gitea 所有高级页面的第一版实现。
- 不是 CI/CD 平台重写；复杂 Pipeline 编辑、Runner 编排和深度审批流后续扩展。
- 不是完整 pub.dev 服务器实现；pub 第一阶段是 hosted repository 配置和发布辅助。
- 不是绕过官方 API 直接修改服务数据库的工具。

## 2. 信息架构

开发服务页面顶部使用分段控制：

| 顶部栏 | 管理对象 | 第一版目标 |
| --- | --- | --- |
| Git | Gitea、GitLab CE | 同机可共存，支持切换当前 Git 服务并在 app 内做原生管理 |
| npm | Verdaccio | 私有 npm 仓库安装、初始化、包/用户/策略/备份管理 |
| pub | Dart/Flutter hosted repository | 生成配置、发布命令、Token/env 指引和风险提示 |

左侧导航保留“开发服务”入口。若“镜像仓库”入口仍存在，应避免和 npm 栏重复：可以跳转到开发服务的 npm 栏，或展示同一套 npm 管理内容。

## 3. 状态模型

### 3.1 页面状态

| 状态 | 含义 | UI 行为 |
| --- | --- | --- |
| `notInstalled` | 未探测到对应服务，或用户还没有创建实例配置 | 展示推荐、资源风险、安装设置、预检、安装按钮 |
| `installedNeedsInitialization` | 服务已安装但需要完成 Web 初始化，例如 Gitea 初始管理员、GitLab root 密码变更 | 展示状态、初始化步骤、打开后台、绑定 token |
| `installedNeedsToken` | 服务可访问，但 app 尚未绑定管理员 token | 展示 token 绑定表单和最小状态，不展示完整写操作 |
| `ready` | 服务已安装且 token 有效 | 展示原生管理工作台 |
| `error` | 探测、连接、授权或 API 调用失败 | 展示失败原因、重试、重新绑定 token、打开后台 |

### 3.2 Git 服务共存策略

Gitea 和 GitLab 可以在同一台服务器上同时部署和管理。产品不强制二选一，但必须提示资源和端口风险。

| 场景 | 产品策略 |
| --- | --- |
| 轻量服务器 2C4G | 默认推荐 Gitea，GitLab 显示“需预检/资源偏高” |
| 服务器性能足够 | Gitea 和 GitLab 都可安装 |
| 两者端口冲突 | 安装前阻断，并提示修改 listen port / external URL |
| 两者都已安装 | Git 栏顶部显示两张状态卡，用户点击切换当前详情 |
| 当前选中服务异常 | 不影响另一个 Git 服务的显示和操作 |

## 4. 模块功能说明

### 4.1 Git 栏

Git 栏由“服务总览”和“当前服务详情”组成。

| 区块 | 目标 | 未安装布局 | 安装后布局 |
| --- | --- | --- | --- |
| 服务总览 | 同时看清 Gitea/GitLab 状态 | 显示推荐、资源风险、安装入口 | 显示状态、版本、URL、授权状态、打开入口 |
| Gitea 详情 | 轻量 Git 托管管理 | 安装设置、预检、安装按钮 | 仓库、用户、组织、团队、Keys、Tokens、PR/Issue 基础视图、服务操作 |
| GitLab 详情 | 完整 DevOps 服务管理 | 安装设置、预检、安装按钮 | Projects、Groups、Members、Branches、Tags、Variables、Deploy Keys、Tokens、Issue/MR/Pipeline 基础视图、服务操作 |
| 授权管理 | 让 app 使用官方 API | 安装后提示创建/粘贴 admin token | Token 状态、重新绑定、权限检查 |
| 服务运维 | 保留基础设施控制 | 预检和安装 | start/stop/restart、状态刷新、日志、备份提示 |

#### Gitea 原生管理能力

第一版应支持：

- 仓库：列表、搜索、创建、删除、归档、基础设置、默认分支、私有/公开状态。
- 用户：列表、创建、禁用/删除、基础信息、重置密码入口。
- 组织/团队：列表、创建、成员管理、仓库权限。
- SSH Key：用户 Key 列表、添加、删除。
- Access Token：Token 列表、创建引导、删除。
- Pull Requests / Issues：列表、详情、状态切换、评论后续可扩展。
- 服务：安装、状态、打开后台、start/stop/restart、最近日志。

#### GitLab 原生管理能力

第一版应支持：

- Projects：列表、搜索、创建、归档、删除、基础设置。
- Groups：列表、创建、成员管理。
- Members：项目/组成员列表、添加、移除、角色修改。
- Branches/Tags：列表、保护分支状态展示，基础创建/删除后续可扩展。
- Variables：项目变量列表、创建、更新、删除，敏感值写入前确认。
- Deploy Keys：列表、添加、启用/禁用、删除。
- Access Tokens：创建引导、撤销入口。
- Issues / Merge Requests：列表、详情、状态切换。
- Pipelines：列表、状态、打开日志/后台入口；复杂编辑后续扩展。
- 服务：预检、安装、状态、start/stop/restart、备份命令预览、最近日志。

### 4.2 npm 栏

npm 栏以 Verdaccio 为核心，安装后在 app 内完成私有 npm 仓库管理。

| 区块 | 目标 | 未安装布局 | 安装后布局 |
| --- | --- | --- | --- |
| 安装设置 | 部署 Verdaccio | 版本、路径、端口、systemd、Nginx proxy 设置 | 折叠显示当前配置 |
| 预检 | 确认 Node、端口、磁盘和 htpasswd | 运行检查，阻断硬失败 | 可重新运行检查 |
| 包管理 | 看包和版本 | 不展示 | 包列表、版本、dist-tag、大小、发布时间、删除入口 |
| 用户管理 | 管理发布用户 | 不展示 | 创建用户、改密、删除、运行 npm smoke test |
| 访问策略 | 控制发布和读取规则 | 可预览默认策略 | 修改 policy、uplink、保存配置、重启服务 |
| 备份恢复 | 降低误操作风险 | 不展示 | 创建备份、选择备份恢复、回滚提示 |
| Nginx proxy | 对外提供 registry URL | 配置生成入口 | 写入 proxy、`nginx -t`、reload |

第一版应继续复用现有 Verdaccio 安装、状态、用户、包、备份、Nginx proxy 能力，并把它们从混合页面迁移到 npm 栏。

### 4.3 pub 栏

pub 栏定位为 Dart/Flutter 私有 hosted repository 配置助手。

第一版应支持：

- 输入 hosted URL、包名、token env 名称。
- 生成 `pubspec.yaml` 片段。
- 生成 `publish_to` 片段。
- 生成 Dart/Flutter 登录、发布、拉取命令。
- 提示 HTTP 内网源、Token 暴露、pub.dev 兼容性风险。
- 可关联 npm/Verdaccio 说明：Verdaccio 是 npm registry，不等同完整 pub registry。

后续扩展：

- 自托管 pub registry 调研和安装。
- 发布历史读取。
- 包版本索引。
- 团队 Token 管理。

### 4.4 原版网页内容映射

本节定义“安装后在我们的软件里也可以完成全部功能操作”的产品映射。实现时不要求复制 Web UI 的视觉样式，但必须覆盖原 Web 后台的核心信息架构、对象列表、详情页和高频写操作。

#### Gitea Web 后台映射

| 原版 Web 内容 | HHC 原生页面 | 核心字段 | 第一版操作 | 后续增强 |
| --- | --- | --- | --- | --- |
| Dashboard / 仓库动态 | Git / Gitea / Overview | 服务状态、仓库数、用户数、组织数、最近活动、版本 | 刷新、打开后台、服务控制 | 活动流筛选、通知 |
| Repositories | Git / Gitea / Repositories | 名称、Owner、可见性、默认分支、更新时间、大小、stars/forks | 创建、搜索、归档、删除、修改基础设置 | 文件浏览、提交历史、Release |
| Repository Settings | Git / Gitea / Repository Detail | 描述、默认分支、Issues/PR/Wiki/Packages 开关、镜像状态 | 修改描述、可见性、默认分支、归档/删除 | Webhook、保护分支、镜像同步 |
| Issues | Git / Gitea / Issues | 标题、状态、标签、Assignee、Milestone、更新时间 | 列表、详情、开关状态、分配人员、标签 | 评论、批量编辑 |
| Pull Requests | Git / Gitea / Pull Requests | 源分支、目标分支、状态、Review 状态、CI 状态 | 列表、详情、关闭/重新打开、合并入口 | Review、冲突处理 |
| Organizations | Git / Gitea / Organizations | 名称、描述、成员数、仓库数 | 创建、编辑、删除 | 组织级 Webhook、套餐/配额 |
| Teams | Git / Gitea / Teams | 团队名、成员、仓库、权限单元 | 添加/移除成员、绑定仓库、修改权限 | 权限模板 |
| Users / Site Admin | Git / Gitea / Users | 用户名、邮箱、状态、管理员、最近登录 | 创建、禁用/删除、重置密码入口、授予/取消管理员 | 邮件验证、2FA 管理 |
| SSH / GPG Keys | Git / Gitea / Keys | 标题、指纹、创建时间、最后使用时间 | 添加、删除 | GPG Key、签名策略 |
| Access Tokens / OAuth2 | Git / Gitea / Tokens | 名称、Scope、创建时间、过期时间 | 创建引导、删除、权限检查 | OAuth App 管理 |
| Packages | Git / Gitea / Packages | 包名、类型、版本、大小、发布时间 | 列表、详情、删除 | 发布、跨类型筛选 |
| Site Administration | Git / Gitea / Admin | 版本、配置摘要、队列、Cron、系统日志 | 只读总览、服务控制、备份入口 | 全量管理后台 |

#### GitLab Web 后台映射

| 原版 Web 内容 | HHC 原生页面 | 核心字段 | 第一版操作 | 后续增强 |
| --- | --- | --- | --- | --- |
| Projects | Git / GitLab / Projects | 名称、Namespace、可见性、默认分支、最后活动、仓库大小 | 创建、搜索、归档、删除、修改基础设置 | 文件浏览、Release |
| Groups / Subgroups | Git / GitLab / Groups | 名称、路径、父级、成员数、项目数 | 创建、编辑、成员管理 | 子组迁移、组级模板 |
| Members | Git / GitLab / Members | 用户、角色、来源、到期时间 | 添加、移除、修改角色 | 批量成员管理 |
| Repository / Branches / Tags | Git / GitLab / Repository | 分支、Tag、保护状态、提交 SHA、创建时间 | 列表、创建/删除 Tag、查看保护状态 | 保护分支编辑、Compare |
| Issues | Git / GitLab / Issues | 标题、状态、Assignee、Label、Milestone、Due date | 列表、详情、开关状态、分配人员 | 评论、批量操作、看板 |
| Merge Requests | Git / GitLab / Merge Requests | 源/目标分支、状态、Reviewer、Pipeline、冲突状态 | 列表、详情、关闭/重新打开、合并入口 | Review、Approval 规则 |
| CI/CD Pipelines | Git / GitLab / Pipelines | Pipeline ID、分支、SHA、状态、耗时、触发者 | 列表、详情、取消/重试入口、日志打开 | Job trace 内嵌、变量触发 |
| Jobs | Git / GitLab / Jobs | Job 名、Stage、状态、Runner、耗时 | 列表、重试/取消、日志打开 | Artifact 下载 |
| Variables | Git / GitLab / Variables | Key、环境范围、Protected、Masked、类型 | 创建、更新、删除，敏感值写入确认 | 批量导入导出 |
| Deploy Keys / Deploy Tokens | Git / GitLab / Deploy Access | 标题、指纹、权限、过期时间 | 添加、启用/禁用、删除 | 只读/写权限策略 |
| Packages & Registries | Git / GitLab / Packages | 包名、类型、版本、大小 | 列表、删除、打开后台 | Container Registry 深度管理 |
| Runners | Git / GitLab / Runners | Runner ID、状态、标签、版本、最后联系时间 | 只读状态、打开后台 | 注册/暂停/删除 |
| Admin Area | Git / GitLab / Admin | 版本、License/CE、用户数、项目数、健康状态 | 只读总览、服务控制、备份命令预览 | 全量管理员后台 |

#### Verdaccio Web UI 映射

Verdaccio 官方 Web UI 主要面向包浏览；用户、权限、上游源和存储更多依赖 `config.yaml`、htpasswd 和 npm CLI。因此 HHC 原生 npm 栏要覆盖 Web UI 的包浏览，同时补齐 Web UI 不完整但运维必须有的管理能力。

| 原版/相关内容 | HHC 原生页面 | 核心字段 | 第一版操作 | 后续增强 |
| --- | --- | --- | --- | --- |
| Package Search / Package List | npm / Packages | 包名、版本数、latest、大小、更新时间、是否私有 | 搜索、刷新、详情、删除确认 | 下载量趋势 |
| Package Detail / README | npm / Package Detail | README、versions、dist-tags、dependencies、maintainers | 查看、复制安装命令、删除版本/包 | README 渲染增强 |
| Login / npm token | npm / Users & Auth | 用户名、htpasswd 状态、token 使用说明 | 创建用户、改密、删除、生成 `.npmrc` 指引 | Web token 管理 |
| Package Access | npm / Policy | access、publish、unpublish、proxy、scope 规则 | 切换公开读/登录发布/登录读写，保存前预览 diff | 多 scope 策略编辑 |
| Uplinks | npm / Uplinks | 上游名称、URL、cache、timeout | 修改 npmjs 上游 URL、保存配置、重启 | 多上游、离线镜像 |
| Configuration | npm / Settings | storage、listen、service、log、auth、packages | 查看配置摘要、受控保存、备份、重启 | 完整 YAML 编辑器 |
| Storage / Backups | npm / Backup | storage 路径、备份路径、大小、时间、状态 | 创建备份、恢复、失败回滚 | 定时备份、远程备份 |
| Nginx Proxy | npm / Proxy | server_name、config path、body size、listen | 写入配置、`nginx -t`、reload | SSL 自动申请 |
| Service Logs | npm / Service | active/substate、版本、journal tail | start/stop/restart、日志刷新、升级 | 长日志检索 |

#### pub 官方工作流映射

| 原版/官方工作流 | HHC 原生页面 | 核心字段 | 第一版操作 | 后续增强 |
| --- | --- | --- | --- | --- |
| Custom hosted dependency | pub / Dependency Config | hosted URL、package、version constraint | 生成 `pubspec.yaml` hosted dependency | 项目文件直接写入 |
| `publish_to` | pub / Publish Config | hosted URL、package path | 生成 `publish_to`，提示防止误发 pub.dev | 发布前检查 |
| `dart pub token` | pub / Token Config | hosted URL、token env | 生成 token add/list/remove 命令 | Keychain 托管本地 token |
| `dart pub publish` | pub / Publish Flow | package path、dry-run、Flutter/Dart | 生成 dry-run/publish 命令 | 内置命令执行和日志 |
| `dart pub get` / `flutter pub get` | pub / Consume Flow | package、hosted URL | 生成 get 命令和项目配置 | 项目部署联动 |

### 4.5 原生页面通用设计

安装后的原生管理页统一使用“列表 + 详情 + 操作抽屉”的结构，降低 Git/npm/pub 之间的学习成本。

| UI 区域 | 行为要求 |
| --- | --- |
| 顶部摘要 | 显示服务名、URL、版本、授权状态、最近刷新时间、打开 Web 后台 |
| 左侧对象列表 | 搜索、筛选、分页、空状态、加载状态、错误状态 |
| 右侧详情 | 展示对象核心字段、最近活动、关联对象和可执行操作 |
| 操作抽屉/弹窗 | 创建、编辑、删除、权限变更、Token 绑定等写操作统一在抽屉或 sheet 中完成 |
| 风险确认 | 删除、恢复、权限扩大、配置保存、服务重启必须二次确认 |
| 审计反馈 | 成功后显示操作摘要；失败时显示脱敏错误和重试入口 |

## 5. 交互设计流程

### 5.1 进入开发服务

1. 用户点击左侧“开发服务”。
2. 页面默认进入 `Git` 栏。
3. 系统并行加载：
   - Gitea 服务状态。
   - GitLab 服务状态。
   - Verdaccio 服务状态。
   - 已绑定 token 的 Keychain 引用状态。
4. 顶部显示三栏分段控制，Git 栏内默认选中更推荐的服务：
   - 轻量服务器默认 Gitea。
   - 已安装服务优先。
   - 两者都已安装时沿用用户上次选择。

### 5.2 Git 未安装流程

1. 用户进入 Git 栏。
2. 看到 Gitea/GitLab 两张服务卡：
   - Gitea：轻量、推荐、适合 2C4G。
   - GitLab：完整 DevOps、需预检、资源要求高。
3. 用户点击服务卡切换详情。
4. 详情区展示安装设置：
   - External URL。
   - Listen port。
   - Install path / data path。
   - Service name。
   - Firewall ports。
5. 用户点击“预检”。
6. 预检通过后启用“安装”。
7. 用户确认风险后执行安装。
8. 安装成功后进入 `installedNeedsInitialization` 或 `installedNeedsToken`。

### 5.3 Git 安装后初始化流程

1. 页面显示服务已安装、URL、版本、systemd 状态。
2. 若服务需要浏览器完成初始管理员创建，显示初始化步骤和“打开后台”。
3. 用户完成初始化后回到 app。
4. 用户粘贴或生成管理员 token。
5. app 调用官方 API 校验 token：
   - 成功：进入 `ready`。
   - 失败：提示 401/403、URL 错误、服务不可达或权限不足。
6. Token 保存到 Keychain，数据库只保存引用和服务实例元数据。

### 5.4 Git 原生管理流程

1. 用户选择 Gitea 或 GitLab。
2. 详情区显示该服务的管理标签：
   - Overview。
   - Repositories / Projects。
   - Users / Members。
   - Organizations / Groups。
   - Keys / Tokens。
   - Issues / Pull Requests / Merge Requests。
   - Settings。
   - Service。
3. 用户执行写操作时：
   - 显示目标、影响范围和确认按钮。
   - API 请求成功后刷新当前列表和详情。
   - 失败时展示 API 错误和重试入口。
   - 所有写操作写入审计。

### 5.5 Git 对象管理流程

Git 对象管理必须对齐原版 Web 后台的常见操作，但使用 macOS 原生列表、表单和详情页呈现。

#### 仓库 / 项目

1. 用户进入 Repositories / Projects。
2. 左侧列表显示名称、Owner/Namespace、可见性、默认分支、更新时间和状态。
3. 用户可搜索、按 Owner/Namespace 筛选、按更新时间/名称排序。
4. 点击条目后右侧显示详情：
   - 基础信息。
   - Clone URL。
   - 默认分支。
   - Issues/PR/MR 状态。
   - 成员和权限摘要。
   - 最近 Pipeline 或活动摘要。
5. 创建仓库/项目时展示 sheet：
   - 名称、路径、Owner/Namespace、可见性、描述、初始化 README。
   - GitLab 额外支持 Group/Project namespace。
6. 删除、归档、可见性变更必须显示确认，确认文案包含服务、项目完整路径和影响范围。

#### 用户 / 成员

1. 用户进入 Users / Members。
2. 列表显示用户名、邮箱、角色、状态、来源、最近活动。
3. 创建用户时收集用户名、邮箱、显示名、临时密码或重置方式。
4. 成员管理需要区分：
   - 实例用户。
   - 组织/团队成员。
   - 项目/组成员。
5. 修改角色时必须显示角色变化，例如 `Reporter -> Maintainer`。
6. 删除/禁用用户前显示影响范围：仓库归属、Issue/MR/PR、Token 和 SSH Key 可能受影响。

#### 组织 / 组 / 团队

1. 用户进入 Organizations / Groups。
2. 列表显示名称、路径、成员数、仓库/项目数。
3. 详情页显示成员、团队、仓库/项目、权限摘要。
4. 新建组织/组时收集名称、路径、描述、可见性。
5. 团队权限编辑必须用明确的权限矩阵，不使用模糊开关。

#### Issue / PR / MR

1. 列表支持按 open/closed/merged、label、assignee、author 筛选。
2. 详情页显示标题、状态、作者、参与者、标签、分支、关联提交和最近评论摘要。
3. 第一版支持打开/关闭、分配人员、改标签和跳转 Web 后台。
4. 评论、Review、Approval 和冲突处理可后续扩展，但详情页必须展示原版 Web 中能判断状态的核心字段。

#### Pipeline / Job

1. GitLab Pipelines 列表显示状态、分支、SHA、触发者、耗时和创建时间。
2. Pipeline 详情显示 Jobs、Stage、状态和失败原因摘要。
3. 第一版支持取消/重试入口和打开后台日志。
4. Runner 管理第一版只做状态展示，避免误操作影响 CI 环境。

### 5.6 npm 安装后管理流程

1. 用户进入 npm 栏。
2. 若 Verdaccio 未安装，显示安装设置和预检。
3. 若已安装但未初始化，提示创建/绑定管理用户或 token。
4. 绑定成功后进入工作台：
   - Overview：状态、URL、版本、存储路径。
   - Packages：包列表、版本详情、删除风险确认。
   - Users：创建、改密、删除、npm smoke test。
   - Policy：访问策略、上游源、保存配置。
   - Proxy：Nginx proxy 写入、测试、reload。
   - Backup：备份、恢复、回滚提示。
5. 配置保存、恢复和 reload 必须走确认和审计。

### 5.7 npm 对象管理流程

#### 包和版本

1. 用户进入 Packages。
2. 列表显示包名、latest、版本数、大小、更新时间。
3. 点击包后展示：
   - README。
   - versions。
   - dist-tags。
   - dependencies。
   - publish/install 命令。
4. 删除包或版本必须二次确认，确认文案包含包名和版本。
5. 如果包元数据来自 storage 解析而非 HTTP API，应在数据来源处标记 `storage metadata`。

#### 用户和认证

1. 用户进入 Users。
2. 展示 htpasswd 状态、可用命令和当前配置中的 auth provider。
3. 创建用户、改密、删除用户复用现有 htpasswd 受控命令。
4. npm smoke test 使用临时包验证 publish/install/require，并在完成后清理。
5. 明文密码不得进入命令字符串、日志和审计。

#### 策略和上游源

1. 用户进入 Policy。
2. 页面显示当前 packages 策略和 uplinks 摘要。
3. 修改前展示生成后的配置预览和影响说明。
4. 保存时必须：
   - 备份 `config.yaml`。
   - 写入新配置。
   - 重启 Verdaccio。
   - 读取状态确认服务恢复。
5. 失败时显示备份路径和恢复建议。

### 5.8 pub 配置流程

1. 用户进入 pub 栏。
2. 输入 hosted URL、包名、Token 环境变量。
3. 点击“生成配置”。
4. app 展示：
   - `pubspec.yaml` dependency_overrides 或 hosted 配置片段。
   - `publish_to` 配置。
   - `dart pub token add` 或环境变量命令。
   - `dart pub publish` / `flutter pub get` 命令。
5. 用户复制配置到项目；后续可从项目部署模块联动。

### 5.9 空状态、错误状态和权限不足

| 场景 | UI 行为 |
| --- | --- |
| 服务未安装 | 显示安装向导，不显示对象管理列表 |
| 服务安装中 | 显示步骤、日志摘要和取消/查看命令入口；禁止重复安装 |
| 服务已安装但未初始化 | 显示初始化步骤和打开后台按钮 |
| Token 缺失 | 显示绑定 token 表单，隐藏需要 API 权限的写操作 |
| Token 权限不足 | 显示缺失权限、重新绑定入口和官方后台跳转 |
| API 网络失败 | 保留最近缓存数据，显示刷新失败横幅 |
| 分页加载失败 | 保留已加载页面，显示“重试加载更多” |
| 写操作失败 | 当前列表不乐观更新，显示失败原因和审计失败记录 |
| 服务停止 | 对象列表置灰，突出 start/restart 操作 |

## 6. API 与数据设计

### 6.1 服务实例

建议新增统一开发服务实例模型：

| 字段 | 说明 |
| --- | --- |
| `id` | 本地 UUID |
| `serverId` | 所属服务器 |
| `kind` | `gitea` / `gitlab` / `verdaccio` / `pubHosted` |
| `displayName` | 展示名称 |
| `baseURL` | 服务 API/Web 根地址 |
| `serviceName` | systemd service name |
| `installPath` | 可选安装路径 |
| `dataPath` | 可选数据路径 |
| `authRef` | Keychain token 引用 |
| `status` | 最近一次探测状态 |
| `version` | 最近一次版本 |
| `lastCheckedAt` | 最近刷新时间 |

### 6.2 API Client

第一版需要三个 client：

- `GiteaAPIClient`
- `GitLabAPIClient`
- `VerdaccioAPIClient`

共同要求：

- 使用 `URLSession`。
- Token 从 Keychain 读取。
- 不在日志中输出 token。
- 支持分页。
- 将 401/403、网络失败、JSON 解析失败、服务不可达映射成可展示错误。
- 写操作统一返回可审计摘要。

### 6.3 API 能力边界

| 服务 | API 基础路径 | Token 类型 | 第一版必须覆盖的 API 对象 | 不用 API 做的事 |
| --- | --- | --- | --- | --- |
| Gitea | `/api/v1` | 用户 access token / 管理员 token | repositories、users、orgs、teams、keys、tokens、issues、pulls、packages | 安装、systemd、配置文件、备份 |
| GitLab | `/api/v4` | Personal access token / admin token | projects、groups、members、branches、tags、variables、deploy keys、issues、merge requests、pipelines、jobs | Omnibus 安装、`gitlab-ctl`、备份命令执行 |
| Verdaccio | Web/API + storage/config | npm auth / htpasswd 用户 | package metadata、package versions、publish/install smoke test、用户和策略管理入口 | systemd、Nginx、storage 备份恢复 |
| pub hosted | Dart pub CLI workflow | hosted repository token env | 配置生成、token 命令、publish/get 命令 | 自托管 pub server 安装 |

实现原则：

- API client 只能访问用户配置的 `baseURL`，不能自动探测内网其他地址。
- API 请求必须带超时，默认 15 秒；列表分页允许逐页加载。
- 所有 API 写操作都必须返回 `before`/`after` 或可审计摘要。
- 401/403 时不重复请求，不自动清除 token，只提示重新绑定。
- 404 要区分“对象不存在”和“baseURL/API path 错误”。
- 5xx 要提示服务端错误，并保留最近一次成功缓存。

### 6.4 Keychain 与本地缓存

| 数据 | 保存位置 | 说明 |
| --- | --- | --- |
| 服务 baseURL、serviceName、installPath、dataPath | SQLite | 非敏感元数据，可用于恢复工作台 |
| API token / admin token | Keychain | 只保存密文条目，SQLite 保存 `authRef` |
| 最近一次列表缓存 | SQLite 或内存缓存 | 用于 API 失败时展示旧数据，应标注缓存时间 |
| 操作审计 | SQLite `remote_change_logs` / operation logs | 必须脱敏 token、密码、secret |
| 临时初始化密码 | 不保存 | 只提示用户到服务官方路径或后台获取 |

Token 绑定流程必须包含：

1. 选择服务实例和 baseURL。
2. 输入 token。
3. 调用 `whoami` / 当前用户 / 权限检查接口。
4. 显示 token 所属用户、权限范围和服务版本。
5. 用户确认后写入 Keychain。
6. 刷新该服务的原生管理首页。

### 6.5 SSH Manager

继续保留并补齐：

- Gitea 安装、状态、服务控制。
- GitLab 安装、预检、状态、服务控制。
- Verdaccio 安装、状态、服务控制、配置、备份恢复。

SSH 负责“服务本身”，API 负责“服务里的对象”。

### 6.6 页面与对象模型建议

| 页面模型 | 关键字段 | 用途 |
| --- | --- | --- |
| `DevelopmentServiceInstance` | `id/serverId/kind/baseURL/serviceName/authRef/status/version` | 表示一个可管理服务实例 |
| `DevelopmentServiceDashboard` | 服务卡片、资源风险、授权状态、最近刷新时间 | Git/npm/pub 顶部摘要 |
| `GitRepositorySummary` | `id/name/fullPath/owner/visibility/defaultBranch/updatedAt` | Gitea/GitLab 仓库列表统一展示 |
| `GitUserSummary` | `id/username/name/email/state/isAdmin/lastActivityAt` | 用户和成员管理 |
| `GitOrganizationSummary` | `id/name/path/memberCount/repositoryCount` | Gitea 组织 / GitLab Group 的统一壳 |
| `GitIssueLikeSummary` | `id/title/state/author/assignee/labels/updatedAt/webURL` | Issue、PR、MR 列表 |
| `GitPipelineSummary` | `id/status/ref/sha/source/duration/createdAt/webURL` | GitLab Pipeline 列表 |
| `NpmPackageSummary` | `name/latestVersion/versionCount/sizeBytes/updatedAt` | Verdaccio 包列表 |
| `PubHostedPlan` | hosted URL、package、token env、生成片段 | pub 配置助手 |

统一模型只能用于列表和通用详情；服务专属字段必须保留在 Gitea/GitLab/Verdaccio 专用模型中，避免为了抽象丢失原版网页里的关键信息。

## 7. 安全边界

- 管理员 token 必须保存到 Keychain，不保存明文到 SQLite。
- Token 绑定前必须显示服务 URL、权限说明和本地保存说明。
- 删除仓库、删除用户、删除包、恢复备份、保存访问策略、reload Nginx 都必须二次确认。
- 远程配置文件修改前必须备份。
- Nginx proxy 写入后必须先 `nginx -t`，测试通过才允许 reload。
- API 失败不能自动改用危险 SSH 数据库修改。
- 审计日志必须记录操作类型、目标、服务类型、状态、时间和脱敏错误信息。

## 8. 分阶段实施

### V1：开发服务三栏和安装后工作台骨架

- 重构 UI 为 Git / npm / pub 三栏。
- Git 栏支持 Gitea/GitLab 共存卡片和详情切换。
- npm 栏迁移 Verdaccio 现有功能。
- pub 栏迁移现有 hosted repository assistant。
- 新增 token 绑定状态和 Keychain 引用模型。
- 安装前/安装后/未绑定 token/ready 四种布局打通。
- 为 Gitea、GitLab、Verdaccio 建立“原版 Web 内容映射”对应的原生页面导航。
- 所有原生管理页先具备空状态、加载状态、错误状态和权限不足状态。

### V1.1：Gitea 原生管理

- Gitea 状态读取和服务控制。
- Gitea API client。
- 仓库、用户、组织/团队、Key、Token、Issue/PR 基础管理。
- Gitea 管理页至少覆盖 Dashboard、Repositories、Organizations、Teams、Users、Keys、Tokens、Issues、Pull Requests、Packages、Admin Overview。

### V1.2：GitLab 原生管理

- GitLab API client。
- Projects、Groups、Members、Variables、Deploy Keys、Issue/MR/Pipeline 基础管理。
- GitLab token 权限检查和错误提示。
- GitLab 管理页至少覆盖 Projects、Groups、Members、Repository、Issues、Merge Requests、Pipelines、Jobs、Variables、Deploy Keys、Packages、Runners Status、Admin Overview。

### V1.3：Verdaccio 原生管理完善

- Verdaccio API/client 能力补齐。
- 包、版本、用户、policy、uplink、备份恢复、proxy 工作台完善。
- Verdaccio 管理页至少覆盖 Package Search/List、Package Detail、Users/Auth、Package Access、Uplinks、Configuration、Storage/Backups、Nginx Proxy、Service Logs。

### V2：深度 DevOps

- Pipeline 日志与重跑。
- Runner 管理。
- GitLab/Gitea Webhook 与项目部署联动。
- 包权限、发布审批、团队协作审计。
- 自托管 pub registry 调研落地。

## 9. 验收标准

- 开发服务页面明确分为 Git / npm / pub。
- Git 栏允许 Gitea 和 GitLab 共存，并能在两者之间切换详情。
- 每个服务都有安装前和安装后两种明显不同的布局。
- 安装后核心管理操作在 app 原生界面完成，Web 后台只作为兜底入口。
- 文档中的“原版网页内容映射”每一行都有对应的原生页面、核心字段、第一版操作或明确后续增强说明。
- Token 绑定、Keychain 保存、API 校验和错误提示流程完整。
- npm 栏保留 Verdaccio 现有安装、状态、用户、包、备份、proxy 能力。
- pub 栏保留 Dart/Flutter hosted repository 配置生成能力。
- 所有远端写操作有确认、审计和脱敏错误信息。
- 开发实施计划能从本文档直接拆出 UI、ViewModel、API Client、SSH Manager、Storage、测试任务。
- 不允许用“内嵌网页”替代已列入第一版的原生高频管理能力；打开 Web 后台只能作为辅助入口。

## 10. 测试与验收场景

| 场景 | 验收方式 |
| --- | --- |
| Git/npm/pub 三栏切换 | UI 测试或手动验收确认三栏状态互不丢失 |
| Gitea/GitLab 共存 | 构造两个服务实例，确认两张卡同时显示且详情可切换 |
| 未安装布局 | 无服务实例时只显示安装向导和预检，不显示对象管理列表 |
| 已安装未绑定 token | 显示服务状态、打开后台和绑定 token，不显示写操作 |
| Token 权限不足 | API 返回 401/403 时显示重新绑定入口，审计不记录 token |
| Gitea 仓库管理 | 列表、详情、创建、删除确认、错误重试 |
| GitLab 项目管理 | 列表、详情、成员、变量、Deploy Key、Pipeline 状态 |
| Verdaccio 包管理 | 包列表、版本详情、安装命令、删除确认 |
| Verdaccio 策略保存 | 配置预览、备份、保存、重启、失败回滚提示 |
| pub 配置生成 | hosted dependency、publish_to、token、publish/get 命令全部生成 |
| API 分页 | 多页列表逐页加载，失败时保留已加载数据 |
| 服务停止 | 对象列表置灰，突出 start/restart 操作 |

## 11. 参考依据

后续实现应优先查阅并对齐以下官方文档和 API：

- Gitea API 与管理能力：<https://docs.gitea.com/development/api-usage>
- GitLab REST API：<https://docs.gitlab.com/api/rest/>
- GitLab Projects API：<https://docs.gitlab.com/api/projects/>
- GitLab Groups API：<https://docs.gitlab.com/api/groups/>
- GitLab Members API：<https://docs.gitlab.com/api/members/>
- GitLab CI/CD Pipelines API：<https://docs.gitlab.com/api/pipelines/>
- Verdaccio 配置与包仓库能力：<https://verdaccio.org/docs/configuration/>
- Verdaccio 认证：<https://verdaccio.org/docs/authentication/>
- Dart custom package repositories：<https://dart.dev/tools/pub/custom-package-repositories>
- Dart publishing packages：<https://dart.dev/tools/pub/publishing>
