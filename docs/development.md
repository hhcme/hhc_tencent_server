# 开发与验证说明

本文记录当前 macOS 原生版本的本地开发、测试和真实 SSH 验证方式。不要把真实服务器地址、用户名、私钥路径或密码写入仓库。

## 构建

```sh
xcodebuild \
  -project HHCServerManager.xcodeproj \
  -scheme HHCServerManager \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 默认测试

默认测试不依赖真实服务器。真实 SSH 集成测试在未配置环境变量时会自动跳过。

推荐本地直接运行与 GitHub Actions 共用的 CI 脚本：

```sh
scripts/ci.sh
```

GitHub Actions workflow 位于 `.github/workflows/ci.yml`，会在 `main` 分支 push 和 pull request 时运行同一套 macOS 构建测试。

`scripts/ci.sh` 默认关闭 Xcode 并行测试 worker，减少 macOS app-hosted tests 在 Dock 中同时出现多份测试宿主 App 图标。需要临时提速时可以手动运行底层 `xcodebuild test` 并打开并行测试。

如果需要展开调试，可以直接运行底层 `xcodebuild test` 命令：

```sh
xcodebuild \
  -project HHCServerManager.xcodeproj \
  -scheme HHCServerManager \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

当前覆盖：

- SQLite repository：服务器 CRUD、trusted host key 级联删除、命令历史、操作日志、远程变更审计日志、云账号元数据、云实例关联、云盘、快照、计费状态、私有仓库实例和备份历史。
- Deployment persistence：部署项目、部署运行记录和部署日志的 SQLite 持久化、更新、按服务器/项目/run 查询和级联删除。
- KeychainService：SSH password、private key、云 SecretId/SecretKey 写入、读取、覆盖、删除。
- ServerManagementService / CloudAccountService：服务器与云账号创建、更新、删除、凭据清理。
- Cloud provider foundation：adapter 协议、provider registry、capability 查询、统一错误、超时包装。
- TencentCloudAdapter：TC3 签名、Region 查询、CVM DescribeInstances 查询、CBS DescribeDisks / DescribeSnapshots 查询、CBS CreateSnapshot / DeleteSnapshots / AttachDisks / DetachDisks 写操作、基础计费/到期字段提取、Cloud Monitor CPU 查询、VPC 安全组/规则查询、分页、provider 错误映射、mock transport fixture 测试。
- AlibabaCloudAdapter：阿里云 OpenAPI V3 `ACS3-HMAC-SHA256` 签名、ECS `DescribeRegions` / `DescribeInstances` 只读查询、分页、公网/私网 IP、规格、状态、VPC、计费和到期字段映射、mock transport fixture 测试。
- HuaweiCloudAdapter：华为云 AK/SK `SDK-HMAC-SHA256` 签名、IAM project 发现、ECS `cloudservers/detail` 只读查询、分页、公网/私网 IP、规格、可用区、状态和计费元数据映射、mock transport fixture 测试。
- CloudSecurityGroupService：基于已关联云实例读取账号、地域和 Keychain 云凭据，按 provider capability 加载安全组列表和选中安全组规则。
- CloudInstanceSyncService：读取 Keychain 云凭据、同步云实例/云盘/快照/计费状态 upsert、保留已有 SSH 关联、从云实例创建 SSH profile、关联/解除关联，并提供统一云资源搜索入口。
- CloudImportSheet / CloudImportViewModel：支持腾讯云、阿里云、华为云账号验证后保存、加载可用地域或项目、同步实例、选择实例并导入为 SSH profile。
- CloudResourceCenterSheet / CloudResourceCenterViewModel：按账号/地域同步云实例、云盘、快照和计费状态，支持跨资源搜索、类型/状态过滤、provider capability matrix 展示和资源详情查看。
- Cloud snapshot actions：腾讯云 CBS `CreateSnapshot` / `DeleteSnapshots` 已接入云资源中心，磁盘可创建快照，`NORMAL` 快照可删除；所有操作需要风险确认，并写入 `remote_change_logs` 云端变更审计。
- Cloud disk attachment actions：腾讯云 CBS `AttachDisks` / `DetachDisks` 已接入云资源中心，`UNATTACHED`/`DETACHED` 云盘可输入目标实例 ID 后挂载，`ATTACHED` 云盘可卸载；所有操作需要风险确认，执行后本地缓存进入 `ATTACHING`/`DETACHING`，并写入 `remote_change_logs` 云端变更审计。
- DashboardService：通过 SSH 探测 OS、kernel、`/proc`、systemd、sftp，并采集负载、内存、根磁盘、CPU 核心数、网络收发总量和进程摘要基础指标；单项指标失败会返回 warning，不阻断整个快照。
- RemoteFileService：通过 SSH/OpenSSH 工具链进行文件管理 bootstrap，支持目录列表、单文件上传/下载、重命名、chmod 权限修改、可恢复移入远端回收目录、轻量 UTF-8 文本读写、保存前备份和另存为，并解析文件类型、大小、权限、修改时间和路径。
- SystemdServiceManager：通过 SSH/systemctl 读取 systemd service 列表，解析 load/active/sub/description，支持严格 `.service` unit 名校验后的 start/stop/restart/reload，以及 journalctl 最近日志读取。
- CronManager：通过 SSH/crontab 读取用户级 crontab，解析启用/禁用任务，支持添加、启用、禁用和删除任务；写入前会把当前 crontab 备份到远端 `~/.hhc-crontab-backup-*`。
- NginxConfigManager：通过 SSH 动态探测 Nginx 配置路径，优先读取 `nginx -V` 的 `--conf-path` / `--prefix`，并兼容 `/etc/nginx`、`/usr/local/nginx/conf`、`/opt/nginx/conf` 等常见目录；支持配置文件列表、UTF-8 配置读取、保存前远端备份、保存后 `nginx -t`、测试失败自动恢复备份和确认后 reload。
- FirewallManager：通过 SSH 只读探测 firewalld、ufw、nftables、iptables 后端，读取后端状态和规则输出；firewalld 安装但未运行时会展示 `not running`，不阻断其他功能。
- EnvironmentFileManager：通过 SSH 受限发现常见 `.env`、`/etc/default`、`/etc/sysconfig` 和 systemd drop-in 环境文件；支持 256 KiB 内 UTF-8 内容读取、保存前远端备份和临时文件替换。
- RemoteOperationRisk：为远程文件删除/权限修改、systemd、Cron、Nginx、Environment 写操作生成统一风险级别、目标、命令预览、影响范围和恢复说明，供确认 UI 和后续写操作复用。
- AddServerViewModel：表单校验。
- ServerWorkspaceViewModel：连接状态、主机指纹确认、smoke test、单条命令执行与取消、本次会话输出历史、stdout/stderr 分开展示、失败摘要、持久化命令元数据历史、历史命令重跑、Dashboard 手动/自动刷新、远程目录浏览、排队单文件上传/下载、当前传输取消、待传队列清空、传输任务状态记录、重命名、chmod 权限修改、可恢复移入回收目录、轻量文本编辑、腾讯云安全组只读查看、systemd 服务管理、Cron 管理、Nginx 配置管理、Firewall 只读状态流和 Environment 文件管理。
- SSHIntegrationTests：通过环境变量启用，默认跳过。

