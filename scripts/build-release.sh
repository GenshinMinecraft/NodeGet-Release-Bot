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
CROSS_BIN="${CROSS_BIN:-cross}"
RUST_TOOLCHAIN="${RUST_TOOLCHAIN:-nightly}"
CROSS_JOBS="${CROSS_JOBS:-$(nproc)}"
ENABLE_UPX="${ENABLE_UPX:-0}"
ENABLE_WINDOWS_GNU="${ENABLE_WINDOWS_GNU:-1}"
ALLOW_PARTIAL="${ALLOW_PARTIAL:-1}"

SERVER_TARGETS=(
  "x86_64-unknown-linux-musl|nodeget-server-linux-x86_64-musl|upx"
  "x86_64-unknown-linux-gnu|nodeget-server-linux-x86_64-gnu|upx"
  "arm-unknown-linux-gnueabi|nodeget-server-linux-arm-gnueabi|upx"
  "arm-unknown-linux-gnueabihf|nodeget-server-linux-arm-gnueabihf|upx"
  "aarch64-unknown-linux-gnu|nodeget-server-linux-aarch64-gnu|upx"
  "aarch64-unknown-linux-musl|nodeget-server-linux-aarch64-musl|upx"
  "armv7-unknown-linux-gnueabi|nodeget-server-linux-armv7-gnueabi|upx"
  "armv7-unknown-linux-gnueabihf|nodeget-server-linux-armv7-gnueabihf|upx"
  "armv7-unknown-linux-musleabi|nodeget-server-linux-armv7-musleabi|upx"
  "armv7-unknown-linux-musleabihf|nodeget-server-linux-armv7-musleabihf|upx"
)

AGENT_TARGETS=(
  "x86_64-unknown-linux-musl|nodeget-agent-linux-x86_64-musl|upx"
  "x86_64-unknown-linux-gnu|nodeget-agent-linux-x86_64-gnu|upx"
  "i686-unknown-linux-gnu|nodeget-agent-linux-i686-gnu|upx"
  "i686-unknown-linux-musl|nodeget-agent-linux-i686-musl|upx"
  "aarch64-unknown-linux-gnu|nodeget-agent-linux-aarch64-gnu|upx"
  "aarch64-unknown-linux-musl|nodeget-agent-linux-aarch64-musl|upx"
  "arm-unknown-linux-gnueabi|nodeget-agent-linux-arm-gnueabi|upx"
  "arm-unknown-linux-gnueabihf|nodeget-agent-linux-arm-gnueabihf|upx"
  "arm-unknown-linux-musleabi|nodeget-agent-linux-arm-musleabi|upx"
  "arm-unknown-linux-musleabihf|nodeget-agent-linux-arm-musleabihf|upx"
  "armv7-unknown-linux-gnueabi|nodeget-agent-linux-armv7-gnueabi|upx"
  "armv7-unknown-linux-gnueabihf|nodeget-agent-linux-armv7-gnueabihf|upx"
  "armv7-unknown-linux-musleabi|nodeget-agent-linux-armv7-musleabi|upx"
  "armv7-unknown-linux-musleabihf|nodeget-agent-linux-armv7-musleabihf|upx"
  "thumbv7neon-unknown-linux-gnueabihf|nodeget-agent-linux-thumbv7neon-gnueabihf|upx"
  "riscv64gc-unknown-linux-gnu|nodeget-agent-linux-riscv64gc-gnu|no-upx"
  "powerpc64-unknown-linux-gnu|nodeget-agent-linux-powerpc64-gnu|no-upx"
  "powerpc64le-unknown-linux-gnu|nodeget-agent-linux-powerpc64le-gnu|no-upx"
  "s390x-unknown-linux-gnu|nodeget-agent-linux-s390x-gnu|no-upx"
  "sparc64-unknown-linux-gnu|nodeget-agent-linux-sparc64-gnu|no-upx"
)

WINDOWS_TARGETS=(
  "nodeget-server|nodeget-server.exe|x86_64-pc-windows-gnu|nodeget-server-windows-x86_64.exe|upx"
  "nodeget-agent|nodeget-agent.exe|x86_64-pc-windows-gnu|nodeget-agent-windows-x86_64.exe|upx"
)

cd "$REPO_DIR"

echo "fetching tag $TAG"
git fetch --tags origin
git checkout --force "$TAG"

if ! command -v "$CROSS_BIN" >/dev/null 2>&1; then
  echo "error: cross is not installed or not in PATH" >&2
  echo "install it with: cargo install cross --git https://github.com/cross-rs/cross" >&2
  exit 127
fi

if ! command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
  echo "error: cross requires docker or podman" >&2
  exit 127
fi

if [ "$ENABLE_UPX" = "1" ] && ! command -v upx >/dev/null 2>&1; then
  echo "warning: ENABLE_UPX=1 but upx is not installed; continuing without compression" >&2
  ENABLE_UPX=0
