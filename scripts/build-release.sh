#!/usr/bin/env bash
set -euo pipefail

TAG="${1:?usage: build-release.sh <tag>}"
REPO_DIR="${REPO_DIR:-/root/NodeGet}"
GITHUB_REPO="${GITHUB_REPO:-eeviriyi/NodeGet}"
ASSET_NAME="${ASSET_NAME:-nodeget-linux-x86_64.tar.gz}"

cd "$REPO_DIR"

echo "fetching tag $TAG"
git fetch --tags origin
git checkout --force "$TAG"

echo "building NodeGet binaries"
cargo +nightly build --release -p nodeget-server -p nodeget-agent

echo "packaging $ASSET_NAME"
rm -rf dist
mkdir -p dist/package
cp target/release/nodeget-server dist/package/
cp target/release/nodeget-agent dist/package/
tar -czf "dist/$ASSET_NAME" -C dist/package nodeget-server nodeget-agent
ls -lh "dist/$ASSET_NAME"

echo "publishing GitHub release $TAG"
if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "dist/$ASSET_NAME" --repo "$GITHUB_REPO" --clobber
else
  gh release create "$TAG" "dist/$ASSET_NAME" \
    --repo "$GITHUB_REPO" \
    --title "$TAG" \
    --notes "NodeGet binaries built on self-hosted release server."
fi

echo "release ready: https://github.com/$GITHUB_REPO/releases/tag/$TAG"
