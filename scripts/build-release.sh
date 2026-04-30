#!/usr/bin/env bash
set -euo pipefail

# systemd services can run with a very small environment. Keep Rust tooling
# paths explicit so the build works outside an interactive shell.
export HOME="${HOME:-/root}"
export CARGO_HOME="${CARGO_HOME:-/root/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-/root/.rustup}"
export PATH="$CARGO_HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

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
