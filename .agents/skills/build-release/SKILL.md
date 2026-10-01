---
name: build-release
description: Automatically version, build, verify, package, and publish AgentQuota as a public GitHub Release. Use for AgentQuota release requests, not ordinary local builds or installation.
---

# Build Release

Read and apply the shared `$release-workflow` skill at
`/Users/tsilva/.codex/skills/release-workflow/SKILL.md` before execution.
It owns common preflight, publication safeguards, `$push` integration,
workflow monitoring, verification, and reporting. The rules below are this
project's adapter; they retain its invocation default and required gates.
If the shared skill is unavailable, stop and report the missing dependency.

Publish only from a clean, synchronized `main` branch. Releases are arm64,
ad-hoc-signed developer builds for macOS 26; they are not notarized.

## Automatic versioning

Do not ask the user for a version. The bundled script selects the next stable
semantic version from the latest reachable `vMAJOR.MINOR.PATCH` tag and the
changes since that tag:

- **Major:** a commit uses a conventional breaking subject such as
  `feat!:`/`feat(scope)!:` or includes a `BREAKING CHANGE:` trailer.
- **Minor:** a commit uses `feat:`/`feat(scope):`, or a runtime Swift change has
  an imperative feature subject beginning with Add, Implement, Introduce,
  Create, Support, Enable, or Expose.
- **Patch:** any other releasable change under `AgentQuota/` or to
  `AgentQuota.xcodeproj`.

If no stable tag exists, normalize the Xcode `MARKETING_VERSION` to three
components and use it for the first release (`1.0` becomes `1.0.0`). Do not
publish for documentation-, skill-, or test-only changes. Do not infer a
prerelease, accept a manual version override, or overwrite an existing tag or
release.

For deterministic classification, breaking app changes must use a `type!:`
subject or `BREAKING CHANGE:` trailer. Prefer conventional `feat:` subjects for
features; the imperative-subject fallback exists for this repository's current
commit style.

An explicit request to use this skill authorizes creation of the automatically
selected public GitHub Release. Use dry-run mode when the user asks to validate
versioning and packaging without publishing.

## Workflow

Run the bundled script from the repository root:

```bash
.agents/skills/build-release/scripts/build-release.zsh
```

For validation without a GitHub mutation:

```bash
.agents/skills/build-release/scripts/build-release.zsh --dry-run
```

The script owns the release sequence: repository and GitHub preflight,
automatic version selection, tests, isolated Release build, version injection,
signature and bundle validation, compressed read-only DMG creation and mounted
content validation, SHA-256 creation, and `gh release create`. The DMG opens as
a compact branded drag-to-install window with large `AgentQuota.app` and
Applications icons, a directional background, and persisted Finder layout
metadata generated without Finder automation. Do not duplicate those steps
manually or change project version files for a release.

Upload release assets without GitHub display labels so the Assets list shows
their complete filenames, including the version, platform, architecture, and
checksum suffix.

The script creates the release directly with `gh release create`; there is no
Actions publication run to monitor. Verify the selected tag's published GitHub
Release and DMG/checksum assets using the shared completion checks.
