# macOS MVP Figma Design

Figma file: [HHC Server Manager - macOS MVP Design](https://www.figma.com/design/Wvukq4AG9kHbVYKdF64gBX)

## Scope

This design file is used to validate product information architecture, core flows, and UI density before implementing the macOS client. The recommended implementation reference is now the `02 macOS Native Flow v0.2` page; the `01 macOS MVP` page is kept as an early exploration.

The core v0.2 adjustment is: the app starts with a server list; opening a server enters a dedicated workspace for that server; switching servers happens through an explicit switcher in the workspace toolbar.

The current design focuses on UI decisions that affect Phase 1 and Phase 2:

- Server list, grouping, search, and connection states.
- Dedicated single-server workspace and overview.
- SSH credential input and pre-save validation.
- First-use SSH host-key trust flow.
- Cloud provider account settings.
- Cloud instance discovery and linking cloud instances to local SSH profiles.

## Frames

### Recommended: `02 macOS Native Flow v0.2`

- `01 Startup - Server List`: startup screen focused on server browsing, grouping, search, filtering, and selected-server summary.
- `02 Server Workspace - Overview`: dedicated single-server workspace after opening a server, with server-specific navigation on the left and back/switch controls in the toolbar.
- `03 Server Switcher Popover`: popover for switching the active server without returning to the full list.
- `04 Add Server - Native Sheet`: add-server form closer to a native macOS sheet.
- `05 Host Key Trust - Native Sheet`: host-key confirmation flow closer to a native macOS sheet.

### Early reference: `01 macOS MVP`

- `01 Main Window - Dashboard`: main window, sidebar, server overview, cloud instance information, recent operations, and terminal preview.
- `02 Add Server Sheet`: add-server sheet with profile fields, authentication mode, and security guidance.
- `03 Host Key Trust Sheet`: fingerprint confirmation flow for unknown hosts.
- `04 Cloud Accounts Settings`: cloud account management, provider adapter capability model, and Tencent Cloud account configuration.
- `05 Instance Import and SSH Link`: cloud API instance discovery and SSH profile creation for unconfigured instances.
- `06 Visual System and Handoff Notes`: colors, implementation decisions, and key states.

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

- Replace base nodes with reusable components after adopting the Apple macOS UI Kit or a project-owned component library.
- Add deeper screens for terminal, file manager, command panel, and deployment workflows.
- Feed SwiftUI implementation findings back into control sizing, states, and empty-state designs.