## 真实 SSH 手动验证

本地可以用系统 OpenSSH 先验证服务器是否可达。以下命令只作为示例，实际值通过本地环境变量或 shell 临时输入提供，不提交到仓库。

```sh
tmpdir=$(mktemp -d /tmp/hhc-ssh-smoke.XXXXXX)
known_hosts="$tmpdir/known_hosts"

ssh-keyscan -T 5 -p "$HHC_TEST_SSH_PORT" "$HHC_TEST_SSH_HOST" > "$known_hosts" 2>/dev/null
chmod 600 "$known_hosts"
ssh-keygen -l -f "$known_hosts"

ssh \
  -i "$HHC_TEST_SSH_PRIVATE_KEY" \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$known_hosts" \
  "$HHC_TEST_SSH_USER@$HHC_TEST_SSH_HOST" \
  'printf hhc-ssh-ok'

rm -rf "$tmpdir"
```

期望输出包含：

```text
hhc-ssh-ok
```

## 真实 SSH 集成测试环境变量

真实集成测试读取以下环境变量：

```sh
export HHC_TEST_SSH_HOST="example.com"
export HHC_TEST_SSH_PORT="22"
export HHC_TEST_SSH_USER="root"
export HHC_TEST_SSH_PRIVATE_KEY="$HOME/.ssh/id_ed25519"
export HHC_TEST_SSH_PASSPHRASE=""
```

