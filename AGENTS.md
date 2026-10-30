# AgentQuota Project Instructions

## Project skills

- Use the project skill at `.agents/skills/agentquota_build-release/SKILL.md` whenever the user asks to build, package, publish, or validate an AgentQuota GitHub Release. Invoke it as `$agentquota_build-release` (or `/agentquota_build-release` in clients that expose skills as slash commands) and follow its automatic versioning, preflight, artifact, and publication safeguards.
- Release versioning is derived from commits. Mark breaking app changes with a conventional `type!:` subject or a `BREAKING CHANGE:` trailer, and prefer `feat:` subjects for feature additions so semantic bumps remain deterministic.

## Product Specifications

When specifications exist, use `$specs-author` for substantive work and
specification changes. Follow its shared read/reuse cadence, provisional-scenario
guidance, proportional detail, decision-based approval, and closing intent check.
The maintained procedure is `/Users/tsilva/.codex/skills/private-skills/specs-author/SKILL.md`.

## Shared release procedure

The project `agentquota_build-release` skill composes `$release-workflow` from
`/Users/tsilva/.codex/skills/release-workflow/SKILL.md`.
Read both for release work; keep project commands, version policy, artifact
requirements, and approval gates in the project adapter.
