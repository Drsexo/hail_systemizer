#!/usr/bin/env bash

set -euo pipefail

HAIL_OWNER="aistra0528"
HAIL_REPO="Hail"
HAIL_WORKFLOW="android.yml"
HAIL_BRANCH="master"

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODULE_DIR="$REPO_ROOT/module"
APK_DEST="$MODULE_DIR/system/priv-app/Hail/Hail.apk"

die() {
    local code="$1"; shift
    echo "::error::$*" >&2
    exit "$code"
}

gh_get() {
    local url="$1"
    local resp
    if ! resp=$(curl -fsSL \
        -H "Authorization: Bearer ${HAIL_TOKEN:?}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$url"); then
        die 2 "GitHub API call failed: $url"
    fi
    printf '%s' "$resp"
}

# Resolve latest successful Hail workflow run
echo ":: Resolving latest successful Hail workflow run"
RUN_JSON=$(gh_get \
    "https://api.github.com/repos/${HAIL_OWNER}/${HAIL_REPO}/actions/workflows/${HAIL_WORKFLOW}/runs?branch=${HAIL_BRANCH}&status=success&per_page=1")

RUN_COUNT=$(printf '%s' "$RUN_JSON" | jq '.workflow_runs | length')
if [ "$RUN_COUNT" -eq 0 ]; then
    die 2 "No successful runs found for ${HAIL_OWNER}/${HAIL_REPO} workflow ${HAIL_WORKFLOW}"
fi

RUN_NUMBER=$(printf '%s' "$RUN_JSON" | jq -r '.workflow_runs[0].run_number')
RUN_SHA=$(printf '%s' "$RUN_JSON" | jq -r '.workflow_runs[0].head_sha')
RUN_HTML_URL=$(printf '%s' "$RUN_JSON" | jq -r '.workflow_runs[0].html_url')
ARTIFACTS_URL=$(printf '%s' "$RUN_JSON" | jq -r '.workflow_runs[0].artifacts_url')
SHORT_SHA="${RUN_SHA:0:7}"

echo "   run #${RUN_NUMBER} sha=${SHORT_SHA}"

# Find first .apk artifact
ART_JSON=$(gh_get "$ARTIFACTS_URL")
ART_NAME=$(printf '%s' "$ART_JSON" | jq -r '.artifacts[] | select(.name | test("\\.apk$")) | .name' | head -n1)
ART_DL_URL=$(printf '%s' "$ART_JSON" | jq -r '.artifacts[] | select(.name | test("\\.apk$")) | .archive_download_url' | head -n1)
ART_SIZE=$(printf '%s' "$ART_JSON" | jq -r '.artifacts[] | select(.name | test("\\.apk$")) | .size_in_bytes' | head -n1)

if [ -z "$ART_NAME" ] || [ "$ART_NAME" = "null" ]; then
    die 2 "No .apk artifacts in run ${RUN_NUMBER}"
fi

echo ":: Artifact: ${ART_NAME} (${ART_SIZE} bytes)"

# Download the APK
echo ":: Downloading APK"
if ! curl -fsSL \
    -H "Authorization: Bearer ${HAIL_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "$ART_DL_URL" -o "$REPO_ROOT/Hail.apk"; then
    die 2 "Artifact download failed"
fi

# Parse version from filename
if [[ "$ART_NAME" =~ ^Hail-(v[0-9]+(\.[0-9]+)*(-[^.]+)?)\.apk$ ]]; then
    VERSION="${BASH_REMATCH[1]}"
    SEMVER=$(printf '%s' "$VERSION" | grep -oE 'v[0-9]+(\.[0-9]+)*' | tr -d 'v.')
else
    die 3 "APK filename does not match expected pattern: ${ART_NAME}"
fi

RUN_NUM="${GITHUB_RUN_NUMBER:-0}"
VERSION_CODE=$((RUN_NUM + 1000000))

echo ":: version=${VERSION} versionCode=${VERSION_CODE} (run=${RUN_NUM})"

# Build metadata
NOW_UTC=$(date -u +"%Y-%m-%d %H:%M UTC")
BUILD_DATE=$(date -u +"%Y%m%d")

