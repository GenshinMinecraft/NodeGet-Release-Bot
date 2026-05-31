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
GITHUB_REPO="${GITHUB_REPO:?GITHUB_REPO is required, for example owner/NodeGet}"
CROSS_BIN="${CROSS_BIN:-cross}"
RUST_TOOLCHAIN="${RUST_TOOLCHAIN:-nightly}"
CROSS_JOBS="${CROSS_JOBS:-8}"
BUILD_CONCURRENCY="${BUILD_CONCURRENCY:-8}"
CLEAN_BUILD="${CLEAN_BUILD:-0}"
ENABLE_UPX="${ENABLE_UPX:-1}"
BUILD_TARGET_SET="${BUILD_TARGET_SET:-all}"
ALLOW_PARTIAL="${ALLOW_PARTIAL:-1}"
BUILD_LOG_DIR="${BUILD_LOG_DIR:-dist/logs}"

case "$BUILD_TARGET_SET" in
  all|linux|linux-x86_64|windows) ;;
  *)
    echo "error: BUILD_TARGET_SET must be one of: all, linux, linux-x86_64, windows" >&2
    exit 2
    ;;
esac

if ! [[ "$BUILD_CONCURRENCY" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: BUILD_CONCURRENCY must be a positive integer" >&2
  exit 2
fi

if ! [[ "$CROSS_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: CROSS_JOBS must be a positive integer" >&2
  exit 2
fi

BUILD_TASKS=(
  "linux|cross|nodeget-server|nodeget-server|x86_64-unknown-linux-musl|nodeget-server-linux-x86_64-musl|upx"
  "linux,linux-x86_64|cross|nodeget-server|nodeget-server|x86_64-unknown-linux-gnu|nodeget-server-linux-x86_64-gnu|upx"
  "linux|cross|nodeget-server|nodeget-server|arm-unknown-linux-gnueabi|nodeget-server-linux-arm-gnueabi|upx"
  "linux|cross|nodeget-server|nodeget-server|arm-unknown-linux-gnueabihf|nodeget-server-linux-arm-gnueabihf|upx"
  "linux|cross|nodeget-server|nodeget-server|aarch64-unknown-linux-gnu|nodeget-server-linux-aarch64-gnu|upx"
  "linux|cross|nodeget-server|nodeget-server|aarch64-unknown-linux-musl|nodeget-server-linux-aarch64-musl|upx"
  "linux|cross|nodeget-server|nodeget-server|armv7-unknown-linux-gnueabi|nodeget-server-linux-armv7-gnueabi|upx"
  "linux|cross|nodeget-server|nodeget-server|armv7-unknown-linux-gnueabihf|nodeget-server-linux-armv7-gnueabihf|upx"
  "linux|cross|nodeget-server|nodeget-server|armv7-unknown-linux-musleabi|nodeget-server-linux-armv7-musleabi|upx"
  "linux|cross|nodeget-server|nodeget-server|armv7-unknown-linux-musleabihf|nodeget-server-linux-armv7-musleabihf|upx"
  "linux|cross|nodeget-agent|nodeget-agent|x86_64-unknown-linux-musl|nodeget-agent-linux-x86_64-musl|upx"
  "linux,linux-x86_64|cross|nodeget-agent|nodeget-agent|x86_64-unknown-linux-gnu|nodeget-agent-linux-x86_64-gnu|upx"
  "linux|cross|nodeget-agent|nodeget-agent|i686-unknown-linux-gnu|nodeget-agent-linux-i686-gnu|upx"
  "linux|cross|nodeget-agent|nodeget-agent|i686-unknown-linux-musl|nodeget-agent-linux-i686-musl|upx"
  "linux|cross|nodeget-agent|nodeget-agent|aarch64-unknown-linux-gnu|nodeget-agent-linux-aarch64-gnu|upx"
  "linux|cross|nodeget-agent|nodeget-agent|aarch64-unknown-linux-musl|nodeget-agent-linux-aarch64-musl|upx"
  "linux|cross|nodeget-agent|nodeget-agent|arm-unknown-linux-gnueabi|nodeget-agent-linux-arm-gnueabi|upx"
  "linux|cross|nodeget-agent|nodeget-agent|arm-unknown-linux-gnueabihf|nodeget-agent-linux-arm-gnueabihf|upx"
  "linux|cross|nodeget-agent|nodeget-agent|arm-unknown-linux-musleabi|nodeget-agent-linux-arm-musleabi|upx"
  "linux|cross|nodeget-agent|nodeget-agent|arm-unknown-linux-musleabihf|nodeget-agent-linux-arm-musleabihf|upx"
  "linux|cross|nodeget-agent|nodeget-agent|armv7-unknown-linux-gnueabi|nodeget-agent-linux-armv7-gnueabi|upx"
  "linux|cross|nodeget-agent|nodeget-agent|armv7-unknown-linux-gnueabihf|nodeget-agent-linux-armv7-gnueabihf|upx"
  "linux|cross|nodeget-agent|nodeget-agent|armv7-unknown-linux-musleabi|nodeget-agent-linux-armv7-musleabi|upx"
  "linux|cross|nodeget-agent|nodeget-agent|armv7-unknown-linux-musleabihf|nodeget-agent-linux-armv7-musleabihf|upx"
  "linux|cross|nodeget-agent|nodeget-agent|thumbv7neon-unknown-linux-gnueabihf|nodeget-agent-linux-thumbv7neon-gnueabihf|upx"
  "linux|cross|nodeget-agent|nodeget-agent|riscv64gc-unknown-linux-gnu|nodeget-agent-linux-riscv64gc-gnu|no-upx"
  "linux|cross|nodeget-agent|nodeget-agent|powerpc64-unknown-linux-gnu|nodeget-agent-linux-powerpc64-gnu|no-upx"
  "linux|cross|nodeget-agent|nodeget-agent|powerpc64le-unknown-linux-gnu|nodeget-agent-linux-powerpc64le-gnu|no-upx"
  "linux|cross|nodeget-agent|nodeget-agent|s390x-unknown-linux-gnu|nodeget-agent-linux-s390x-gnu|no-upx"
  "linux|cross|nodeget-agent|nodeget-agent|sparc64-unknown-linux-gnu|nodeget-agent-linux-sparc64-gnu|no-upx"
  "windows|cargo|nodeget-server|nodeget-server.exe|x86_64-pc-windows-gnu|nodeget-server-windows-x86_64.exe|upx"
  "windows|cargo|nodeget-agent|nodeget-agent.exe|x86_64-pc-windows-gnu|nodeget-agent-windows-x86_64.exe|upx"
)

cd "$REPO_DIR"

echo "fetching tag $TAG"
git fetch --tags origin
git checkout --force "$TAG"

if [ "$BUILD_TARGET_SET" = "all" ] || [ "$BUILD_TARGET_SET" = "linux" ] || [ "$BUILD_TARGET_SET" = "linux-x86_64" ]; then
  if ! command -v "$CROSS_BIN" >/dev/null 2>&1; then
    echo "error: cross is not installed or not in PATH" >&2
    echo "install it with: cargo install cross --git https://github.com/cross-rs/cross" >&2
    exit 127
  fi

  if ! command -v docker >/dev/null 2>&1 && ! command -v podman >/dev/null 2>&1; then
    echo "error: cross requires docker or podman" >&2
    exit 127
  fi
fi

if [ "$ENABLE_UPX" = "1" ] && ! command -v upx >/dev/null 2>&1; then
  echo "warning: ENABLE_UPX=1 but upx is not installed; continuing without compression" >&2
  ENABLE_UPX=0
fi

FAILED_TARGETS=()
FAILED_LOGS=()
WINDOWS_GNU_READY=0
if [ "$BUILD_TARGET_SET" = "all" ] || [ "$BUILD_TARGET_SET" = "windows" ]; then
  if ! command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
    echo "warning: x86_64-w64-mingw32-gcc is not installed; skipping Windows GNU builds" >&2
    FAILED_TARGETS+=("windows:x86_64-pc-windows-gnu")
    if [ "$ALLOW_PARTIAL" != "1" ]; then
      exit 1
    fi
  elif ! rustup target add x86_64-pc-windows-gnu --toolchain "$RUST_TOOLCHAIN"; then
    echo "warning: failed to install x86_64-pc-windows-gnu target; skipping Windows GNU builds" >&2
    FAILED_TARGETS+=("windows:x86_64-pc-windows-gnu")
    if [ "$ALLOW_PARTIAL" != "1" ]; then
      exit 1
    fi
  else
    WINDOWS_GNU_READY=1
  fi
fi

echo "preparing build output"
if [ "$CLEAN_BUILD" = "1" ]; then
  echo "cleaning cargo target cache"
  cargo +"$RUST_TOOLCHAIN" clean
else
  echo "keeping cargo target cache"
fi
rm -rf dist
mkdir -p dist/artifacts "$BUILD_LOG_DIR"
RUNNING_PIDS=()
RUNNING_NAMES=()
RUNNING_LOGS=()

build_artifact() {
  local builder="$1"
  local package="$2"
  local source_name="$3"
  local target="$4"
  local output_name="$5"
  local upx_mode="$6"

  local target_dir="target-parallel/${output_name}"

  echo "building $package for $target -> $output_name (target-dir: $target_dir)"
  case "$builder" in
    cross)
      RUSTUP_TOOLCHAIN="$RUST_TOOLCHAIN" "$CROSS_BIN" build \
        --package "$package" \
        --target "$target" \
        --target-dir "$target_dir" \
        --profile minimal \
        --jobs "$CROSS_JOBS"
      ;;
    cargo)
      cargo +"$RUST_TOOLCHAIN" build \
        --package "$package" \
        --target "$target" \
        --target-dir "$target_dir" \
        --profile minimal \
        --jobs "$CROSS_JOBS"
      ;;
    *)
      echo "error: unknown builder: $builder" >&2
      return 2
      ;;
  esac || {
    echo "error: build failed for $package on $target" >&2
    return 1
  }

  local built="$target_dir/$target/minimal/$source_name"
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

stop_running_builds() {
  if [ "${#RUNNING_PIDS[@]}" -eq 0 ]; then
    return
  fi

  echo "stopping remaining build tasks" >&2
  kill "${RUNNING_PIDS[@]}" >/dev/null 2>&1 || true
}

wait_for_next_task() {
  local done_pid=""
  local status=0
  local index=-1
  local task_name=""
  local task_log=""

  if [ "${#RUNNING_PIDS[@]}" -eq 0 ]; then
    return
  fi

  set +e
  wait -n -p done_pid "${RUNNING_PIDS[@]}"
  status=$?
  set -e

  for i in "${!RUNNING_PIDS[@]}"; do
    if [ "${RUNNING_PIDS[$i]}" = "$done_pid" ]; then
      index="$i"
      task_name="${RUNNING_NAMES[$i]}"
      task_log="${RUNNING_LOGS[$i]}"
      break
    fi
  done

  if [ "$index" -lt 0 ]; then
    echo "warning: finished unknown build task pid=$done_pid status=$status" >&2
    return
  fi

  unset "RUNNING_PIDS[$index]"
  unset "RUNNING_NAMES[$index]"
  unset "RUNNING_LOGS[$index]"
  RUNNING_PIDS=("${RUNNING_PIDS[@]}")
  RUNNING_NAMES=("${RUNNING_NAMES[@]}")
  RUNNING_LOGS=("${RUNNING_LOGS[@]}")

  if [ "$status" -eq 0 ]; then
    echo "finished $task_name"
    return
  fi

  echo "failed $task_name; see $task_log" >&2
  FAILED_TARGETS+=("$task_name")
  FAILED_LOGS+=("$task_log")

  if [ "$ALLOW_PARTIAL" != "1" ]; then
    stop_running_builds
    exit 1
  fi
}

queue_build() {
  local builder="$1"
  local package="$2"
  local source_name="$3"
  local target="$4"
  local output_name="$5"
  local upx_mode="$6"
  local task_name="$package:$target"
  local task_log="$BUILD_LOG_DIR/$output_name.log"

  echo "queued $task_name -> $output_name (log: $task_log)"
  build_artifact "$builder" "$package" "$source_name" "$target" "$output_name" "$upx_mode" >"$task_log" 2>&1 &
  RUNNING_PIDS+=("$!")
  RUNNING_NAMES+=("$task_name")
  RUNNING_LOGS+=("$task_log")

  while [ "${#RUNNING_PIDS[@]}" -ge "$BUILD_CONCURRENCY" ]; do
    wait_for_next_task
  done
}

wait_for_all_tasks() {
  while [ "${#RUNNING_PIDS[@]}" -gt 0 ]; do
    wait_for_next_task
  done
}

group_contains() {
  local groups="$1"
  local wanted="$2"

  case ",$groups," in
    *",$wanted,"*) return 0 ;;
    *) return 1 ;;
  esac
}

