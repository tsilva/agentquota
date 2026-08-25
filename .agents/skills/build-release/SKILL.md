---
name: build-release
description: Automatically version, build, verify, package, and publish AgentQuota as a public GitHub Release. Use for AgentQuota release requests, not ordinary local builds or installation.
---

# Build Release

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
signature and bundle validation, ZIP and SHA-256 creation, and
`gh release create`. Do not duplicate those steps manually or change project
version files for a release.

If any preflight, test, build, validation, upload, or publication step fails,
stop and report the exact failure. Do not delete or replace tags/releases, force
push, weaken validation, or publish a different version as a workaround.

## Completion

Report the release version, commit SHA, test/build result, artifact names,
architecture and signing/notarization status, and the GitHub Release URL. For a
dry run, state clearly that nothing was published.