注意：当前 Xcode app-hosted test 通过 `xcodebuild test` 启动时，shell 环境变量可能不会稳定传入测试进程。因此真实 SSH 仍以手动 smoke test 作为可靠验收入口；集成测试保留为后续 CI/scheme 配置完善后的自动化入口。

## 当前实现边界

- 当前 SSH 适配层是 bootstrap OpenSSH adapter，用于先打通真实服务器、主机指纹信任、smoke test、单条命令执行和取消；取消运行中命令时会 terminate 对应 OpenSSH 子进程。
- 命令面板只持久化 command、exit code、duration 和 created at；stdout/stderr 默认只保留在本次工作台会话中，分开展示但不写入 SQLite，避免把敏感输出落盘。
- Dashboard 当前为 Phase 3 bootstrap：指标通过 SSH 即时采集，支持手动刷新和自动刷新；已关联腾讯云 CVM 时会通过 Cloud Monitor `GetMonitorData` 拉取 Cloud CPU 指标并标记来源为 Cloud API；单项可选指标失败会以 warning 降级展示，尚未写入 `dashboard_snapshots` 缓存表，更多云监控指标仍待扩展。
- 文件管理当前为 bootstrap：目录浏览通过 SSH `find` 命令实现，上传/下载通过本机 OpenSSH `scp` 实现排队单文件传输，并在 UI 中记录最近传输任务的 pending/running/succeeded/failed/cancelled 状态；当前运行中的传输可取消，待传队列可清空。重命名使用 `mv -n`，权限修改使用经过八进制校验的 `chmod`，删除入口会二次确认并移动到 `~/.hhc-server-manager-trash`；小型 UTF-8 文本文件可通过 SSH/base64 读取和保存，限制 256 KiB，保存前会生成 `*.hhc-backup-*` 备份，另存为默认不覆盖已有文件，并通过临时文件替换。已在真实 Linux 服务器上验证 `sftp` 命令存在以及 scp 上传/下载往返可用；尚未完成 SwiftNIO SSH/libssh2 正式 SFTP 替换、进度百分比、批量/并发传输和队列持久化。
- Services 当前为 Phase 4 bootstrap：systemd 服务列表和日志通过 SSH 即时读取，start/stop/restart/reload 操作需要 UI 确认，unit 名限制为简单 `.service` 名称，并会写入 `remote_change_logs` 审计表；真实服务器已完成只读服务列表验证，真实重启/停止等写操作仍需手动验收。
- 危险操作确认当前为 Phase 4 bootstrap：`RemoteOperationRisk` 已为远程文件删除/权限修改、systemd、Cron、Nginx、Environment 生成统一风险级别、目标、命令预览、影响和恢复说明；现有确认弹窗已接入风险文案，chmod sheet 会展示风险预览。后续安全组、防火墙写操作和 GitLab 部署需要复用同一模型。
- Cron 当前为 Phase 4 bootstrap：用户级 crontab 通过 SSH 即时读取，添加/启用/禁用/删除操作需要 UI 确认并在远端创建备份，同时会写入 `remote_change_logs` 审计表；真实服务器已完成只读 crontab 验证，真实写操作由 mock/contract 测试覆盖，仍需谨慎手动验收。尚未支持系统级 `/etc/cron*` 管理。
- Nginx 当前为 Phase 4 bootstrap：配置路径通过 `nginx -V` 动态探测，已覆盖 `/etc/nginx` 和 `/www/server/nginx/conf` 这类非标准安装路径；配置文件可浏览和编辑，保存时会先创建 `.hhc-backup-*` 远端备份，再写入配置并执行 `nginx -t`，测试失败会自动恢复备份；reload 需要 UI 确认并写入 `remote_change_logs` 审计表。真实服务器已完成 `nginx -t` 和配置目录只读验证；真实配置写入/reload 仍需谨慎手动验收。
- Firewall 当前为 Phase 4 bootstrap：只读探测 firewalld、ufw、nftables、iptables 并展示规则输出；真实服务器已验证 firewalld 安装但未运行的降级状态。新增/删除规则等写操作仍待规则 diff、风险确认和审计流程接入。
- Security Groups 当前为 Phase 4 bootstrap：仅对已关联云实例的账号和地域启用，使用腾讯云 VPC `DescribeSecurityGroups` / `DescribeSecurityGroupPolicies` 只读查询并展示安全组规则；当前支持本地生成安全组规则新增/删除 diff、before/after 计数、风险级别、命令预览和警告，但不执行云端写入。当前尚未持久化实例与安全组的精确关联，因此先展示该账号地域下的安全组列表，后续补实例过滤、云端写操作确认和审计。
- Environment 当前为 Phase 4 bootstrap：只发现受限范围内的常见 env 文件，包括用户/应用目录 `.env` 和 `*.env`、`/etc/default`、`/etc/sysconfig`、`/etc/systemd/system/*.service.d/*.conf`；单文件限制 256 KiB，要求 UTF-8，保存前创建 `.hhc-backup-*` 远端备份并写入 `remote_change_logs`。暂不自动解析 shell profile，不扫描私钥/凭据目录，不做跨文件变量合并。
- 云账号当前已实现本地元数据、云实例关联表、云盘/快照/计费状态表、Keychain 云凭据命名空间、Tencent / Alibaba / Huawei Cloud adapter、云实例同步服务、腾讯云云盘/快照/计费状态同步服务、腾讯云快照创建/删除操作、腾讯云云盘挂载/卸载操作、统一资源搜索、三家云基础导入 UI、云资源中心 UI、已关联 CVM 的 CPU 云监控查询和账号地域级安全组只读查询；阿里云/华为云目前只覆盖地域或项目发现、ECS 实例发现和实例派生计费状态，云盘/快照/安全组等高级资源仍未接入。真实多云手动验收、真实腾讯云快照/云盘写操作验收和更多跨云危险云写操作仍在后续任务中。
- Deployment 当前为 Phase 5 bootstrap：已建立 `deployment_projects`、`deployment_runs`、`deployment_logs` 三张表和 repository 读写基础，用于手动部署、日志、回滚和 webhook 核心触发；`DeploymentCommandBuilder` 已支持仓库 URL、branch、部署路径白名单和单行命令校验，并生成 clone/fetch/checkout/build/restart/health check 命令预览；`DeploymentRunner` 已能通过 `SSHClient` 执行受控步骤、记录脱敏后的 stdout/stderr/exit code、捕获 previous/target commit、失败停止并持久化 cancelled/failed/succeeded 状态；build 失败停止后续步骤、health check 失败、非法部署目录和工作台错误展示均有 mock/contract 测试覆盖；rollback 会通过受控 plan reset 到 previous commit，并重新执行 build/restart/health check，UI 已在执行前接入统一风险确认；webhook secret 存 Keychain，核心服务已支持 GitLab push payload 解析、`X-Gitlab-Token` 常量时间校验、repo/branch 过滤并触发 webhook run；本地 `DeploymentWebhookHTTPServer` 使用 Network.framework 监听 `/webhooks/gitlab`，按核心服务结果返回状态，并在 webhook run 开始和结束时写入 `operation_logs`；macOS workspace 已接入 Deployments 页面，支持项目列表、添加/编辑/删除、命令预览、手动运行、回滚、webhook 开关/secret、本地 listener 启停和 URL 展示、运行历史、运行中日志自动刷新和日志查看/复制，并明确客户端离线时 webhook 不会自动部署。尚未完成真实服务器部署闭环手动验收。
- Private Registries 当前为 Phase 6 bootstrap：已建立 Verdaccio 安装草稿、配置校验、固定版本策略、安装前 SSH preflight 检查、可读检查报告、基础 `config.yaml` 和 systemd service 模板；preflight 会检查 Node.js、npm/pnpm/yarn、systemd、htpasswd、端口占用、安装/data 目录父级可写性和磁盘空间，缺少 htpasswd 时以 warning 提示用户管理不可用但不阻断安装。`VerdaccioInstaller` 已生成受控远程安装流程，包含 system user、安装/data 目录创建、配置写入、systemd unit 写入、`daemon-reload`、`enable --now`、`restart` 和 `/-/ping` health check，并通过 mock/contract 测试覆盖失败停止和 health check 失败。`VerdaccioConfigurationBuilder` 已支持 `htpasswd` auth 配置、上游 registry URL policy、公开读/登录用户发布或登录用户读写两种包权限策略，以及独立 Nginx vhost 反向代理配置生成；proxy 生成包含 `proxy_pass`、Host/IP/Forwarded headers、Upgrade header 和 body size，HTTPS 仅保留配置协助注释，不自动申请证书。`NginxConfigManager` 已支持受控新建/更新 `.conf`，保存后执行 `nginx -t`，失败时恢复已有文件或删除新文件，reload 复用既有测试后 reload 流程。`VerdaccioManager` 已支持 systemd 状态、版本、storage size、journal tail 脱敏读取，start/stop/restart 服务控制，固定版本升级时备份 systemd unit 后写入新 unit、`daemon-reload`、重启和 health check，`config.yaml` UTF-8 读取和保存前 `.hhc-backup-*` 备份后重启，基于 storage 的私有包摘要列表，基于 `htpasswd -B -i` / `htpasswd -D` 的用户创建、改密和删除命令层，包含 `config.yaml` 和 storage 目录的 tar.gz 备份归档，受限备份路径恢复流程，以及 npm smoke test 流程；smoke test 会创建临时 scoped package，执行 `npm adduser`、`npm publish`、`npm install` 和 `require` 验证，并在退出时尝试 `npm unpublish` 清理，明文密码不会进入 shell 命令字符串。恢复会先停止服务并创建 rollback 归档，恢复后执行 health check，恢复命令或 health check 失败时会尝试回滚。SQLite 已接入 `registry_instances` 和 `registry_backups`，在调用方传入 repository 时记录备份/恢复成功或失败历史、大小、恢复时间和脱敏错误信息；服务控制和升级会写入 `remote_change_logs`。macOS 工作台已新增 Registries section，当前提供 Verdaccio preflight、安装确认、状态、服务 start/stop/restart、固定版本 upgrade、htpasswd 用户创建/改密/确认删除、npm publish/install smoke test、包列表、备份创建/恢复入口、Nginx proxy vhost 写入/测试结果展示/确认 reload，以及 Dart/Flutter Hosted Pub Repository 方向提示；创建备份后会回填恢复路径，恢复前需要危险确认，恢复后会刷新状态。Dart/Flutter pub 方案已完成当前轮技术结论：Phase 6 不实现自托管 pub registry installer，后续只提供外部 Hosted Pub Repository 的 `hosted-url`、`publish_to`、token 和项目配置检查辅助；unpub / pub_server 安装能力必须等真实 Dart/Flutter 项目 publish/get 验收后再开放。当前尚未完成真实服务器安装/恢复/Nginx proxy 写入验收。
- TencentCloudAdapter 已接入腾讯云 API 3.0 TC3-HMAC-SHA256 签名流程，并实现 Region、CVM instance、CBS `DescribeDisks`、CBS `DescribeSnapshots`、CBS `CreateSnapshot` / `DeleteSnapshots`、CBS `AttachDisks` / `DetachDisks`、Cloud Monitor `GetMonitorData` CPU 指标、VPC `DescribeSecurityGroups` 和 `DescribeSecurityGroupPolicies` 查询；默认测试使用 mock transport，不提交真实 SecretId/SecretKey。
- AlibabaCloudAdapter 已接入阿里云 OpenAPI V3 header 签名流程，并实现 ECS `DescribeRegions`、`DescribeInstances` 只读查询；HuaweiCloudAdapter 已接入华为云 AK/SK 签名流程，并实现 IAM project 发现和 ECS `cloudservers/detail` 只读查询。默认测试使用 mock transport，不提交真实 AccessKey/SecretKey。
- `SSHClient` 协议已经隔离 UI/ViewModel 与具体 SSH 实现，后续可以替换为 SwiftNIO SSH。
- OpenSSH adapter 当前支持私钥认证，也支持通过临时 `SSH_ASKPASS` 脚本进行 password 认证。密码从 Keychain 读出后只注入当前 SSH 子进程环境，脚本执行后立即删除。
- 后续仍需要把 bootstrap OpenSSH adapter 替换或补齐为 SwiftNIO SSH 正式实现。
