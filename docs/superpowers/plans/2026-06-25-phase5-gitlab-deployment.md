# Phase 5：GitLab 部署实施计划

> Phase 5 提供以 SSH 为核心的 GitLab 项目部署能力。部署必须围绕白名单目录、可审计日志、回滚记录和 webhook 密钥校验设计，不能执行不受控脚本。

**前置条件:** Phase 4 已完成，远程命令、文件管理、环境配置和操作审计稳定。

## 1. 目标

1. 管理部署项目配置：服务器、仓库、分支、部署目录、构建命令、启动命令。
2. 支持手动部署：拉取代码、安装依赖、构建、重启服务、记录日志。
3. 支持回滚：记录上一次 commit 和部署产物状态。
4. 支持 GitLab webhook 自动部署的可选入口。
5. 验证 webhook secret，限制触发分支和项目。
6. 所有部署步骤可视化、可复制日志、可中断。

## 2. 非目标

- 不做通用 CI/CD 平台。
- 不默认安装 GitLab Runner。
- 不做 Kubernetes、Docker Swarm 或复杂编排。
- 不在桌面客户端离线时保证 webhook 自动部署。
- 不支持未配置白名单目录的任意远程脚本执行。

## 3. 技术约束

- 部署目录必须在用户配置的白名单路径内。
- `git reset --hard`、`rm`、服务重启等危险命令必须明确展示。
- 执行部署前记录当前 commit。
- webhook secret 使用常量时间比较。
- webhook 自动部署只在桌面客户端在线且监听启用时工作；需要公网入口时由用户自行配置反向代理或后续中继能力。
- 部署日志不得保存 token、私钥、完整环境变量。

## 4. 数据模型

```sql
CREATE TABLE deployment_projects (
    id TEXT PRIMARY KEY NOT NULL,
    server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    repository_url TEXT NOT NULL,
    branch TEXT NOT NULL,
    deploy_path TEXT NOT NULL,
    build_command TEXT,
    restart_command TEXT,
    health_check_command TEXT,
    webhook_enabled INTEGER NOT NULL DEFAULT 0,
    webhook_secret_ref TEXT,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);

CREATE TABLE deployment_runs (
    id TEXT PRIMARY KEY NOT NULL,
    project_id TEXT NOT NULL REFERENCES deployment_projects(id) ON DELETE CASCADE,
    trigger_type TEXT NOT NULL,
    requested_ref TEXT,
    previous_commit TEXT,
    target_commit TEXT,
    status TEXT NOT NULL,
    started_at DATETIME NOT NULL,
    finished_at DATETIME,
    summary TEXT
);

CREATE TABLE deployment_logs (
    id TEXT PRIMARY KEY NOT NULL,
    run_id TEXT NOT NULL REFERENCES deployment_runs(id) ON DELETE CASCADE,
    step_name TEXT NOT NULL,
    stream TEXT NOT NULL,
    message TEXT NOT NULL,
    created_at DATETIME NOT NULL
);
```

webhook secret 存入 Keychain，SQLite 只保存 `webhook_secret_ref`。

## 5. 模块设计

- `DeploymentProjectStore`：项目配置持久化。
- `DeploymentRunner`：部署状态机和步骤执行。
- `DeploymentLogStore`：日志持久化和脱敏。
- `RollbackService`：回滚到 previous commit。
- `WebhookServer`：可选本地监听、校验 secret、触发部署。
- `DeploymentCommandBuilder`：生成受控命令，不拼接未校验输入。

## 6. UI 范围

- 工作台新增“部署”页。
- 部署项目列表、添加、编辑、删除。（已完成基础 UI）
- 手动部署按钮和部署前预览。（已完成基础 UI 和统一风险确认）
- 部署运行详情：步骤、状态、日志、耗时、失败原因。（已完成基础 UI 和运行中日志自动刷新）
- 回滚按钮：展示 previous commit，先展示统一风险确认，再触发受控 rollback。（已完成基础 UI 和风险确认）
- webhook 设置：启用开关、secret、允许分支、本地 listener 启停和监听地址。（已完成配置、核心校验、listener 基础和 UI 接入）

