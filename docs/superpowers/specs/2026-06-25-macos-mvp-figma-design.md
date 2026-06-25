# macOS MVP Figma 设计稿

Figma 文件：[HHC Server Manager - macOS MVP Design](https://www.figma.com/design/Wvukq4AG9kHbVYKdF64gBX)

## 范围

这份设计稿用于在正式实现 macOS 客户端前确认产品信息架构、核心流程和界面密度。当前推荐使用 `02 macOS Native Flow v0.2` 页面作为实现参考；`01 macOS MVP` 页面保留为早期探索稿。

v0.2 的核心调整是：应用启动后首先展示服务器列表；点击服务器后进入该服务器的专用工作台；在工作台内通过顶部服务器切换器切换当前操作对象。

当前设计重点覆盖 Phase 1 到 Phase 2 会直接影响 UI 架构的内容：

- 服务器列表、分组、搜索和连接状态。
- 单服务器工作台和概览。
- SSH 凭据录入和保存前校验。
- 首次连接时的 SSH 主机指纹信任流程。
- 云厂商账号配置。
- 云实例发现，以及云实例与本地 SSH Profile 的关联。

## 画板

### 当前推荐：`02 macOS Native Flow v0.2`

- `01 Startup - Server List`：应用启动页，优先展示服务器列表、分组、搜索、筛选和选中服务器摘要。
- `02 Server Workspace - Overview`：点击服务器后进入的单服务器工作台，左侧是该服务器的操作分类，顶部提供返回列表和服务器切换入口。
- `03 Server Switcher Popover`：在单服务器工作台内切换当前服务器的弹出层。
- `04 Add Server - Native Sheet`：更接近 macOS sheet 的添加服务器表单。
- `05 Host Key Trust - Native Sheet`：更接近 macOS sheet 的主机指纹确认流程。

### 早期参考：`01 macOS MVP`

- `01 Main Window - Dashboard`：主窗口、侧边栏、服务器概览、云实例信息、近期操作和终端预览。
- `02 Add Server Sheet`：添加服务器弹窗，包含基础信息、认证方式和安全提示。
- `03 Host Key Trust Sheet`：首次连接未知主机时的指纹确认流程。
- `04 Cloud Accounts Settings`：云账号管理、Provider adapter 能力和腾讯云账号配置。
- `05 Instance Import and SSH Link`：通过云 API 发现实例，并为未配置实例创建 SSH Profile。
- `06 Visual System and Handoff Notes`：颜色、实现决策和关键状态说明。

## 设计判断

- macOS 优先，不做营销页，第一屏就是可浏览和选择的服务器列表。
- 单台服务器的操作应进入专用工作台，不在启动页里直接塞满详情面板。
- 服务器切换应是工作台内的明确功能，而不是一直常驻展示全部服务器详情。
- SSH 是基础执行通道；云 API 是可选增强层，负责实例发现、云资源状态和平台侧能力。
- 主机指纹信任必须在凭据保存和正式连接前成为显式安全关卡。
- 云实例可以没有公网 IP，因此设计稿保留了私网 IP + jump host 的配置路径。
- 后续 Windows 原生版可以复用信息架构，但控件和平台能力应按 WinUI 3/Windows App SDK 重新实现。

## 评审重点

- 启动页是否符合“先浏览服务器列表，再进入服务器工作台”的产品心智。
- 单服务器工作台是否足够专注，避免和服务器总览页混在一起。
- 服务器切换器是否能自然替代常驻的全量服务器列表。
- 添加服务器流程是否足够短，同时没有跳过安全校验。
- 云厂商 API 功能是否以增强能力出现，而不是强制依赖。
- 实例导入流程是否能解释“发现云实例”和“创建 SSH 连接配置”是两件事。

## 后续迭代

- 接入 Apple macOS UI Kit 或项目自建组件库后，将基础节点替换为更贴近系统组件的可复用组件。
- 为终端、文件管理器、命令面板和部署流程补充更细的二级界面。
- 根据首版 SwiftUI 实现反馈，回写控件尺寸、状态和空态设计。
