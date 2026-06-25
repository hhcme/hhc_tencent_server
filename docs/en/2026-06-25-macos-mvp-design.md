# macOS MVP Design

Repository snapshots: [macOS MVP v0.2 Design Snapshots](../assets/design/macos-mvp-v0.2/README.md)

## Scope

This design file is used to validate product information architecture, core flows, and UI density before implementing the macOS client. The recommended implementation reference is now the checked-in `macos-mvp-v0.2` design snapshots.

The core v0.2 adjustment is: the app starts with a server list; opening a server enters a dedicated workspace for that server; switching servers happens through an explicit switcher in the workspace toolbar.

The current design focuses on UI decisions that affect Phase 1 and Phase 2:

- Server list, grouping, search, and connection states.
- Dedicated single-server workspace and overview.
- SSH credential input and pre-save validation.
- First-use SSH host-key trust flow.
- Cloud provider account settings.
- Cloud instance discovery and linking cloud instances to local SSH profiles.

## Snapshots

- `01-startup-server-list.png`: startup screen focused on server browsing, grouping, search, filtering, and selected-server summary.
- `02-server-workspace-overview.png`: dedicated single-server workspace after opening a server, with server-specific navigation on the left and back/switch controls in the toolbar.
- `03-server-switcher-popover.png`: popover for switching the active server without returning to the full list.
- `04-add-server-native-sheet.png`: add-server form closer to a native macOS sheet.
- `05-host-key-trust-native-sheet.png`: host-key confirmation flow closer to a native macOS sheet.

## Local Images

- [Startup server list](../assets/design/macos-mvp-v0.2/01-startup-server-list.png)
- [Server workspace overview](../assets/design/macos-mvp-v0.2/02-server-workspace-overview.png)
- [Server switcher popover](../assets/design/macos-mvp-v0.2/03-server-switcher-popover.png)
- [Add server native sheet](../assets/design/macos-mvp-v0.2/04-add-server-native-sheet.png)
- [Host key trust native sheet](../assets/design/macos-mvp-v0.2/05-host-key-trust-native-sheet.png)

## Design Decisions

- macOS comes first. The first screen is a browsable server list, not a marketing page.
- Single-server operations should happen in a dedicated workspace instead of being mixed into the startup list.
- Server switching should be an explicit workspace action rather than a permanent all-server detail surface.
- SSH is the baseline execution channel. Cloud APIs are optional enhancements for discovery, cloud resource state, and provider-side capabilities.
- Host-key trust is an explicit security gate before credentials are saved and a real connection is established.
- Cloud instances may not have public IPs, so the design keeps a private-IP plus jump-host path.
- The later Windows native app can reuse the information architecture, but controls and platform integration should be rebuilt with WinUI 3 and Windows App SDK.

## Review Checklist

- Does the startup screen match the mental model of browsing servers first, then opening one workspace?
- Is the single-server workspace focused enough, without mixing global server browsing into it?
- Does the server switcher naturally replace a permanently visible all-server detail list?
- Is the add-server flow short enough without skipping security validation?
- Do cloud provider APIs read as optional enhancement instead of a hard dependency?
- Does the import flow make it clear that discovering a cloud instance and creating an SSH profile are separate steps?

## Follow-up Iterations

- Use the checked-in snapshots as the stable implementation reference for the open-source project.
- Add deeper screens for terminal, file manager, command panel, and deployment workflows.
- Feed SwiftUI implementation findings back into control sizing, states, and empty-state designs.
