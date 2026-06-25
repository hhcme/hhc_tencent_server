# Contributing / 贡献指南

[English](#english) | [中文](#中文)

## English

Thanks for your interest in HHC Server Manager. The project is early, so design feedback, implementation help, tests, and documentation improvements are all valuable.

### Ways to contribute

- Review architecture and security decisions.
- Implement Phase 1 tasks from the documented plan.
- Add tests for storage, Keychain, SSH state, and host key trust.
- Improve README or Chinese project documentation.
- Report bugs with clear reproduction steps.
- Suggest features that fit the SSH-first, vendor-neutral direction.

### Development principles

- Prefer real SSH behavior over mocked success states.
- Do not store secrets in SQLite, logs, issue screenshots, or test fixtures.
- Treat SSH host key verification as a required security feature.
- Keep UI state on the main actor and isolate networking details inside services.
- Add tests for high-risk behavior.
- Keep the root README bilingual; keep detailed design and phase plans in Chinese unless a maintainer asks for a translation.

### Pull request checklist

Before opening a pull request:

- The change has a clear scope.
- Documentation is updated in the appropriate place: README for project introduction changes, Chinese docs for architecture and phase-plan changes.
- Tests are added or updated where appropriate.
- No secrets, private keys, server addresses, or local paths are committed.
- The change follows the current Phase boundary.

### Commit style

Use short, descriptive commit messages. Examples:

- `docs: add bilingual project README`
- `feat: add server profile model`
- `test: cover host key trust mismatch`

## 中文

感谢你关注 HHC 服务器管理器。项目还处在早期阶段，架构反馈、功能实现、测试、文档改进和安全审查都很有价值。

### 可以贡献什么

- 审查架构和安全设计。
- 按 Phase 1 计划实现任务。
- 为存储、Keychain、SSH 状态、主机指纹信任补测试。
- 改进 README 或中文项目文档。
- 用清晰复现步骤报告问题。
- 提出符合“SSH 优先、云厂商中立”方向的功能建议。

### 开发原则

- 优先实现真实 SSH 行为，不用模拟成功状态冒充可用能力。
- 不要把密码、私钥、真实服务器地址写入 SQLite、日志、截图或测试 fixture。
- 把 SSH 主机指纹验证当成必需安全能力。
- UI 状态保持在 main actor，网络细节隔离在服务层。
- 高风险行为必须配测试。
- 根目录 README 保持中英文；详细设计和 Phase 实施计划默认使用中文维护，除非维护者明确要求翻译。

### Pull request 检查清单

提交 PR 前请确认：

- 变更范围清晰。
- 行为或架构变化已更新对应文档：项目介绍改 README，架构和 Phase 计划改中文 docs。
- 需要测试的地方已经补充或更新测试。
- 没有提交密钥、密码、真实服务器地址或本地路径。
- 变更没有越过当前 Phase 边界。

### Commit 风格

提交信息保持简短明确，例如：

- `docs: add bilingual project README`
- `feat: add server profile model`
- `test: cover host key trust mismatch`
