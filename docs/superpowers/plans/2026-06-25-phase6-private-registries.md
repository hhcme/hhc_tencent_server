# Phase 6：私有包仓库实施计划

> Phase 6 面向开发者常见的私有包管理需求，优先提供 Verdaccio npm 私有仓库部署和管理。Dart/Flutter pub 私有仓库方案必须在实现前重新验证维护状态和兼容性。

**前置条件:** Phase 5 已完成，部署项目、远程命令、日志和回滚能力稳定。

## 1. 目标

1. 支持 Verdaccio 部署、升级、启动、停止和配置管理。
2. 支持 npm 私有包列表、用户/权限配置、storage 路径和备份。
3. 支持 Nginx 反向代理和 HTTPS 配置协助。
4. 验证 Dart/Flutter pub 私有仓库方案，并确定是否实现。
5. 对包仓库服务提供 Dashboard：状态、端口、版本、磁盘占用、最近日志。

## 2. 非目标

- 不自研 npm registry 协议。
- 不默认暴露公网端口。
- 不自动申请或托管真实 TLS 证书。
- 不在技术验证前承诺 Dart/Flutter pub 仓库可用。
- 不做企业级权限系统。

## 3. 技术约束

- Verdaccio 版本必须明确固定，不使用浮动 pre-release。
- 安装前检查 Node.js、npm/pnpm、systemd、端口占用和磁盘空间。
- 配置改写前必须备份。
- 默认只监听本机或内网地址，由用户明确选择公网暴露。
- 管理 token、htpasswd、密钥类配置必须脱敏。
- Dart/Flutter pub server 方案在进入实现前重新验证维护状态、Dart SDK 兼容性和部署方式。

## 4. 数据模型

```sql
CREATE TABLE registry_instances (
    id TEXT PRIMARY KEY NOT NULL,
    server_id TEXT NOT NULL REFERENCES server_profiles(id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    name TEXT NOT NULL,
    install_path TEXT NOT NULL,
    data_path TEXT NOT NULL,
    listen_host TEXT NOT NULL,
    listen_port INTEGER NOT NULL,
    service_name TEXT,
    version TEXT,
    status TEXT,
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL
);

CREATE TABLE registry_backups (
    id TEXT PRIMARY KEY NOT NULL,
    registry_id TEXT NOT NULL REFERENCES registry_instances(id) ON DELETE CASCADE,
    backup_path TEXT NOT NULL,
    status TEXT NOT NULL,
    size_bytes INTEGER,
    created_at DATETIME NOT NULL
);
```

## 5. 模块设计

- `RegistryInstaller`：安装前检查、安装、升级。
- `VerdaccioManager`：配置、服务、用户、包列表、日志。
- `RegistryBackupService`：备份和恢复。
- `NginxProxyConfigurator`：生成反向代理配置，复用 Phase 4 Nginx 能力。
- `PubRegistryResearchHarness`：验证 Dart/Flutter 私有仓库候选方案。

## 6. UI 范围

- 工作台新增“包仓库”页。
- 安装向导：类型、路径、端口、访问范围、服务名。
- Verdaccio 状态卡：版本、运行状态、端口、storage 占用、最近日志。
- 用户和权限配置入口。
- 包列表和搜索。
- 备份、恢复、升级按钮。
- Dart/Flutter pub 区域先展示技术验证状态，验证完成后再开放安装。

## 7. 实施任务

### Task 1：安装前检查

- [x] 检查 Node.js 和包管理器：已实现 SSH preflight marker 采集和报告解析。
- [x] 检查 systemd：已实现 `systemctl` 可用性检查。
- [x] 检查端口占用：已实现 `ss`/`netstat` 监听端口检测。
- [x] 检查目录权限和磁盘空间：已实现安装目录/data 目录父级可写检查和 `df` 可用空间解析。
- [x] 生成可读的检查报告：已输出 passed/warning/failed、detail 和 remediation。

