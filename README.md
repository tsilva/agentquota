<p align="center">
  <img src="logo.png" alt="AgentQuota" width="520" />
  <br />
  <strong>🤖 Know your Codex quota at a glance 📊</strong>
</p>

AgentQuota is a native macOS menu-bar app for developers who use Codex. It keeps the tightest active subscription quota visible and opens a compact breakdown of every available quota window, reset time, and connection state.

The app reads quota data through the installed Codex CLI's local app-server protocol. It has no third-party dependencies and does not persist quota or authentication data.

## Install

Requires macOS 26, Xcode 26, and a current Codex CLI installation.

```bash
git clone https://github.com/tsilva/agentquota.git
cd agentquota
codex login
open AgentQuota.xcodeproj
```

In Xcode, select the **AgentQuota** scheme and **My Mac** destination, then choose **Run**. AgentQuota appears in the menu bar rather than the Dock.

## Commands

Run these commands from the repository root:

```bash
xcodebuild -project AgentQuota.xcodeproj -scheme AgentQuota -destination 'platform=macOS' build  # build the app
xcodebuild -project AgentQuota.xcodeproj -scheme AgentQuota -destination 'platform=macOS' test   # run the tests
```

## Notes

- AgentQuota finds `codex` on `PATH`, then checks `~/.superset/bin`, `~/.local/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`.
- It refreshes when the menu opens, when Codex reports a quota update, every 60 seconds, or when you refresh manually.
- The last successful snapshot stays in memory during transient failures and becomes stale after two minutes.
- Reconnect attempts back off through 1, 2, 5, and 30 seconds.
- This is an unsandboxed, locally signed developer build because it must run the local Codex executable. There is no notarized public release pipeline.

## Troubleshooting

- **Codex CLI not found:** confirm `codex --version` works, then reopen Xcode and choose **Retry**.
- **Sign-in required:** run `codex login`, finish authentication, and choose **Retry**.
- **Quota reporting unsupported:** update the Codex CLI and choose **Retry**.
- **App-server or network failure:** use **Refresh** or **Retry**; AgentQuota keeps the latest in-memory snapshot while reconnecting.

## Architecture

![AgentQuota architecture](architecture.png)

## License

[MIT](LICENSE)
