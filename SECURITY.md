# Security Policy / 安全策略

[English](#english) | [中文](#中文)

## English

HHC Server Manager handles SSH connections, host keys, and local credentials. Security reports are taken seriously.

### Supported versions

The project is pre-release. Until the first tagged release, only the default branch is considered supported for security review.

### How to report a vulnerability

Please do not publicly disclose vulnerabilities that may expose credentials, bypass host key verification, execute unintended remote commands, or leak server information.

Preferred reporting path:

1. Open a private security advisory on GitHub if available.
2. If private advisories are not available, contact the repository owner privately.
3. If neither option is available, open a minimal public issue that says a security report exists, without technical exploit details or secrets.

### Sensitive data rules

Never include the following in issues, pull requests, screenshots, or logs:

- Passwords or tokens.
- Private keys or passphrases.
- Cloud provider SecretId/SecretKey, AccessKey, temporary tokens, or API credentials.
- Real production hostnames, IP addresses, usernames, or ports.
- Known-host fingerprints for private infrastructure unless intentionally public.

### Security priorities

- Credentials must be stored in macOS Keychain, not SQLite.
- Cloud provider API credentials must be stored in macOS Keychain, not SQLite or logs.
- SSH host key verification must not be bypassed silently.
- Host key changes must block connection until explicitly reviewed.
- Remote destructive operations must require confirmation and clear scope.
- Logs must avoid secrets and private infrastructure details.

## 中文

HHC 服务器管理器会处理 SSH 连接、主机指纹和本地凭据，因此安全问题会被认真对待。

### 支持版本

项目目前还没有正式发布版本。在第一个 tag 发布前，只有默认分支被视为安全审查对象。

### 如何报告漏洞

请不要公开披露可能导致凭据泄露、绕过主机指纹验证、执行非预期远程命令或泄露服务器信息的漏洞细节。

推荐报告方式：

1. 如果 GitHub private security advisory 可用，请优先使用。
2. 如果不可用，请私下联系仓库所有者。
3. 如果以上方式都不可用，可以创建一个最小公开 issue，只说明存在安全报告，不包含漏洞细节或敏感信息。

### 敏感数据规则

不要在 issue、pull request、截图或日志中包含：

- 密码或 token。
- 私钥或密钥口令。
- 云厂商 SecretId/SecretKey、AccessKey、临时 token 或 API 凭据。
- 真实生产主机名、IP、用户名或端口。
- 私有基础设施的 known-host 指纹，除非它本来就是公开信息。

### 安全优先级

- 凭据必须存入 macOS Keychain，不写入 SQLite。
- 云厂商 API 凭据必须存入 macOS Keychain，不写入 SQLite 或日志。
- SSH 主机指纹验证不能被静默绕过。
- 主机指纹变更必须阻断连接，直到用户明确审查。
- 远程破坏性操作必须有确认和清晰作用范围。
- 日志中应避免包含密钥和私有基础设施细节。
