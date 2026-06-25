# macOS MVP Figma Design

Figma file: [HHC Server Manager - macOS MVP Design v0.1](https://www.figma.com/design/Wvukq4AG9kHbVYKdF64gBX)

## Scope

This design file is used to validate product information architecture, core flows, and UI density before implementing the macOS client. The current version focuses on UI decisions that affect Phase 1 and Phase 2:

- Server list, grouping, search, and connection states.
- Single-server dashboard.
- SSH credential input and pre-save validation.
- First-use SSH host-key trust flow.
- Cloud provider account settings.
- Cloud instance discovery and linking cloud instances to local SSH profiles.

## Frames

- `01 Main Window - Dashboard`: main window, sidebar, server overview, cloud instance information, recent operations, and terminal preview.
- `02 Add Server Sheet`: add-server sheet with profile fields, authentication mode, and security guidance.
- `03 Host Key Trust Sheet`: fingerprint confirmation flow for unknown hosts.
- `04 Cloud Accounts Settings`: cloud account management, provider adapter capability model, and Tencent Cloud account configuration.
- `05 Instance Import and SSH Link`: cloud API instance discovery and SSH profile creation for unconfigured instances.
- `06 Visual System and Handoff Notes`: colors, implementation decisions, and key states.

## Design Decisions

- macOS comes first. The first screen is the usable desktop app, not a marketing page.
- SSH is the baseline execution channel. Cloud APIs are optional enhancements for discovery, cloud resource state, and provider-side capabilities.
- Host-key trust is an explicit security gate before credentials are saved and a real connection is established.
- Cloud instances may not have public IPs, so the design keeps a private-IP plus jump-host path.
- The later Windows native app can reuse the information architecture, but controls and platform integration should be rebuilt with WinUI 3 and Windows App SDK.

## Review Checklist

- Is the sidebar dense enough for day-to-day multi-server management?
- Are SSH state, cloud resource state, and server actions prioritized clearly on the dashboard?
- Is the add-server flow short enough without skipping security validation?
- Do cloud provider APIs read as optional enhancement instead of a hard dependency?
- Does the import flow make it clear that discovering a cloud instance and creating an SSH profile are separate steps?

## Follow-up Iterations

- Replace base nodes with reusable components after adopting the Apple macOS UI Kit or a project-owned component library.
- Add deeper screens for terminal, file manager, command panel, and deployment workflows.
- Feed SwiftUI implementation findings back into control sizing, states, and empty-state designs.
