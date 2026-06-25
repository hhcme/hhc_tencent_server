# Phase 4：安全组 + 环境配置实施计划

> Phase 4 开始进入会修改远端环境和云网络边界的能力。所有写操作必须有能力探测、权限检查、预览、二次确认、操作日志和失败恢复说明。

**前置条件:** Phase 3 已完成，Dashboard、能力探测和文件管理器稳定。

## 1. 目标

1. 通过云 provider adapter 管理安全组查看和有限写操作。
2. 实现 systemd 服务查看、启动、停止、重启和日志查看。
3. 实现 Nginx 配置查看、测试、启用、回滚。
4. 实现防火墙规则查看和有限管理。
5. 实现 Cron 任务查看、添加、禁用、删除。
6. 实现环境变量文件管理和变更记录。
7. 建立远程变更审计日志和危险操作确认框架。

## 2. 非目标

- 不做 GitLab 部署。
- 不做私有包仓库。
- 不做跨云高级资源管理。
- 不尝试覆盖所有 Linux 发行版，只对已探测能力启用功能。
- 不在没有明确回滚路径时执行复杂配置改写。

## 3. 技术约束

- 安全组写操作必须基于 provider capability 和账号权限展示。
- systemd/Nginx/firewall/cron 都必须通过 adapter 或 capability model，不写死单一发行版。
- 修改配置前必须读取当前内容并保存本地变更记录。
- Nginx 配置保存后必须先执行测试命令，测试通过才 reload。
- 防火墙规则不能默认开放危险端口范围。
- 所有远程写操作必须有 timeout、stderr 捕获和操作日志。

## 4. 数据模型

新增表：

```sql
CREATE TABLE remote_change_logs (
    id TEXT PRIMARY KEY NOT NULL,
    server_id TEXT REFERENCES server_profiles(id) ON DELETE SET NULL,
    provider_id TEXT,
    target_type TEXT NOT NULL,
    target_id TEXT,
    action TEXT NOT NULL,
    before_snapshot TEXT,
    after_snapshot TEXT,
    status TEXT NOT NULL,
    message TEXT,
    created_at DATETIME NOT NULL
);

CREATE TABLE environment_profiles (
    id TEXT PRIMARY KEY NOT NULL,
    server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    last_loaded_at DATETIME,
    UNIQUE(server_id, file_path)
);
```

## 5. 模块设计

- `SecurityGroupService`：云安全组读取、规则 diff、写操作提交。
- `SystemdServiceManager`：服务列表、状态、start/stop/restart、journal 日志。
- `NginxConfigManager`：站点配置读取、编辑、测试、reload、回滚。
- `FirewallAdapter`：ufw/firewalld/iptables 能力探测和有限操作。
- `CronManager`：crontab 读取、编辑、禁用、恢复。
- `EnvironmentConfigManager`：`.env`、shell profile、systemd env file 管理。
- `RemoteChangeLogStore`：所有写操作审计。

## 6. UI 范围

- 工作台新增“安全组”页，仅云实例关联且账号有能力时启用。
- 工作台新增“服务”页：systemd 服务列表、状态、操作按钮、日志。
- 工作台新增“Nginx”页：配置文件列表、编辑、测试、reload、回滚。
- 工作台新增“防火墙”页：展示当前探测到的防火墙后端和规则。
- 工作台新增“Cron”页：任务列表、启用/禁用、编辑。
- 工作台新增“环境变量”页：常用 env 文件管理。
- 所有危险操作使用统一确认 sheet，展示命令、目标和影响范围。

## 7. 实施任务

### Task 1：危险操作框架

- [ ] 定义 `RemoteOperationRisk` 和确认模型。
- [ ] 所有写操作写入 `remote_change_logs`。
- [ ] 操作失败时保存 stderr 和上下文。
- [ ] UI 展示操作预览和风险说明。

### Task 2：安全组

- [ ] 扩展 CloudProviderAdapter 支持安全组读取。
- [ ] 腾讯云安全组规则读取。
- [ ] 规则 diff 和预览。
- [ ] 有限写操作：新增/删除单条规则。
- [ ] 权限不足时明确提示。

### Task 3：systemd

- [x] 探测 systemd 可用性：`systemctl` 不存在时返回明确错误，Dashboard 也会探测 systemd capability。
- [x] 服务列表和状态解析：解析 unit、load、active、sub 和 description，并优先显示 active 服务。
- [x] start/stop/restart/reload 操作：限制为简单 `.service` unit 名，UI 操作前弹出确认。
- [x] journal 日志读取：支持读取选中 service 的最近 journal。
- [x] 非 systemd 系统隐藏或降级：当前以错误状态降级展示，不影响 SSH 其他功能。

### Task 4：Nginx

- [ ] 探测 Nginx 安装和配置路径。
- [ ] 读取站点配置。
- [ ] 编辑前备份。
- [ ] 保存后执行 `nginx -t`。
- [ ] 测试通过才 reload，失败自动恢复备份。

### Task 5：防火墙

- [ ] 探测 ufw/firewalld/iptables。
- [ ] 展示规则。
- [ ] 支持有限新增/删除规则。
- [ ] 高风险规则二次确认。

### Task 6：Cron 与环境变量

- [x] 读取用户 crontab。
- [x] 添加、禁用、删除任务：当前支持用户级 crontab 的添加、启用、禁用和删除，写入前创建远端备份。
- [ ] 管理常用 `.env` 文件和 systemd env file。
- [ ] 保存前创建备份。

### Task 7：测试

- [x] 命令解析 fixture 测试：已覆盖 systemd service 列表解析、unit 名校验、Cron 解析和 crontab 写入内容。
- [ ] 风险确认 ViewModel 测试。
- [ ] Nginx 配置测试/回滚逻辑测试。
- [ ] Firewall adapter 能力探测测试。
- [ ] RemoteChangeLogStore 测试。

### Task 8：手动验收

- [ ] 无云账号时安全组页不可用但 SSH 功能正常。
- [ ] 腾讯云安全组可读取。
- [ ] 新增安全组规则前显示预览和确认。
- [ ] systemd 服务可以查看和重启。当前真实服务器只读查看已验收，重启操作由 mock/contract 测试覆盖，真实写操作待谨慎手动验收。
- [ ] Nginx 配置测试失败时不 reload。
- [ ] Cron 任务可禁用并恢复。当前真实服务器只读 crontab 已验收，禁用/恢复写操作由 mock/contract 测试覆盖，真实写操作待谨慎手动验收。
- [ ] 所有写操作可在操作日志中查到。

## 8. 完成标志

1. 云安全组基础读写可用。
2. systemd、Nginx、防火墙、Cron、环境变量能力基于探测启用。
3. 所有远程写操作有确认和审计。
4. Nginx 等配置类操作有备份和回滚。
5. 测试和手动验收通过。

## 9. 后续 Phase 边界

- Phase 5 才做 GitLab 部署。
- Phase 6 才做包仓库安装。
- Phase 7 才扩展快照、云盘、计费和更多云厂商高级能力。