fi

echo "cleaning previous build output"
cargo +"$RUST_TOOLCHAIN" clean
rm -rf dist
mkdir -p dist/artifacts
FAILED_TARGETS=()

build_one() {
  local package="$1"
  local source_name="$2"
  local target="$3"
  local output_name="$4"
  local upx_mode="$5"

  echo "building $package for $target -> $output_name"
  if ! RUSTUP_TOOLCHAIN="$RUST_TOOLCHAIN" "$CROSS_BIN" build \
    --package "$package" \
    --target "$target" \
    --profile minimal \
    --jobs "$CROSS_JOBS"; then
    echo "error: build failed for $package on $target" >&2
    return 1
  fi

  local built="target/$target/minimal/$source_name"
  if [ ! -f "$built" ]; then
    echo "error: expected binary not found: $built" >&2
    return 1
  fi

  if [ "$ENABLE_UPX" = "1" ] && [ "$upx_mode" = "upx" ]; then
    echo "compressing $built with upx"
    upx --brute "$built"
  fi

  cp "$built" "dist/artifacts/$output_name"
}

build_cargo_one() {
  local package="$1"
  local source_name="$2"
  local target="$3"
  local output_name="$4"
  local upx_mode="$5"

  echo "building $package for $target -> $output_name"
  if ! cargo +"$RUST_TOOLCHAIN" build \
    --package "$package" \
    --target "$target" \
    --profile minimal \
    --jobs "$CROSS_JOBS"; then
    echo "error: build failed for $package on $target" >&2
    return 1
  fi

  local built="target/$target/minimal/$source_name"
  if [ ! -f "$built" ]; then
    echo "error: expected binary not found: $built" >&2
    return 1
  fi

  if [ "$ENABLE_UPX" = "1" ] && [ "$upx_mode" = "upx" ]; then
    echo "compressing $built with upx"
    upx --brute "$built"
  fi

  cp "$built" "dist/artifacts/$output_name"
}

for item in "${SERVER_TARGETS[@]}"; do
  IFS='|' read -r target output_name upx_mode <<< "$item"
  if ! build_one "nodeget-server" "nodeget-server" "$target" "$output_name" "$upx_mode"; then
    FAILED_TARGETS+=("nodeget-server:$target")
    if [ "$ALLOW_PARTIAL" != "1" ]; then
      exit 1
    fi
  fi
done

for item in "${AGENT_TARGETS[@]}"; do
  IFS='|' read -r target output_name upx_mode <<< "$item"
  if ! build_one "nodeget-agent" "nodeget-agent" "$target" "$output_name" "$upx_mode"; then
    FAILED_TARGETS+=("nodeget-agent:$target")
    if [ "$ALLOW_PARTIAL" != "1" ]; then
      exit 1
    fi
  fi
done

if [ "$ENABLE_WINDOWS_GNU" = "1" ]; then
  if ! command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
    echo "warning: x86_64-w64-mingw32-gcc is not installed; skipping Windows GNU builds" >&2
    FAILED_TARGETS+=("windows:x86_64-pc-windows-gnu")
    if [ "$ALLOW_PARTIAL" != "1" ]; then
      exit 1
    fi
  else
    if ! rustup target add x86_64-pc-windows-gnu; then
      echo "warning: failed to install x86_64-pc-windows-gnu target; skipping Windows GNU builds" >&2
      FAILED_TARGETS+=("windows:x86_64-pc-windows-gnu")
      if [ "$ALLOW_PARTIAL" != "1" ]; then
        exit 1
      fi
    else
      for item in "${WINDOWS_TARGETS[@]}"; do
        IFS='|' read -r package source_name target output_name upx_mode <<< "$item"
        if ! build_cargo_one "$package" "$source_name" "$target" "$output_name" "$upx_mode"; then
          FAILED_TARGETS+=("$package:$target")
          if [ "$ALLOW_PARTIAL" != "1" ]; then
            exit 1
          fi
        fi
      done
    fi
  fi
fi

echo "built artifacts"
ls -lh dist/artifacts

if ! compgen -G "dist/artifacts/*" >/dev/null; then
  echo "error: no release artifacts were built" >&2
  exit 1
fi

if [ "${#FAILED_TARGETS[@]}" -gt 0 ]; then
  echo "warning: some targets failed and were skipped:" >&2
  printf '  - %s\n' "${FAILED_TARGETS[@]}" >&2
fi

echo "publishing GitHub release $TAG"
if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" dist/artifacts/* --repo "$GITHUB_REPO" --clobber
else
  gh release create "$TAG" dist/artifacts/* \
    --repo "$GITHUB_REPO" \
    --title "$TAG" \
    --notes "NodeGet Linux and Windows GNU binaries built on self-hosted release server."
fi

echo "release ready: https://github.com/$GITHUB_REPO/releases/tag/$TAG"
