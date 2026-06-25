# Windows Native Client Strategy

> The current implementation priority remains the macOS native app. The Windows native client should start after the macOS feature set is reasonably mature. The Windows version should reuse domain concepts and protocol-layer design, but use native Windows UI and platform services.

## 1. Recommendation

Recommended Windows stack:

| Layer | Choice |
|-------|--------|
| UI | WinUI 3 |
| Platform SDK | Windows App SDK 2.x stable |
| Language | C# |
| Runtime | .NET 10 LTS |
| Architecture | MVVM |
| Database | SQLite |
| Credentials | Windows Credential Manager / DPAPI |
| SSH | Start with SSH.NET; evaluate libssh2/native wrapper if needed |
| Packaging | MSIX first, unpackaged if needed |
| Distribution | GitHub Releases / winget / MSIX installer |

WinUI 3 is Microsoft's modern native UI framework for new Windows desktop apps and is delivered as part of the Windows App SDK. It is the right default for a new, modern, native Windows version. WPF remains a strong fallback when mature controls, legacy compatibility, or enterprise desktop patterns matter more than modern platform direction.

## 2. Why WinUI 3

Pros:

- Microsoft's recommended native UI direction for new Windows apps.
- Fluent Design and Windows 11 visual alignment.
- Windows App SDK provides modern windowing, lifecycle, notifications, resources, and deployment features.
- Supports C# and C++; this project should prefer C#.
- Runs on Windows 10 1809+ and Windows 11.

Risks:

- Some desktop control ecosystems are less mature than WPF.
- XAML designer, third-party controls, complex tables, and terminal controls require validation.
- Windows App SDK runtime deployment and packaging need early planning.

Strategy: **Use WinUI 3 for the new Windows client, but keep core business logic independent of the UI framework.**

## 3. Why not WPF first

WPF strengths:

- Mature and stable.
- Strong ecosystem for enterprise desktop applications.
- Rich third-party controls and data grids.
- Many years of production experience and troubleshooting knowledge.

Reasons not to make it the default:

- Modern Windows 11 look and feel takes more work.
- Platform direction is less future-facing than WinUI 3 for new native apps.
- The project wants a modern native client rather than a legacy-compatible desktop tool.

WPF remains Plan B if WinUI 3 blocks key requirements such as terminal integration, complex data tables, window behavior, or deployment.

## 4. Why C# instead of C++

The project is mostly about:

- SSH connections and command execution.
- Cloud provider APIs.
- SQLite persistence.
- Credential management.
- Forms, lists, state synchronization.
- Deployment scripts and logs.

C# is more productive for these needs. It has strong async, JSON, HTTP, SQLite, MVVM, and testing ecosystems. C++/WinRT is worth considering only for very low-level Windows integration, DirectX, specialized native interop, or extreme performance requirements.

## 5. Suggested architecture

```text
HHCServerManager.Windows/
├── App/
│   ├── App.xaml
│   └── MainWindow.xaml
├── Presentation/
│   ├── Views/
│   ├── ViewModels/
│   └── Controls/
├── Application/
│   ├── ServerManagement/
│   ├── CloudProviders/
│   ├── Deployment/
│   └── Settings/
├── Domain/
│   ├── Servers/
│   ├── SSH/
│   ├── Cloud/
│   └── Security/
├── Infrastructure/
│   ├── Storage/
│   ├── Credentials/
│   ├── SSH/
│   ├── CloudProviders/
│   └── Logging/
└── Tests/
```

Layering principles:

- `Domain` stays platform-independent.
- `Application` orchestrates use cases and does not depend on WinUI.
- `Infrastructure` wraps SQLite, Credential Manager, SSH, and cloud APIs.
- `Presentation` is the only layer that depends on WinUI 3.
- macOS and Windows should share concepts and interface names where useful, but they should not force shared code too early.

## 6. macOS to Windows mapping

| Capability | macOS | Windows |
|------------|-------|---------|
| UI | SwiftUI | WinUI 3 |
| Language | Swift | C# |
| SSH | SwiftNIO SSH | SSH.NET / libssh2 wrapper |
| Local database | SQLite + GRDB | SQLite + EF Core or sqlite-net |
| Credentials | macOS Keychain | Windows Credential Manager / DPAPI |
| Cloud APIs | Provider Adapter | Provider Adapter |
| Packaging | `.app`, signing, notarization later | MSIX / winget |
| Updates | Later evaluation | MSIX / winget / GitHub Releases |

## 7. Technical validation before Windows work

Before starting the Windows client, validate:

1. WinUI 3 sidebar, tabs, complex lists, and data tables.
2. Terminal strategy: simplified command panel, ConPTY integration, or mature terminal control.
3. SSH.NET support for ED25519, passphrases, host key verification, and streaming output.
4. Credential Manager / DPAPI credential storage and migration.
5. MSIX packaging, updates, and Windows App SDK runtime deployment.
6. Proxy, firewall, and enterprise network environments.
7. ARM64 Windows support.

## 8. Roadmap position

The Windows client is not part of the current macOS MVP.

Recommended sequence:

- **Phase 1-6**: complete the core macOS native app.
- **Phase 7**: add more cloud providers and advanced cloud resource features.
- **Phase 8**: start Windows native technical validation and architecture.

Phase 8 first target:

1. WinUI 3 app skeleton.
2. Server profile CRUD.
3. Windows Credential Manager credential storage.
4. Real SSH connection and `printf hhc-ssh-ok` smoke test.
5. Reuse the cloud provider adapter domain model.

## 9. References

- WinUI 3: https://learn.microsoft.com/en-us/windows/apps/winui/winui3/
- Windows App SDK: https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/
- Windows developer platform overview: https://learn.microsoft.com/en-us/windows/apps/get-started/
- Windows App SDK downloads: https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads
- .NET downloads and support: https://dotnet.microsoft.com/en-us/download/dotnet
