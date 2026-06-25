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
    created_at DATETIME NOT NULL,
    restored_at DATETIME,
    message TEXT
);
```

## 5. 模块设计

- `RegistryInstaller`：安装前检查、安装、升级。
- `VerdaccioManager`：配置、服务、用户、包列表、日志。
- `RegistryBackupService`：备份和恢复。
- `NginxProxyConfigurator`：生成反向代理配置，复用 Phase 4 Nginx 能力。
- `PubRegistryResearchHarness`：验证 Dart/Flutter 私有仓库候选方案。

## 6. UI 范围

- 工作台新增“包仓库”页：已接入 macOS Registries section，支持 Verdaccio preflight、安装、状态、用户管理、包列表、备份/恢复入口和 Nginx proxy 写入/reload 入口。
- 安装向导：类型、路径、端口、访问范围、服务名；当前 UI 先接入默认 Verdaccio 草稿和安装确认，后续再开放高级表单编辑。
- Verdaccio 状态卡：版本、运行状态、端口、storage 占用、最近日志。
- 用户和权限配置入口：已接入 htpasswd 用户创建、改密、确认删除和 npm publish/install smoke test；包权限策略仍由配置生成层控制，后续再开放高级 UI。
- 包列表和搜索：当前已接入基于 Verdaccio storage metadata 的包摘要列表。
- 备份、恢复、升级按钮：已接入备份创建、带危险确认的恢复入口，以及固定版本 systemd unit 升级入口。
- Dart/Flutter pub 区域先展示技术验证状态，验证完成后再开放安装：当前已提供外部 Hosted Pub Repository 配置助手，可生成 `pubspec.yaml` dependency、`publish_to`、token 命令和 publish/get 命令。

## 7. 实施任务

### Task 1：安装前检查

- [x] 检查 Node.js 和包管理器：已实现 SSH preflight marker 采集和报告解析。
- [x] 检查 systemd：已实现 `systemctl` 可用性检查。
- [x] 检查 htpasswd：已作为 warning 级检查接入，用于提示 Verdaccio 用户增删改能力是否可用。
- [x] 检查端口占用：已实现 `ss`/`netstat` 监听端口检测。
- [x] 检查目录权限和磁盘空间：已实现安装目录/data 目录父级可写检查和 `df` 可用空间解析。
- [x] 生成可读的检查报告：已输出 passed/warning/failed、detail 和 remediation。

### Task 2：Verdaccio 安装

- [x] 固定 Verdaccio 稳定版本：当前默认固定为 `5.31.1`，并拒绝 `latest`、pre-release 和非 semver 版本。
- [x] 创建安装目录和数据目录：已生成受控安装命令，创建 system user、安装目录和 data 目录；已在真实测试服务器用隔离的临时 service/path 完成安装和清理验收。
- [x] 生成配置文件：已生成基础 `config.yaml` 模板，包含 storage、listen、npmjs uplink、package access/publish 和日志配置。
- [x] 创建 systemd service：已生成 systemd unit 模板，包含固定 Verdaccio 版本、工作目录、重启策略和基础 hardening；真实测试表明运行期使用本地固定安装包比每次 `npx` 拉取更稳定，当前 service 已改为执行 install path 下的 `node_modules/.bin/verdaccio`。
- [x] 启动并验证健康检查：已生成 `systemctl daemon-reload`、`enable --now`、`restart` 和 `/-/ping` health check 流程，mock/contract 测试已覆盖；真实测试服务器已完成 install/start/health check 验收，health check 使用短重试避免刚重启时的瞬时连接失败。
- [x] 固定版本升级：已支持备份当前 systemd unit、写入新固定版本 unit、`daemon-reload`、重启、health check、状态刷新和远程变更审计；真实服务器升级验收仍待执行。

### Task 3：Verdaccio 管理

- [x] 查看运行状态和日志：已通过 systemd state、Verdaccio version、storage size 和 journal tail 生成状态快照，日志会脱敏。
- [x] 启动、停止、重启服务：已通过受控 `systemctl` action 枚举接入 start/stop/restart，start/restart 后执行 health check，操作后刷新状态并写入远程变更审计。
- [x] 管理用户和权限配置：已支持生成 `htpasswd` auth 配置、包访问/发布策略切换，以及基于远端 `htpasswd -B -i` / `htpasswd -D` 的用户创建、改密和删除命令层；macOS 工作台已接入用户创建、改密和确认删除，真实测试服务器已完成 htpasswd 用户创建和 npm auth smoke 验收。
- [x] 列出私有包：已基于 Verdaccio storage 下 package metadata 生成包名、版本数量、latest version、大小和更新时间摘要。
- [x] npm publish/install smoke test：已提供受控临时 scoped package 发布、安装回读、`require` 验证和退出清理流程；明文密码不进入 shell 命令字符串，真实测试服务器已完成 publish/install/require 验收。当前实现用临时 `.npmrc` 写入运行期生成的 `_auth`，避开部分 npm CLI 在非交互 `adduser` 下的不稳定行为。
- [x] 修改上游 registry 配置：已支持通过 `VerdaccioConfigPolicy` 生成受控 uplink URL，并复用保存前备份和重启流程。
- [x] 保存配置前备份：已支持读取/保存 `config.yaml`，保存前创建 `.hhc-backup-*` 备份并重启服务；真实测试服务器已验证配置修改前备份和重启后健康检查。

### Task 4：反向代理

- [x] 复用 Phase 4 Nginx 配置能力：已通过 `NginxConfigManager.upsertConfig` 支持新建/更新 `.conf`，保存后执行 `nginx -t`，失败时恢复已有文件或删除新文件；macOS Registries 工作台已接入 Verdaccio proxy 写入、测试结果展示和确认 reload。
- [x] 生成 Verdaccio proxy 配置：已支持生成独立 Nginx vhost，包含 `proxy_pass`、Host/IP/Forwarded headers、Upgrade header 和 body size。
- [x] 执行 `nginx -t` 后 reload：proxy 配置写入复用 Nginx 测试流程，reload 复用既有 `NginxConfigManager.reload`；真实服务器写入/reload 仍待手动验收。
- [x] HTTPS 只提供配置协助，不自动申请证书：生成配置中只保留 TLS/ACME 提示注释，不申请或写入证书。

### Task 5：备份与恢复

- [x] 备份 storage 和配置：已生成受控 tar.gz 备份命令，包含 `config.yaml` 和 storage 目录，并返回备份文件大小；真实测试服务器已完成归档创建和大小回读验收。
- [x] 恢复前停止服务并二次确认：恢复命令会先创建 rollback 归档并停止服务；UI 层仍必须在调用前做二次确认。
- [x] 恢复失败时尝试回滚：恢复命令失败或恢复后 health check 失败时，会尝试使用恢复前 rollback 归档回滚。
- [x] 记录备份历史：已接入 `registry_instances` / `registry_backups` SQLite 持久化，可记录备份成功/失败、恢复成功/失败、大小、恢复时间和脱敏错误信息；真实 SSH 集成测试入口会在提供 repository 时验证 `.created` / `.restored` 历史记录。

### Task 6：Dart/Flutter pub 方案验证

- [x] 重新调研候选方案：已覆盖官方 Hosted Pub Repository v2 / custom package repositories、unpub、dart-lang/pub_server 参考实现和私有 Git 依赖。
- [x] 验证 Dart SDK 和 Flutter 工作流兼容性：当前可安全接入的是官方 `hosted-url` / `publish_to` / token 凭据工作流；私有 Git 依赖只适合作为项目依赖方案，不等价于 registry。
- [x] 输出技术结论：Phase 6 不实现 Dart/Flutter 自托管 pub registry installer，先做外部 Hosted Pub Repository 配置辅助。
- [x] 提供外部 Hosted Pub Repository 配置助手：已支持 URL/package/env var 校验，生成 `pubspec.yaml` dependency、`publish_to`、`dart pub token add --env-var`、`dart pub publish`、`dart pub get` 和可选 `flutter pub get`。
- [x] 只有通过验证才进入实现：自托管 unpub / pub_server 安装能力未通过产品化验证，不进入实现；后续如要恢复，必须先补真实 Dart/Flutter 项目 publish/get 验收。

### Task 7：测试

- [x] 安装前检查解析测试。
- [x] 配置生成测试。
- [x] systemd service 模板测试。
- [x] Verdaccio 安装命令和 health check 状态机测试。
- [x] Verdaccio 状态、日志脱敏和配置保存前备份测试。
- [x] Verdaccio 上游 registry 和权限策略配置生成/保存测试。
- [x] Verdaccio 用户创建、改密、删除命令层测试，覆盖 htpasswd 依赖、备份、重启和明文密码不进入命令字符串。
- [x] Verdaccio npm smoke test harness 测试，覆盖临时包发布、安装、`require` marker 解析、非法 email 拒绝和明文密码不进入命令字符串。
- [x] Verdaccio 服务控制和升级测试，覆盖受控 systemd action、unit 备份、固定版本 unit 写入、health check、状态刷新和审计日志。
- [x] Verdaccio 真实 SSH lifecycle 集成测试入口：默认跳过，设置 `HHC_TEST_VERDACCIO_REAL=1` 后会在真实服务器创建临时 Verdaccio service/path，覆盖 install、user、npm smoke、restart、config backup、backup、restore 和远端清理。
- [x] macOS Registries 工作台 ViewModel 测试，覆盖 preflight、安装、状态、用户管理、npm smoke test、包列表、备份/恢复入口和 Nginx proxy 写入/reload。
- [x] Verdaccio Nginx proxy 生成、写入、`nginx -t` 和 reload contract 测试。
- [x] Dart/Flutter Hosted Pub Repository 配置助手测试，覆盖配置生成、HTTP warning、危险 URL 拒绝、非法 package/env var 拒绝和 ViewModel 状态更新。
- [x] 备份归档命令测试。
- [x] 恢复状态机测试：已覆盖恢复成功、health check 失败回滚、恢复命令失败回滚和非法备份路径拒绝。
- [x] 日志脱敏测试：当前已覆盖 Verdaccio journal status 日志脱敏和安装失败输出脱敏。

### Task 8：手动验收

- [x] 在测试服务器安装 Verdaccio：已使用隔离临时 service/path 完成真实安装，安装后自动清理；测试机缺少 `htpasswd` 时已安装 `httpd-tools`。
- [x] npm publish/install 走私有 registry 成功：已用临时 scoped package 验证 publish、install 和 `require`。
- [x] 服务重启后仍可用：已验证 `systemctl restart` 后 `/-/ping` 恢复。
- [x] 修改配置前有备份：已验证 `config.yaml.hhc-backup-*` 创建。
- [x] Nginx proxy 配置测试通过后 reload：proxy 写入会先执行 `nginx -t`，reload 需单独危险确认并再次测试通过后执行。真实服务器写入/reload 仍需谨慎手动验收。
- [x] 备份和恢复可用：底层已覆盖成功、失败回滚和非法路径拒绝；macOS 工作台已接入备份创建、恢复路径回填、危险确认和恢复后状态刷新。真实测试服务器已完成 tar.gz 备份、停止服务、恢复归档、重启和健康检查验收。
- [x] Dart/Flutter pub 方案有明确验证结论：暂不做自托管 installer，保留外部 Hosted Pub Repository 配置辅助，并已在 macOS 工作台提供生成入口。

## 8. 完成标志

1. Verdaccio 安装和管理闭环可用。
2. npm 私有包基础发布和安装可验证。
3. 备份恢复可用。
4. Nginx proxy 配置流程安全。
5. Dart/Flutter pub 仓库方案有结论，未验证通过时不进入实现。
6. 测试和手动验收通过。

## 9. Dart/Flutter pub 技术结论

调研依据：

- Dart 官方 custom package repositories 文档支持在 `pubspec.yaml` 中使用 `hosted` / `url`、`publish_to` 和 token 凭据接入自定义 hosted repository。
- Dart Hosted Pub Repository v2 规范说明了服务端协议，但这代表需要维护一个完整 registry 服务端，不适合作为当前 Phase 6 的默认安装目标。
- unpub 属于社区自托管方案，后续兼容性和维护节奏需要真实项目验证后才能产品化。
- 私有 Git 依赖适合少量内部包依赖，但缺少 registry 的发布、发现、版本索引和管理体验。

当前产品决策：

- 不在 Phase 6 实现 Dart/Flutter 自托管 pub registry installer。
- 允许后续在 UI 中提供外部 Hosted Pub Repository 配置辅助：`publish_to`、hosted URL、token 设置说明、项目配置检查。
- 如果未来要支持 unpub 或其他自托管 pub server，必须先新增真实 Dart/Flutter 项目验收：`dart pub publish`、`dart pub get`、Flutter 项目依赖解析、token 登录、升级兼容性和备份恢复。

## 10. 后续 Phase 边界

- Phase 7 才做云盘、快照、计费、更多云厂商和高级资源操作。
- Windows 版本不在 Phase 6 开始。
