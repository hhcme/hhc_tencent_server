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

- SQLite repository：服务器 CRUD、trusted host key 级联删除、命令历史、操作日志。
- KeychainService：password、private key 写入、读取、覆盖、删除。
- ServerManagementService：服务器创建、删除、凭据清理。
- AddServerViewModel：表单校验。
- ServerWorkspaceViewModel：连接状态、主机指纹确认、smoke test、单条命令执行、本次会话输出历史、持久化命令元数据历史。
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

- 当前 SSH 适配层是 bootstrap OpenSSH adapter，用于先打通真实服务器、主机指纹信任、smoke test 和单条命令执行。
- 命令面板只持久化 command、exit code、duration 和 created at；stdout/stderr 默认只保留在本次工作台会话中，避免把敏感输出写入 SQLite。
- `SSHClient` 协议已经隔离 UI/ViewModel 与具体 SSH 实现，后续可以替换为 SwiftNIO SSH。
- OpenSSH adapter 当前支持私钥认证，也支持通过临时 `SSH_ASKPASS` 脚本进行 password 认证。密码从 Keychain 读出后只注入当前 SSH 子进程环境，脚本执行后立即删除。
- 后续仍需要把 bootstrap OpenSSH adapter 替换或补齐为 SwiftNIO SSH 正式实现。
