#!/bin/zsh

set -euo pipefail

fail() {
    print -u2 "error: $*"
    exit 1
}

publish=true
case "${1:-}" in
    --dry-run)
        publish=false
        shift
        ;;
    -h|--help)
        print "Usage: ${0:t} [--dry-run]"
        print "Dispatch an AgentQuota release in GitHub Actions; --dry-run validates without publishing."
        exit 0
        ;;
esac
[[ $# -eq 0 ]] || fail "Version arguments are not accepted; versioning is automatic"

for command_name in gh git; do
    command -v "$command_name" >/dev/null 2>&1 || fail "Required command not found: $command_name"
done
script_directory="${0:A:h}"
repository_root="$(git -C "$script_directory" rev-parse --show-toplevel)"
cd "$repository_root"
[[ "$(git branch --show-current)" == "main" ]] || fail "Dispatch releases from main"
[[ -z "$(git status --porcelain)" ]] || fail "The worktree must be clean before dispatch"
gh auth status --hostname github.com >/dev/null
git fetch origin main --tags
release_sha="$(git rev-parse HEAD)"
[[ "$release_sha" == "$(git rev-parse origin/main)" ]] || fail "Local main must exactly match origin/main"
repository_slug="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"

gh workflow run release.yml --repo "$repository_slug" --ref main \
    -f ref="$release_sha" -f publish="$publish"
print "Dispatched release.yml for ${repository_slug} at ${release_sha} (publish=${publish})."
print "Follow the workflow_dispatch run for this exact SHA; dispatch alone does not prove success."
