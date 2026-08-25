#!/bin/zsh

set -euo pipefail

program_name="${0:t}"

usage() {
    print -u2 "Usage: ${program_name} [--dry-run]"
    print -u2 "The release version is selected automatically from Git history."
}

fail() {
    print -u2 "error: $*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

typeset -i dry_run=0
case "${1:-}" in
    --dry-run)
        dry_run=1
        shift
        ;;
    -h|--help)
        usage
        exit 0
        ;;
esac

if [[ $# -ne 0 ]]; then
    usage
    fail "Version arguments are not accepted; versioning is automatic"
fi

for command_name in awk codesign ditto gh git grep head lipo plutil shasum unzip xcodebuild; do
    require_command "$command_name"
done

script_directory="${0:A:h}"
repository_root="$(git -C "$script_directory" rev-parse --show-toplevel)"
cd "$repository_root"

[[ "$(git branch --show-current)" == "main" ]] || fail "Releases must be built from main"

if [[ $dry_run -eq 0 && -n "$(git status --porcelain)" ]]; then
    fail "The worktree must be clean before publishing"
fi

gh auth status --hostname github.com >/dev/null
git fetch origin main --tags

head_sha="$(git rev-parse HEAD)"
origin_main_sha="$(git rev-parse origin/main)"
[[ "$head_sha" == "$origin_main_sha" ]] || fail "Local main must exactly match origin/main"

latest_release_tag="$(
    git tag --list 'v*' --sort=-version:refname \
        | grep -E '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' \
        | head -n 1 \
        || true
)"

if [[ -z "$latest_release_tag" ]]; then
    project_marketing_version="$(
        xcodebuild \
            -project AgentQuota.xcodeproj \
            -scheme AgentQuota \
            -configuration Release \
            -showBuildSettings 2>/dev/null \
            | awk '$1 == "MARKETING_VERSION" && $2 == "=" { print $3; exit }'
    )"

    if print -r -- "$project_marketing_version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
        release_version="$project_marketing_version"
    elif print -r -- "$project_marketing_version" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
        release_version="${project_marketing_version}.0"
    else
        fail "Xcode MARKETING_VERSION must be MAJOR.MINOR or MAJOR.MINOR.PATCH; found: ${project_marketing_version:-<empty>}"
    fi
    version_reason="first release, normalized from Xcode MARKETING_VERSION ${project_marketing_version}"
else
    git merge-base --is-ancestor "$latest_release_tag" HEAD \
        || fail "Latest version tag ${latest_release_tag} is not an ancestor of HEAD"

    changed_files="$(git diff --name-only "${latest_release_tag}..HEAD")"
    releasable_changes="$(
        print -r -- "$changed_files" \
            | grep -E '^(AgentQuota/|AgentQuota\.xcodeproj/)' \
            || true
    )"
    [[ -n "$releasable_changes" ]] \
        || fail "No releasable app changes exist after ${latest_release_tag}"

    commit_subjects="$(git log --format='%s' "${latest_release_tag}..HEAD")"
    commit_messages="$(git log --format='%s%n%b%n' "${latest_release_tag}..HEAD")"

    version_bump="patch"
    version_reason="other app or Xcode project changes after ${latest_release_tag}"

    if print -r -- "$commit_messages" \
        | grep -Eiq '^(BREAKING[ -]CHANGE:|[[:alnum:]_-]+(\([^)]*\))?!:)'; then
        version_bump="major"
        version_reason="breaking-change commit marker after ${latest_release_tag}"
    elif print -r -- "$commit_subjects" \
        | grep -Eiq '^feat(\([^)]*\))?:'; then
        version_bump="minor"
        version_reason="conventional feature commit after ${latest_release_tag}"
    elif print -r -- "$changed_files" | grep -Eq '^AgentQuota/.*\.swift$' \
        && print -r -- "$commit_subjects" \
            | grep -Eiq '^(Add|Implement|Introduce|Create|Support|Enable|Expose)([[:space:]:]|$)'; then
        version_bump="minor"
        version_reason="feature-style runtime Swift change after ${latest_release_tag}"
    fi

    version_components="${latest_release_tag#v}"
    IFS=. read -r version_major version_minor version_patch <<< "$version_components"
    case "$version_bump" in
        major)
            release_version="$((version_major + 1)).0.0"
            ;;
        minor)
            release_version="${version_major}.$((version_minor + 1)).0"
            ;;
        patch)
            release_version="${version_major}.${version_minor}.$((version_patch + 1))"
            ;;
    esac
