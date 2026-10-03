---
name: build-release
description: Dispatch, monitor, and verify automatically versioned AgentQuota releases built and published in GitHub Actions. Use for AgentQuota release requests, not ordinary local builds or installation.
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

Do not ask the user for a version. The Actions build helper selects the next stable
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

All release tests, compilation, signing, DMG packaging, artifact validation, and
publication run in `.github/workflows/release.yml`. The operator machine needs
only Git and authenticated `gh`; do not run Xcode or the build helper locally.
Editing release instructions does not authorize publication.

From a clean `main` synchronized with `origin/main`, dispatch publication:

```bash
.agents/skills/build-release/scripts/build-release.zsh
```

For validation without creating a tag or GitHub Release:

```bash
.agents/skills/build-release/scripts/build-release.zsh --dry-run
```

The launcher submits the exact full commit SHA with `publish=true` or `false`.
Both modes run in Actions. Manual dispatch defaults to `publish=false` and must
use the workflow on `main` with the same full SHA as `origin/main`. When there
are no app changes since the latest release, validation rebuilds that version;
publication fails without creating a new release. Do not change project version
files or create a tag locally.

The macOS job uses the same macOS 26 / Xcode 26.6 toolchain as CI. Its
`scripts/build-release-ci.zsh` helper owns automatic versioning, tests, an
isolated Release build, version injection, signature and bundle checks, DMG
creation and mounted-content validation, and SHA-256 creation. The DMG retains
its branded drag-to-install background and persisted Finder layout. The job
uploads its validated DMG and checksum as `agentquota-<full-sha>`.

Only the separate publication job has `contents: write`. It downloads those
exact artifacts, verifies their filenames and checksum, confirms that `main`
still matches the release SHA and the tag/version remain unused, then creates
the tag and GitHub Release. Upload assets without GitHub display labels so the
Assets list shows their complete filenames. Never rebuild between validation
and publication or substitute assets from another run.

## Monitor and verify

Follow the shared monitoring procedure for the `release.yml`
`workflow_dispatch` run on `main` at the dispatched full SHA. Inspect its inputs
when distinguishing validation from publication. Require the build job and,
for publication, the publish job to succeed; dispatch alone is not completion.

On failure, report the exact failed job and run URL. Preserve existing releases
and do not automatically repeat publication. A published release whose final
verification failed remains incomplete and needs inspection.

The publication job verifies the tag's exact source SHA and downloads fresh
copies of `AgentQuota-<version>-macOS-arm64.dmg` and its `.sha256` file. It
compares the published checksum with the validated candidate and checks the
fresh DMG against it. Require that verification before reporting success.
Report the release URL, version/tag, full SHA, workflow URL, asset names, and
ad-hoc signing / non-notarization status. For validation, report the successful
run and its artifact download location and state that nothing was published.
