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
- 部署项目列表、添加、编辑、删除。
- 手动部署按钮和部署前预览。
- 部署运行详情：步骤、状态、实时日志、耗时、失败原因。
- 回滚按钮：展示 previous commit 和风险说明。
- webhook 设置：启用开关、本地监听地址、secret、允许分支。

## 7. 实施任务

### Task 1：部署项目配置

- [x] 实现数据表和 repository：当前已落地 `deployment_projects`、`deployment_runs`、`deployment_logs`，支持项目 upsert/delete/fetch、运行记录 upsert/fetch、日志按时间读取和级联删除。
- [x] 配置基础校验：当前 `DeploymentCommandBuilder` 已校验仓库 URL、分支和单行命令格式；UI 表单接入待后续完成。
- [x] 部署目录白名单校验：当前默认仅允许 `/srv`、`/var/www`、`/opt`、`/home` 下的部署目录。
- [ ] webhook secret 写入 Keychain。

### Task 2：部署状态机

- [ ] 定义部署步骤：prepare、fetch、checkout、install、build、restart、health check。
- [ ] 每一步都记录日志和 exit code。
- [ ] 支持取消运行。
- [ ] 失败时标记 run 状态并停止后续步骤。

### Task 3：Git 操作

- [ ] 检查远端是否安装 git。
- [ ] clone 或 fetch。
- [ ] checkout 目标分支。
- [ ] 记录 previous commit。
- [ ] 限制 `reset --hard` 只在部署目录内执行。

### Task 4：部署命令执行

- [ ] 支持安装依赖、构建、重启服务命令。
- [ ] 命令环境变量脱敏。
- [ ] 健康检查命令失败时标记部署失败。
- [ ] 支持用户复制日志。

### Task 5：回滚

- [ ] 回滚到 previous commit。
- [ ] 重新执行构建和重启。
- [ ] 回滚也记录独立 run。
- [ ] 没有 previous commit 时禁用回滚。

### Task 6：Webhook

- [ ] 实现可选本地 HTTP listener。
- [ ] 校验 GitLab `X-Gitlab-Token`。
- [ ] 过滤项目、分支和事件类型。
- [ ] 触发部署前写入操作日志。
- [ ] UI 明确说明桌面客户端离线时不会自动部署。

### Task 7：测试

- [x] DeploymentProjectStore 测试：已覆盖项目持久化、更新、按服务器过滤、删除级联运行和日志。
- [ ] DeploymentRunner 状态机测试。
- [x] 命令构建和目录白名单测试：已覆盖受控 clone/fetch/checkout/build/restart/health check 命令预览、危险路径拒绝、非法 branch/URL/多行命令拒绝。
- [ ] webhook secret 常量时间比较测试。
- [ ] 日志脱敏测试。当前 deployment logs 仅完成持久化顺序测试，脱敏在 Runner/LogStore 阶段接入。

### Task 8：手动验收

- [ ] 添加部署项目。
- [ ] 手动部署成功，日志完整。
- [ ] 构建失败时状态正确，后续步骤不执行。
- [ ] health check 失败时部署标记失败。
- [ ] 回滚能回到 previous commit。
- [ ] webhook secret 错误时拒绝触发。
- [ ] 不在白名单目录内的部署配置被拒绝。

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