THIS_REPO="${GITHUB_REPOSITORY:-DrSexo/hail_systemizer}"
ZIP_NAME="hail_systemizer-${VERSION}-${BUILD_DATE}.zip"
ZIP_URL="https://github.com/${THIS_REPO}/releases/download/${VERSION}/${ZIP_NAME}"
CHANGELOG_URL="https://raw.githubusercontent.com/${THIS_REPO}/main/CHANGELOG.md"

# Install APK into module
echo ":: Installing APK into module"
mkdir -p "$(dirname "$APK_DEST")"
cp "$REPO_ROOT/Hail.apk" "$APK_DEST"

# Render module.prop
echo ":: Rendering module.prop and update.json"
sed -i \
    -e "s/PLACEHOLDER_VERSION_CODE/${VERSION_CODE}/g" \
    -e "s/PLACEHOLDER_VERSION/${VERSION}/g" \
    "$MODULE_DIR/module.prop"

sed -i \
    -e "s/PLACEHOLDER_VERSION_CODE/${VERSION_CODE}/g" \
    -e "s/PLACEHOLDER_VERSION/${VERSION}/g" \
    -e "s|PLACEHOLDER_ZIP_URL|${ZIP_URL}|g" \
    -e "s|PLACEHOLDER_CHANGELOG_URL|${CHANGELOG_URL}|g" \
    "$MODULE_DIR/update.json"

echo ":: Generating CHANGELOG.md"
cat > "$REPO_ROOT/CHANGELOG.md" <<EOF
# Changelog

## ${VERSION} - ${NOW_UTC}

- Hail APK: [${SHORT_SHA}](https://github.com/${HAIL_OWNER}/${HAIL_REPO}/commit/${RUN_SHA})
- Workflow run: [#${RUN_NUMBER}](${RUN_HTML_URL})
EOF

# Validate update.json
JQ_ERR=$(jq empty "$MODULE_DIR/update.json" 2>&1 >/dev/null) || {
    echo "::group::Rendered update.json content (DEBUG)"
    cat "$MODULE_DIR/update.json"
    echo ""
    echo "--- hexdump ---"
    od -A x -t x1z -v "$MODULE_DIR/update.json" | head -20
    echo "::endgroup::"
    die 1 "Rendered update.json is not valid JSON: ${JQ_ERR}"
}
VC_TYPE=$(jq -r '.versionCode | type' "$MODULE_DIR/update.json")
if [ "$VC_TYPE" != "number" ]; then
    die 1 "Rendered update.json versionCode is ${VC_TYPE}, must be number"
fi

# Build the module zip
echo ":: Building module zip"
(
    cd "$MODULE_DIR"
    rm -f "$REPO_ROOT/${ZIP_NAME}"
    find . \( -type d -o -type f \) \
        ! -name '.gitkeep' \
        ! -name 'README.md' \
        ! -name 'update.json' \
        -print0 \
        | xargs -0 zip -q "$REPO_ROOT/${ZIP_NAME}"
)
ZIP_PATH="$REPO_ROOT/${ZIP_NAME}"

if [ ! -f "$ZIP_PATH" ]; then
    die 1 "Failed to build zip at ${ZIP_PATH}"
fi
echo ":: Wrote ${ZIP_PATH}"

# Release
RELEASE_TITLE="${VERSION#v}"
RELEASE_BODY=$(cat <<EOF
[${SHORT_SHA}](https://github.com/${HAIL_OWNER}/${HAIL_REPO}/commit/${RUN_SHA}) [#${RUN_NUMBER}](${RUN_HTML_URL})
Built: ${NOW_UTC}
EOF
)

# Write step outputs
if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "release_title=${RELEASE_TITLE}"
        echo "release_body<<EOF"
        echo "${RELEASE_BODY}"
        echo "EOF"
        echo "zip_path=${ZIP_PATH}"
        echo "zip_name=${ZIP_NAME}"
        echo "release_tag=${VERSION}"
        echo "version=${VERSION}"
        echo "version_code=${VERSION_CODE}"
    } >> "$GITHUB_OUTPUT"
fi

echo "::release_title=${RELEASE_TITLE}"
echo "::release_tag=${VERSION}"