fi

release_tag="v${release_version}"
print "Automatically selected ${release_tag}: ${version_reason}"

if git show-ref --verify --quiet "refs/tags/${release_tag}"; then
    fail "Tag already exists: ${release_tag}"
fi

repository_slug="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
if gh release view "$release_tag" --repo "$repository_slug" >/dev/null 2>&1; then
    fail "GitHub Release already exists: ${release_tag}"
fi

release_workspace="$(mktemp -d "${TMPDIR:-/tmp}/agentquota-release.XXXXXX")"
cleanup() {
    if [[ -n "${release_workspace:-}" && -d "$release_workspace" ]]; then
        rm -rf -- "$release_workspace"
    fi
}
trap cleanup EXIT

derived_data_path="${release_workspace}/DerivedData"
output_directory="${release_workspace}/output"
mkdir -p "$output_directory"

print "Testing AgentQuota at ${head_sha}"
xcodebuild test \
    -project AgentQuota.xcodeproj \
    -scheme AgentQuota \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data_path" \
    -quiet

build_number="$(git rev-list --count HEAD)"
print "Building AgentQuota ${release_version} (${build_number})"
xcodebuild build \
    -project AgentQuota.xcodeproj \
    -scheme AgentQuota \
    -configuration Release \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$derived_data_path" \
    -quiet \
    MARKETING_VERSION="$release_version" \
    CURRENT_PROJECT_VERSION="$build_number"

app_path="${derived_data_path}/Build/Products/Release/AgentQuota.app"
info_plist="${app_path}/Contents/Info.plist"
binary_path="${app_path}/Contents/MacOS/AgentQuota"
[[ -d "$app_path" ]] || fail "Release app was not produced at ${app_path}"

codesign --verify --deep --strict --verbose=2 "$app_path"

bundle_identifier="$(plutil -extract CFBundleIdentifier raw -o - "$info_plist")"
bundle_version="$(plutil -extract CFBundleShortVersionString raw -o - "$info_plist")"
bundle_build="$(plutil -extract CFBundleVersion raw -o - "$info_plist")"
is_menu_bar_app="$(plutil -extract LSUIElement raw -o - "$info_plist")"
binary_architectures="$(lipo -archs "$binary_path")"

[[ "$bundle_identifier" == "com.tsilva.AgentQuota" ]] || fail "Unexpected bundle identifier: ${bundle_identifier}"
[[ "$bundle_version" == "$release_version" ]] || fail "Unexpected bundle version: ${bundle_version}"
[[ "$bundle_build" == "$build_number" ]] || fail "Unexpected bundle build: ${bundle_build}"
[[ "$is_menu_bar_app" == "true" ]] || fail "LSUIElement is not enabled"
[[ "$binary_architectures" == "arm64" ]] || fail "Expected arm64 binary, found: ${binary_architectures}"

artifact_name="AgentQuota-${release_version}-macOS-arm64.zip"
artifact_path="${output_directory}/${artifact_name}"
checksum_path="${artifact_path}.sha256"

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$artifact_path"
unzip -t "$artifact_path" >/dev/null
(
    cd "$output_directory"
    shasum -a 256 "$artifact_name" > "${artifact_name}.sha256"
)

if [[ $dry_run -eq 1 ]]; then
    print "Dry run passed for automatically selected ${release_tag}; nothing was published."
    print "Artifact: ${artifact_name}"
    print "Checksum: ${artifact_name}.sha256"
    exit 0
fi

release_notice=$'Developer build for Apple silicon Macs running macOS 26. This app is ad-hoc signed and not notarized, so macOS may require opening it via right-click > Open or allowing it in System Settings > Privacy & Security.\n\nInstall the Codex CLI and run `codex login` before launching AgentQuota.'

print "Publishing ${release_tag} to ${repository_slug}"
gh release create "$release_tag" \
    "$artifact_path#AgentQuota ${release_version} for macOS arm64" \
    "$checksum_path#SHA-256 checksum" \
    --repo "$repository_slug" \
    --target "$head_sha" \
    --title "AgentQuota ${release_version}" \
    --generate-notes \
    --notes "$release_notice" \
    --fail-on-no-commits \
    --latest

release_url="$(gh release view "$release_tag" --repo "$repository_slug" --json url --jq '.url')"
print "Published ${release_tag}: ${release_url}"
