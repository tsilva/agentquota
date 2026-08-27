## PROJECT PURPOSE

AgentQuota gives Codex users a macOS menu-bar view of their current quota and connection state.

## PROJECT REQUIREMENTS

### Codex executable

- On first launch, AgentQuota must prefer the default Codex executable over wrapper executables, persist its stable path under `~/.agentquota/`, and reuse that path on later launches.
- AgentQuota settings must let the user select and persist a different Codex executable.