should_queue_task() {
  local groups="$1"

  if [ "$BUILD_TARGET_SET" = "all" ]; then
    return 0
  fi

  group_contains "$groups" "$BUILD_TARGET_SET"
}

trap 'stop_running_builds; exit 130' INT TERM

echo "building with concurrency=$BUILD_CONCURRENCY jobs=$CROSS_JOBS"

for item in "${BUILD_TASKS[@]}"; do
  IFS='|' read -r groups builder package source_name target output_name upx_mode <<< "$item"

  if ! should_queue_task "$groups"; then
    continue
  fi

  if group_contains "$groups" "windows" && [ "$WINDOWS_GNU_READY" != "1" ]; then
    continue
  fi

  queue_build "$builder" "$package" "$source_name" "$target" "$output_name" "$upx_mode"
done

wait_for_all_tasks

echo "built artifacts"
ls -lh dist/artifacts

if ! compgen -G "dist/artifacts/*" >/dev/null; then
  echo "error: no release artifacts were built" >&2
  exit 1
fi

if [ "${#FAILED_TARGETS[@]}" -gt 0 ]; then
  echo "warning: some targets failed and were skipped:" >&2
  printf '  - %s\n' "${FAILED_TARGETS[@]}" >&2

  if [ "${#FAILED_LOGS[@]}" -gt 0 ]; then
    echo "failed target logs:" >&2
    printf '  - %s\n' "${FAILED_LOGS[@]}" >&2
  fi
fi

if [ "$CLEAN_BUILD" = "1" ]; then
  echo "cleaning parallel target directories"
  rm -rf target-parallel
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
