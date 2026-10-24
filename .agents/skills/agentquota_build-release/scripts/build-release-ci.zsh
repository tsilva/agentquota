#!/bin/zsh

set -euo pipefail

fail() {
    print -u2 "error: $*"
    exit 1
}

[[ "${GITHUB_ACTIONS:-}" == "true" ]] || fail "Release builds run only in GitHub Actions; use build-release.zsh to dispatch"
[[ $# -eq 1 ]] || fail "Usage: build-release-ci.zsh ARTIFACT_DIRECTORY"
[[ "${RELEASE_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || fail "RELEASE_SHA must be a full commit SHA"
[[ "${RELEASE_PUBLISH:-}" == "true" || "${RELEASE_PUBLISH:-}" == "false" ]] || fail "RELEASE_PUBLISH must be true or false"
[[ -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_OUTPUT:-}" ]] || fail "GitHub Actions release context is missing"

for command_name in awk cmp codesign ditto gh git grep hdiutil head lipo plutil readlink shasum sips xcodebuild xcrun; do
    command -v "$command_name" >/dev/null 2>&1 || fail "Required command not found: $command_name"
done

script_directory="${0:A:h}"
repository_root="$(git -C "$script_directory" rev-parse --show-toplevel)"
background_renderer="${script_directory}/render-dmg-background.swift"
layout_template="${script_directory:h}/assets/dmg-layout.DS_Store"
[[ -f "$background_renderer" ]] || fail "DMG background renderer not found: ${background_renderer}"
[[ -f "$layout_template" ]] || fail "DMG Finder layout template not found: ${layout_template}"
artifact_directory="${1:A}"
[[ ! -e "$artifact_directory" ]] || fail "Artifact directory must be fresh: $artifact_directory"
cd "$repository_root"

[[ -z "$(git status --porcelain)" ]] || fail "The release checkout must be clean"
git fetch origin main --tags
head_sha="$(git rev-parse HEAD)"
[[ "$head_sha" == "$RELEASE_SHA" && "$head_sha" == "$(git rev-parse origin/main)" ]] \
    || fail "Release SHA must exactly match origin/main"

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
    if [[ -z "$releasable_changes" && "$RELEASE_PUBLISH" == "true" ]]; then
        fail "No releasable app changes exist after ${latest_release_tag}"
    fi

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
    if [[ -z "$releasable_changes" ]]; then
        release_version="${latest_release_tag#v}"
        version_reason="validation of current app; no new app release is needed"
    fi
fi

release_tag="v${release_version}"
print "Automatically selected ${release_tag}: ${version_reason}"

if [[ "$RELEASE_PUBLISH" == "true" ]]; then
    if git show-ref --verify --quiet "refs/tags/${release_tag}"; then
        fail "Tag already exists: ${release_tag}"
    fi
    release_tags="$(gh api --paginate "repos/${GITHUB_REPOSITORY}/releases" --jq '.[].tag_name')"
    if print -r -- "$release_tags" | grep -Fxq "$release_tag"; then
        fail "GitHub Release already exists: ${release_tag}"
    fi
fi

release_workspace="$(mktemp -d "${TMPDIR:-/tmp}/agentquota-release.XXXXXX")"
typeset -i dmg_attached=0
validation_mountpoint=""
cleanup() {
    if [[ $dmg_attached -eq 1 && -n "$validation_mountpoint" ]]; then
        hdiutil detach "$validation_mountpoint" >/dev/null 2>&1 || true
    fi
    if [[ -n "${release_workspace:-}" && -d "$release_workspace" ]]; then
        rm -rf -- "$release_workspace"
    fi
}
trap cleanup EXIT

derived_data_path="${release_workspace}/DerivedData"
output_directory="$artifact_directory"
dmg_source_directory="${release_workspace}/dmg-root"
validation_mountpoint="${release_workspace}/dmg-validation"
mkdir -p "$output_directory" "$dmg_source_directory/.background" "$validation_mountpoint"

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

artifact_name="AgentQuota-${release_version}-macOS-arm64.dmg"
artifact_path="${output_directory}/${artifact_name}"
checksum_path="${artifact_path}.sha256"
background_path="${dmg_source_directory}/.background/installer-background.png"
volume_name="AgentQuota Installer"

ditto "$app_path" "${dmg_source_directory}/AgentQuota.app"
ln -s /Applications "${dmg_source_directory}/Applications"
ditto "$layout_template" "${dmg_source_directory}/.DS_Store"
xcrun swift "$background_renderer" "$background_path" "$release_version"
background_width="$(sips -g pixelWidth "$background_path" | awk '/pixelWidth:/ { print $2 }')"
background_height="$(sips -g pixelHeight "$background_path" | awk '/pixelHeight:/ { print $2 }')"
[[ "$background_width" == "700" && "$background_height" == "440" ]] \
    || fail "Unexpected DMG background dimensions: ${background_width}x${background_height}"

hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$dmg_source_directory" \
    -format UDZO \
    -ov \
    "$artifact_path" >/dev/null
hdiutil verify "$artifact_path" >/dev/null
hdiutil attach \
    "$artifact_path" \
    -readonly \
    -nobrowse \
    -noautoopen \
    -mountpoint "$validation_mountpoint" >/dev/null
dmg_attached=1

packaged_app_path="${validation_mountpoint}/AgentQuota.app"
packaged_info_plist="${packaged_app_path}/Contents/Info.plist"
packaged_binary_path="${packaged_app_path}/Contents/MacOS/AgentQuota"
[[ -d "$packaged_app_path" ]] || fail "DMG does not contain AgentQuota.app"
[[ -L "${validation_mountpoint}/Applications" ]] || fail "DMG does not contain an Applications shortcut"
[[ -f "${validation_mountpoint}/.background/installer-background.png" ]] \
    || fail "DMG does not contain its Finder background"
[[ -f "${validation_mountpoint}/.DS_Store" ]] || fail "DMG does not contain its Finder layout metadata"
cmp -s "$layout_template" "${validation_mountpoint}/.DS_Store" \
    || fail "DMG Finder layout metadata differs from the validated template"
[[ "$(readlink "${validation_mountpoint}/Applications")" == "/Applications" ]] \
    || fail "DMG Applications shortcut has an unexpected target"
codesign --verify --deep --strict --verbose=2 "$packaged_app_path"
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$packaged_info_plist")" == "$release_version" ]] \
    || fail "DMG contains an unexpected app version"
[[ "$(lipo -archs "$packaged_binary_path")" == "arm64" ]] \
    || fail "DMG contains an app with an unexpected architecture"

hdiutil detach "$validation_mountpoint" >/dev/null
dmg_attached=0
(
    cd "$output_directory"
    shasum -a 256 "$artifact_name" > "${artifact_name}.sha256"
)

print "version=${release_version}" >> "$GITHUB_OUTPUT"
print "tag=${release_tag}" >> "$GITHUB_OUTPUT"
print "Validated ${release_tag} at ${head_sha}"
print "Artifact: ${artifact_path}"
print "Checksum: ${checksum_path}"
