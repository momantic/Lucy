#!/bin/zsh
set -euo pipefail

# Replace the GitHub Release download asset that Lucy's live install page uses.
#
# Required auth:
#   GITHUB_TOKEN or GH_TOKEN with repo/content release permissions.
#
# Example:
#   GITHUB_TOKEN="ghp_..." zsh ./publish_lucy_release_asset.sh

OWNER="${GITHUB_OWNER:-momantic}"
REPO="${GITHUB_REPO:-Lucy}"
TAG="${LUCY_RELEASE_VERSION:-v0.1-beta}"
ASSET_PATH="${LUCY_RELEASE_ZIP:-release/Lucy-${TAG}.zip}"
ASSET_NAME="$(basename "$ASSET_PATH")"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
API_ROOT="https://api.github.com"

if [ -z "$TOKEN" ]; then
  cat >&2 <<ERROR
Missing GitHub auth token.

Set GITHUB_TOKEN or GH_TOKEN to a GitHub token that can edit releases for:
  ${OWNER}/${REPO}

Then rerun:
  GITHUB_TOKEN="..." zsh ./publish_lucy_release_asset.sh
ERROR
  exit 2
fi

if [ ! -f "$ASSET_PATH" ]; then
  echo "Release ZIP not found: $ASSET_PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to parse GitHub API responses." >&2
  exit 1
fi

echo "Looking up GitHub release: ${OWNER}/${REPO}@${TAG}"
release_json="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "$API_ROOT/repos/$OWNER/$REPO/releases/tags/$TAG")"

release_id="$(jq -r '.id' <<<"$release_json")"
if [ -z "$release_id" ] || [ "$release_id" = "null" ]; then
  echo "Could not resolve release id for tag: $TAG" >&2
  exit 1
fi

existing_asset_id="$(jq -r --arg name "$ASSET_NAME" '.assets[]? | select(.name == $name) | .id' <<<"$release_json" | head -1)"
if [ -n "$existing_asset_id" ] && [ "$existing_asset_id" != "null" ]; then
  echo "Deleting existing release asset: $ASSET_NAME ($existing_asset_id)"
  curl -fsSL -X DELETE \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API_ROOT/repos/$OWNER/$REPO/releases/assets/$existing_asset_id" >/dev/null
fi

size="$(wc -c < "$ASSET_PATH" | tr -d ' ')"
sha256="$(shasum -a 256 "$ASSET_PATH" | awk '{print $1}')"

echo "Uploading $ASSET_PATH as $ASSET_NAME"
echo "Size: ${size} bytes"
echo "SHA-256: ${sha256}"

upload_json="$(curl -fsSL -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Content-Type: application/zip" \
  --data-binary "@$ASSET_PATH" \
  "https://uploads.github.com/repos/$OWNER/$REPO/releases/$release_id/assets?name=$ASSET_NAME")"

download_url="$(jq -r '.browser_download_url' <<<"$upload_json")"

cat <<DONE
Published Lucy release asset.

Download URL:
$download_url

SHA-256:
$sha256
DONE