## 7. 实施任务

### Task 1：部署项目配置

- [x] 实现数据表和 repository：当前已落地 `deployment_projects`、`deployment_runs`、`deployment_logs`，支持项目 upsert/delete/fetch、运行记录 upsert/fetch、日志按时间读取和级联删除。
- [x] 配置基础校验：当前 `DeploymentCommandBuilder` 已校验仓库 URL、分支和单行命令格式，并已接入 Deployments UI 表单。
- [x] 部署目录白名单校验：当前默认仅允许 `/srv`、`/var/www`、`/opt`、`/home` 下的部署目录。
- [x] webhook secret 写入 Keychain，SQLite 只保存 `webhook_secret_ref`；删除/禁用 webhook 时清理 Keychain。

### Task 2：部署状态机

- [x] 定义部署步骤：prepare、git_check、current_commit、clone_or_fetch、checkout、target_commit、build、restart、health check。
- [x] 每一步都记录日志和 exit code。
- [x] 支持取消运行：当前 Runner 在步骤间和 SSH 取消错误处落库为 cancelled。
- [x] 失败时标记 run 状态并停止后续步骤。

### Task 3：Git 操作

- [x] 检查远端是否安装 git。
- [x] clone 或 fetch。
- [x] checkout 目标分支。
- [x] 记录 previous commit。
- [x] 限制 `reset --hard` 只在部署目录内执行。

### Task 4：部署命令执行

- [x] 支持构建、重启服务、health check 命令。
- [x] 命令环境变量脱敏：Runner 保存日志前会脱敏 token、secret、password、Authorization/Bearer、URL credentials 和私钥块。
- [x] 健康检查命令失败时标记部署失败。
- [x] 支持用户复制日志：当前 UI 日志和命令预览支持文本选择复制。
- [x] 运行中自动刷新部署 run/log，日志区域显示 Live 状态。
- [x] 手动部署前复用统一风险确认，展示部署目录、完整命令预览、影响和审计说明。
- [x] 手动部署写入远程变更审计：部署结束后记录 `remote_change_logs`，包含 project target、deploy action、状态、摘要，以及 previous/target commit 快照；失败状态同样记录。

### Task 5：回滚

- [x] 回滚到 previous commit。
- [x] 重新执行构建和重启。
- [x] 回滚也记录独立 run。
- [x] 没有 previous commit 时禁用回滚。
- [x] 回滚前复用统一风险确认，展示目标 commit、命令预览、影响和恢复说明。
- [x] 回滚写入远程变更审计：rollback run 完成或失败都会记录 `remote_change_logs`，包含 project target、rollback action、状态、摘要，以及回滚前后 commit 快照。

### Task 6：Webhook

- [x] 实现可选本地 HTTP listener 基础：当前 `DeploymentWebhookHTTPServer` 使用 `NWListener` 接收 `/webhooks/gitlab`，解析 HTTP 请求，校验方法和路径，并根据 webhook 核心服务结果返回状态。
- [x] 校验 GitLab `X-Gitlab-Token`，使用常量时间比较。
- [x] 过滤项目、分支和事件类型。
- [x] 触发部署前写入操作日志：webhook run 开始和结束都会写入 `operation_logs`，记录 project id、状态和摘要。
- [x] UI 明确说明桌面客户端离线时不会自动部署，并提供本地 listener start/stop、端口和 URL 展示。

### Task 7：测试

