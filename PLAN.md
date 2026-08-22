# AgentQuota macOS Menu-Bar App

## Summary

Build a dependency-free native SwiftUI menu-bar app for macOS 26 that displays the current Codex subscription quota. It will use the installed Codex CLI’s local app-server protocol, target developer/Xcode builds, and support Codex only.

## Implementation Design Reference

- Use [`docs/reference/codex-weekly-quota-widget.png`](docs/reference/codex-weekly-quota-widget.png) as the implementation design for the menu-bar item and popover.
- Match the screenshot’s visual hierarchy, compact dimensions, spacing, typography, progress treatment, dark translucent material, menu-bar presentation, and placement of status and update information as closely as native SwiftUI and macOS accessibility conventions allow.
- Where the screenshot’s sample copy or values differ from the functional requirements below, preserve the screenshot’s visual design while following the specified quota semantics, states, labels, and actions.

## Implementation

- Create an Xcode 26 Swift application targeting macOS 26 with bundle identifier `com.tsilva.AgentQuota`.
- Configure it as a menu-bar-only app using `MenuBarExtra` and `LSUIElement`; do not show a Dock icon or conventional app window.
- Resolve `codex` from the inherited `PATH` and common locations, including `~/.superset/bin`, `~/.local/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`. If unavailable, show an installation error with Retry and Quit actions; do not add a binary picker.
- Run `codex app-server --stdio` as a managed child process and communicate using newline-delimited JSON-RPC:
  - Send `initialize` with AgentQuota client metadata.
  - Send the `initialized` notification.
  - Request `account/rateLimits/read`.
  - Listen for `account/rateLimits/updated`; debounce each event into a fresh read instead of merging sparse payloads.
  - Poll every 60 seconds, refresh when the popover opens, and support manual Refresh.
- Add request IDs, a 10-second timeout, serialized pipe writes, incremental stdout decoding, clean process termination, and reconnect delays of 1, 2, 5, then 30 seconds.
- Keep the last successful snapshot in memory during transient failures and mark it stale after two minutes. Do not persist quota or authentication data.
- Treat unknown fields and enum values as forward-compatible strings. Convert each window to `remainingPercent = clamp(100 - usedPercent, 0...100)`.
- Use `rateLimitsByLimitId["codex"]` when present, falling back to the legacy `rateLimits` snapshot.

## UI and Internal Interfaces

- Show the lowest remaining percentage across the primary and secondary Codex windows directly in the menu bar; show `—` until data is available and an error indicator when cached data is stale.
- The popover will contain:
  - Codex plan name and connection state.
  - One progress row per available window, labeled from its duration such as “5-hour” or “Weekly.”
  - Remaining percentage, relative reset countdown, local reset date/time, and last-updated time.
  - Refresh, About, and Quit actions.
- Handle absent secondary windows, missing reset timestamps, no authenticated account, network failures, unsupported app-server methods, malformed responses, and unexpected child-process exits with specific recovery messages.
- Define internal boundaries:
  - `CodexLocator` resolves and validates the executable.
  - `AppServerTransport` owns the process and JSON-RPC lifecycle.
  - `CodexQuotaClient` translates protocol payloads into domain models.
  - `QuotaStore` owns connection, refresh, stale-data, and retry state for SwiftUI.
  - `QuotaSnapshot` and `QuotaWindow` expose display-ready quota values without leaking raw protocol structures.
- Disable App Sandbox because the app must execute the local Codex binary. Use local/ad-hoc developer signing only; signing, notarization, launch-at-login, alerts, history, charts, and other providers remain outside v1.
- Add a README covering Xcode build/run steps, macOS 26 and Codex CLI requirements, `codex login`, supported discovery paths, and troubleshooting.

## Test Plan

- Unit-test quota conversion, clamping, tightest-window selection, duration labels, reset formatting, stale-state transitions, and missing optional fields.
- Test JSON-RPC framing, request correlation, initialization ordering, timeouts, unknown messages, malformed lines, and process restart behavior using an injectable fake transport.
- Test executable discovery across inherited `PATH`, known locations, missing files, and non-executable files.
- Test store behavior for initial loading, successful refresh, rolling update, manual refresh, retained stale data, authentication failure, and recovery.
- Run `xcodebuild` build and test for the macOS destination.
- Manually verify against a logged-in Codex CLI that:
  - The menu-bar percentage matches `account/rateLimits/read`.
  - Opening and manually refreshing the popover updates the timestamp.
  - Quitting terminates the child app-server process.
  - Missing Codex and logged-out states show actionable errors.

## Assumptions

- The current Codex app-server protocol remains available, but it is treated as version-sensitive and detected by capability rather than a hard-coded CLI version.
- V1 is a developer build for the current Mac, targets macOS 26 only, and has no public release pipeline.
- AgentQuota reads existing Codex authentication indirectly through the child process and never reads or logs credential files.
