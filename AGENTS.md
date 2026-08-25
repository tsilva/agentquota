# AgentQuota Project Instructions

## Project skills

- Use the project skill at `.agents/skills/build-release/SKILL.md` whenever the user asks to build, package, publish, or validate an AgentQuota GitHub Release. Invoke it as `$build-release` (or `/build-release` in clients that expose skills as slash commands) and follow its automatic versioning, preflight, artifact, and publication safeguards.
- Release versioning is derived from commits. Mark breaking app changes with a conventional `type!:` subject or a `BREAKING CHANGE:` trailer, and prefer `feat:` subjects for feature additions so semantic bumps remain deterministic.