- [x] DeploymentProjectStore 测试：已覆盖项目持久化、更新、按服务器过滤、删除级联运行和日志。
- [x] DeploymentRunner 状态机测试：已覆盖成功执行、日志持久化、commit 捕获、步骤失败停止和取消落库。
- [x] Deployment workspace ViewModel 测试：已覆盖项目表单保存、命令预览和 UI 触发手动部署后读取运行日志。
- [x] Deployment 手动运行风险确认测试：已覆盖统一风险模型的 deploy 级别、审计类型、动作和当前草稿命令预览。
- [x] Deployment live log refresh 测试：已覆盖部署运行中自动读取 running run 和 plan 日志。
- [x] Deployment workspace 验收测试：已覆盖不在白名单目录内的项目不会保存，build 失败会停止后续 restart/health check，以及 health check 失败会在工作台显示 failed 状态和 stderr 日志。
- [x] Deployment rollback 风险确认测试：已覆盖统一风险模型的级别、审计类型、动作和命令预览。
- [x] Deployment 远程变更审计测试：`testRunDeploymentPersistsRunLogsFromWorkspace` 覆盖成功部署审计，`testRunDeploymentShowsHealthCheckFailureInWorkspace` 覆盖失败部署审计，`testRollbackDeploymentPersistsRemoteChangeAudit` 覆盖回滚审计。
- [x] 命令构建和目录白名单测试：已覆盖受控 clone/fetch/checkout/build/restart/health check 命令预览、危险路径拒绝、非法 branch/URL/多行命令拒绝。
- [x] rollback 测试：已覆盖回滚 run、previous/target commit 捕获和 `git reset --hard <commit>` 命令。
- [x] webhook secret 常量时间比较测试。
- [x] GitLab webhook 核心测试：已覆盖 secret Keychain 存储、push payload 解析、repo/branch 匹配、错误 token 拒绝和 webhook run 触发。
- [x] GitLab webhook HTTP listener 测试：已覆盖 HTTP 请求解析、header/body 保留和响应格式。
- [x] webhook 操作日志测试：已覆盖 started/succeeded 状态和 project target id。
- [x] 日志脱敏测试：已覆盖 token、password、Authorization/Bearer、URL credentials。
- [x] 真实 SSH 临时部署集成测试：已覆盖远端 `/tmp/hhc-deploy-*` 临时 Git 仓库、existing checkout、fetch/reset、build、health check、commit 捕获和日志落库；默认通过环境变量启用，2026-06-26 已重新用当前代码运行 `testRealDeploymentRunnerDeploysTemporaryRepositoryWhenEnvironmentIsConfigured` 并在真实服务器验证通过。

### Task 8：手动验收

- [x] 添加部署项目：工作台和 repository 测试已覆盖，真实 SSH 集成测试可用环境变量创建临时项目并验证部署。
- [x] 手动部署成功，日志完整：已增加真实 SSH 临时 Git 仓库部署集成测试，并在真实测试服务器上完成当前代码 opt-in 集成验证；生产项目部署仍需按项目配置单独验收。
- [x] 构建失败时状态正确，后续步骤不执行：runner 和工作台 ViewModel 测试已覆盖，真实服务器手动验收仍需谨慎执行。
- [x] health check 失败时部署标记失败：mock/contract 测试和工作台 ViewModel 测试已覆盖，真实服务器手动验收仍需谨慎执行。
- [x] 回滚能回到 previous commit：mock/contract 测试已覆盖，真实服务器手动回滚仍需谨慎验收。
- [x] webhook secret 错误时拒绝触发：核心 service 测试已覆盖。
- [x] 不在白名单目录内的部署配置被拒绝：命令构建测试和工作台 ViewModel 测试已覆盖。

## 8. 完成标志

1. 手动部署闭环可用。
2. 部署日志可审计且不泄露敏感信息。
3. 回滚闭环可用。
4. webhook 可选启用并正确校验 secret。
5. 所有危险命令受目录白名单约束。
6. 测试和手动验收通过。

## 9. 后续 Phase 边界

- Phase 6 才把部署能力用于私有包仓库安装。
- Phase 7 才考虑云侧负载均衡、快照和发布前云资源备份。