### Task 2：Verdaccio 安装

- [x] 固定 Verdaccio 稳定版本：当前默认固定为 `5.31.1`，并拒绝 `latest`、pre-release 和非 semver 版本。
- [x] 创建安装目录和数据目录：已生成受控安装命令，创建 system user、安装目录和 data 目录；真实服务器写操作仍需谨慎手动验收。
- [x] 生成配置文件：已生成基础 `config.yaml` 模板，包含 storage、listen、npmjs uplink、package access/publish 和日志配置。
- [x] 创建 systemd service：已生成 systemd unit 模板，包含固定 Verdaccio 版本、工作目录、重启策略和基础 hardening。
- [x] 启动并验证健康检查：已生成 `systemctl daemon-reload`、`enable --now`、`restart` 和 `/-/ping` health check 流程，mock/contract 测试已覆盖；真实服务器手动验收仍未执行。

### Task 3：Verdaccio 管理

- [x] 查看运行状态和日志：已通过 systemd state、Verdaccio version、storage size 和 journal tail 生成状态快照，日志会脱敏。
- [ ] 管理用户和权限配置。
- [x] 列出私有包：已基于 Verdaccio storage 下 package metadata 生成包名、版本数量、latest version、大小和更新时间摘要。
- [ ] 修改上游 registry 配置。
- [x] 保存配置前备份：已支持读取/保存 `config.yaml`，保存前创建 `.hhc-backup-*` 备份并重启服务；真实服务器写操作仍需谨慎验收。

### Task 4：反向代理

- [ ] 复用 Phase 4 Nginx 配置能力。
- [ ] 生成 Verdaccio proxy 配置。
- [ ] 执行 `nginx -t` 后 reload。
- [ ] HTTPS 只提供配置协助，不自动申请证书。

### Task 5：备份与恢复

- [x] 备份 storage 和配置：已生成受控 tar.gz 备份命令，包含 `config.yaml` 和 storage 内容，并返回备份文件大小；真实服务器手动验收仍未执行。
- [ ] 恢复前停止服务并二次确认。
- [ ] 恢复失败时尝试回滚。
- [ ] 记录备份历史：当前返回备份路径和大小，持久化历史仍待接入。

### Task 6：Dart/Flutter pub 方案验证

- [ ] 重新调研候选方案：unpub、其他 pub server、自建代理、私有 Git 依赖。
- [ ] 验证 Dart SDK 和 Flutter 工作流兼容性。
- [ ] 输出技术结论。
- [ ] 只有通过验证才进入实现。

### Task 7：测试

- [x] 安装前检查解析测试。
- [x] 配置生成测试。
- [x] systemd service 模板测试。
- [x] Verdaccio 安装命令和 health check 状态机测试。
- [x] Verdaccio 状态、日志脱敏和配置保存前备份测试。
- [x] 备份归档命令测试。
- [ ] 恢复状态机测试。
- [x] 日志脱敏测试：当前已覆盖 Verdaccio journal status 日志脱敏和安装失败输出脱敏。

### Task 8：手动验收

- [ ] 在测试服务器安装 Verdaccio。
- [ ] npm publish/install 走私有 registry 成功。
- [ ] 服务重启后仍可用。
- [ ] 修改配置前有备份。
- [ ] Nginx proxy 配置测试通过后 reload。
- [ ] 备份和恢复可用。
- [ ] Dart/Flutter pub 方案有明确验证结论。

## 8. 完成标志

1. Verdaccio 安装和管理闭环可用。
2. npm 私有包基础发布和安装可验证。
3. 备份恢复可用。
4. Nginx proxy 配置流程安全。
5. Dart/Flutter pub 仓库方案有结论，未验证通过时不进入实现。
6. 测试和手动验收通过。

## 9. 后续 Phase 边界

- Phase 7 才做云盘、快照、计费、更多云厂商和高级资源操作。
- Windows 版本不在 Phase 6 开始。
