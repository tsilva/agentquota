# AgentQuota Project Instructions

## Project skills

- Use the project skill at `.agents/skills/build-release/SKILL.md` whenever the user asks to build, package, publish, or validate an AgentQuota GitHub Release. Invoke it as `$build-release` (or `/build-release` in clients that expose skills as slash commands) and follow its automatic versioning, preflight, artifact, and publication safeguards.
- Release versioning is derived from commits. Mark breaking app changes with a conventional `type!:` subject or a `BREAKING CHANGE:` trailer, and prefer `feat:` subjects for feature additions so semantic bumps remain deterministic.

## Product Specifications

At the start of substantive repository work, use `$specs-author` to read the entire root `SPECS.md` once per ongoing task. Reuse unchanged contents across follow-ups and composed skills. Reread when the file or repository association changes, or new stakeholder intent requires a fresh comparison. Before finishing, always check for new or changed stakeholder intent; reread if the file or intent changed. Purely conversational follow-ups do not require another full read.

- Treat `SPECS.md` as the persistent source of stakeholder requirements that cannot be inferred reliably from code or remembered conversations.
- Apply the scope test to proposed and existing requirements: root `SPECS.md` contains only project-wide intent; scoped intent belongs in its nearest authoritative specification and must not be broadened to fit the root.
- If the task, repository, or user request contradicts, omits, or ambiguously interprets the specification, tell the user. Continue safe exploration and work that does not depend on resolving the issue, but never silently choose an interpretation.
- Never edit `SPECS.md` from inference. Propose the exact change, explain why it reflects stakeholder intent, and edit the file only after the user explicitly approves that exact change.
- Keep `SPECS.md` complete, concise, and compacted. It must contain stakeholder intent rather than implementation, architecture, operations, or transient project detail.

## Shared release procedure

The project `build-release` skill composes `$release-workflow` from
`/Users/tsilva/.codex/skills/release-workflow/SKILL.md`.
Read both for release work; keep project commands, version policy, artifact
requirements, and approval gates in the project adapter.
