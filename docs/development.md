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

- SQLite repository：服务器 CRUD、trusted host key 级联删除、命令历史、操作日志、远程变更审计日志、云账号元数据、云实例关联。
- KeychainService：SSH password、private key、云 SecretId/SecretKey 写入、读取、覆盖、删除。
- ServerManagementService / CloudAccountService：服务器与云账号创建、更新、删除、凭据清理。
- Cloud provider foundation：adapter 协议、provider registry、capability 查询、统一错误、超时包装。
- TencentCloudAdapter：TC3 签名、Region 查询、CVM DescribeInstances 查询、分页、provider 错误映射、mock transport fixture 测试。
- CloudInstanceSyncService：读取 Keychain 云凭据、同步云实例 upsert、保留已有 SSH 关联、从云实例创建 SSH profile、关联/解除关联。
- CloudImportSheet / CloudImportViewModel：腾讯云账号验证后保存、加载可用地域、同步实例、选择实例并导入为 SSH profile。
- DashboardService：通过 SSH 探测 OS、kernel、`/proc`、systemd、sftp，并采集负载、内存、根磁盘、CPU 核心数、网络收发总量和进程摘要基础指标；单项指标失败会返回 warning，不阻断整个快照。
- RemoteFileService：通过 SSH/OpenSSH 工具链进行文件管理 bootstrap，支持目录列表、单文件上传/下载、重命名、chmod 权限修改、可恢复移入远端回收目录、轻量 UTF-8 文本读写、保存前备份和另存为，并解析文件类型、大小、权限、修改时间和路径。
- SystemdServiceManager：通过 SSH/systemctl 读取 systemd service 列表，解析 load/active/sub/description，支持严格 `.service` unit 名校验后的 start/stop/restart/reload，以及 journalctl 最近日志读取。
- CronManager：通过 SSH/crontab 读取用户级 crontab，解析启用/禁用任务，支持添加、启用、禁用和删除任务；写入前会把当前 crontab 备份到远端 `~/.hhc-crontab-backup-*`。
- NginxConfigManager：通过 SSH 动态探测 Nginx 配置路径，优先读取 `nginx -V` 的 `--conf-path` / `--prefix`，并兼容 `/etc/nginx`、`/usr/local/nginx/conf`、`/opt/nginx/conf` 等常见目录；支持配置文件列表、UTF-8 配置读取、保存前远端备份、保存后 `nginx -t`、测试失败自动恢复备份和确认后 reload。
- AddServerViewModel：表单校验。
- ServerWorkspaceViewModel：连接状态、主机指纹确认、smoke test、单条命令执行与取消、本次会话输出历史、stdout/stderr 分开展示、失败摘要、持久化命令元数据历史、历史命令重跑、Dashboard 手动/自动刷新、远程目录浏览、排队单文件上传/下载、当前传输取消、待传队列清空、传输任务状态记录、重命名、chmod 权限修改、可恢复移入回收目录、轻量文本编辑、systemd 服务管理、Cron 管理和 Nginx 配置管理状态流。
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
- Cron 当前为 Phase 4 bootstrap：用户级 crontab 通过 SSH 即时读取，添加/启用/禁用/删除操作需要 UI 确认并在远端创建备份，同时会写入 `remote_change_logs` 审计表；真实服务器已完成只读 crontab 验证，真实写操作由 mock/contract 测试覆盖，仍需谨慎手动验收。尚未支持系统级 `/etc/cron*` 管理。
- Nginx 当前为 Phase 4 bootstrap：配置路径通过 `nginx -V` 动态探测，已覆盖 `/etc/nginx` 和 `/www/server/nginx/conf` 这类非标准安装路径；配置文件可浏览和编辑，保存时会先创建 `.hhc-backup-*` 远端备份，再写入配置并执行 `nginx -t`，测试失败会自动恢复备份；reload 需要 UI 确认并写入 `remote_change_logs` 审计表。真实服务器已完成 `nginx -t` 和配置目录只读验证；真实配置写入/reload 仍需谨慎手动验收。
- 云账号当前已实现本地元数据、云实例关联表、Keychain 云凭据命名空间、Tencent Cloud adapter、云实例同步服务、基础导入 UI 和已关联 CVM 的 CPU 云监控查询；真实腾讯云账号手动验收仍在后续任务中。
- TencentCloudAdapter 已接入腾讯云 API 3.0 TC3-HMAC-SHA256 签名流程，并实现 Region、CVM instance 只读查询和 Cloud Monitor `GetMonitorData` CPU 指标查询；默认测试使用 mock transport，不提交真实 SecretId/SecretKey。
- `SSHClient` 协议已经隔离 UI/ViewModel 与具体 SSH 实现，后续可以替换为 SwiftNIO SSH。
- OpenSSH adapter 当前支持私钥认证，也支持通过临时 `SSH_ASKPASS` 脚本进行 password 认证。密码从 Keychain 读出后只注入当前 SSH 子进程环境，脚本执行后立即删除。
- 后续仍需要把 bootstrap OpenSSH adapter 替换或补齐为 SwiftNIO SSH 正式实现。
