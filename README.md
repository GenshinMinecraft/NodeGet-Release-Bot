# NodeGet-Release-Bot

Rust webhook service for building NodeGet releases on your own server.

It receives GitHub push webhooks, verifies `X-Hub-Signature-256`, responds only to `refs/tags/v*`, builds NodeGet Linux binaries with `cross`, builds Windows x86_64 GNU binaries with MinGW, and uploads GitHub Release assets with `gh`.

## Runtime Defaults

- Public webhook: `https://release.aqa.cc/nodeget-release-webhook`
- Local listen: `127.0.0.1:8787`
- NodeGet repo path: `/root/NodeGet`
- GitHub repo: `eeviriyi/NodeGet`
- Rust toolchain for NodeGet: `nightly`
- Release artifacts: individual binaries named like `nodeget-server-linux-x86_64-musl` and `nodeget-server-windows-x86_64.exe`

## Server Requirements

- Rust stable for this bot
- Rust nightly for building NodeGet
- Docker or Podman for `cross`
- `cross` installed in the service PATH
- MinGW for Windows x86_64 GNU builds
- `gh` authenticated with release permissions
- Existing NodeGet checkout at `/root/NodeGet`
- Caddy reverse proxy to `127.0.0.1:8787`

You already verified manual release creation with `gh`, so the same auth is reused.

Install build dependencies:

```bash
sudo apt-get update
sudo apt-get install -y build-essential pkg-config libssl-dev docker.io gcc-mingw-w64-x86-64
sudo systemctl enable --now docker
cargo install cross --git https://github.com/cross-rs/cross
rustup target add x86_64-pc-windows-gnu --toolchain nightly
```

Optional compression:

```bash
sudo apt-get install -y upx
```

## Install

```bash
cd /root
git clone https://github.com/eeviriyi/NodeGet-Release-Bot.git
cd NodeGet-Release-Bot
cp .env.example .env
nano .env
chmod +x scripts/build-release.sh
cargo build --release
```

Generate a webhook secret:

```bash
openssl rand -hex 32
```

Put it in `.env`:

```env
WEBHOOK_SECRET=...
```

Cross-build settings:

```env
CROSS_BIN=cross
RUST_TOOLCHAIN=nightly
CROSS_JOBS=32
ENABLE_UPX=0
ENABLE_WINDOWS_GNU=1
BUILD_TARGET_SET=all
ALLOW_PARTIAL=1
```

`ALLOW_PARTIAL=1` uploads every successful architecture even if a target fails because a dependency or toolchain does not support it. Set `ALLOW_PARTIAL=0` if you want one failed target to fail the whole release.

`ENABLE_WINDOWS_GNU=1` enables Linux-hosted Windows x86_64 `.exe` builds using `x86_64-pc-windows-gnu`. This is not the same as upstream's Windows MSVC build, but it is the practical Windows target for a single Linux build server.

`BUILD_TARGET_SET` can be `all`, `linux`, or `windows`. Use `windows` when you only need to backfill Windows assets into an existing release.

## Run Manually

```bash
./target/release/nodeget-release-bot
```

Health check:

```bash
curl -I http://127.0.0.1:8787/health
```

## systemd

```bash
sudo cp systemd/nodeget-release-bot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now nodeget-release-bot
sudo systemctl status nodeget-release-bot --no-pager
```

Logs:

```bash
sudo journalctl -u nodeget-release-bot -f
```

## Caddy

```caddyfile
release.aqa.cc {
    reverse_proxy 127.0.0.1:8787
}
```

## GitHub Webhook

Repository settings:

- Payload URL: `https://release.aqa.cc/nodeget-release-webhook`
- Content type: `application/json`
- Secret: same value as `WEBHOOK_SECRET`
- Events: `Pushes`

## Release Flow

Push a tag:

```bash
git tag v0.0.4-custom.1
git push origin v0.0.4-custom.1
```

The bot will:

1. Fetch the tag.
2. Check out the tag.
3. Run `cross build --profile minimal` for Linux server and agent targets.
4. Run `cargo build --target x86_64-pc-windows-gnu --profile minimal` for Windows x86_64 server and agent targets.
5. Rename binaries using the upstream release naming style.
6. Create or update the GitHub Release assets.

Backfill only Windows assets into an existing tag:

```bash
cd /root/NodeGet-Release-Bot
BUILD_TARGET_SET=windows ./scripts/build-release.sh v0.0.0-test.7
```

## Linux Targets

Server artifacts:

- `nodeget-server-linux-x86_64-musl`
- `nodeget-server-linux-x86_64-gnu`
- `nodeget-server-linux-arm-gnueabi`
- `nodeget-server-linux-arm-gnueabihf`
- `nodeget-server-linux-aarch64-gnu`
- `nodeget-server-linux-aarch64-musl`
- `nodeget-server-linux-armv7-gnueabi`
- `nodeget-server-linux-armv7-gnueabihf`
- `nodeget-server-linux-armv7-musleabi`
- `nodeget-server-linux-armv7-musleabihf`

Agent artifacts:

- `nodeget-agent-linux-x86_64-musl`
- `nodeget-agent-linux-x86_64-gnu`
- `nodeget-agent-linux-i686-gnu`
- `nodeget-agent-linux-i686-musl`
- `nodeget-agent-linux-aarch64-gnu`
- `nodeget-agent-linux-aarch64-musl`
- `nodeget-agent-linux-arm-gnueabi`
- `nodeget-agent-linux-arm-gnueabihf`
- `nodeget-agent-linux-arm-musleabi`
- `nodeget-agent-linux-arm-musleabihf`
- `nodeget-agent-linux-armv7-gnueabi`
- `nodeget-agent-linux-armv7-gnueabihf`
- `nodeget-agent-linux-armv7-musleabi`
- `nodeget-agent-linux-armv7-musleabihf`
- `nodeget-agent-linux-thumbv7neon-gnueabihf`
- `nodeget-agent-linux-riscv64gc-gnu`
- `nodeget-agent-linux-powerpc64-gnu`
- `nodeget-agent-linux-powerpc64le-gnu`
- `nodeget-agent-linux-s390x-gnu`
- `nodeget-agent-linux-sparc64-gnu`

## Windows Targets

These are built on Linux with MinGW:

- `nodeget-server-windows-x86_64.exe`
- `nodeget-agent-windows-x86_64.exe`

macOS releases still need a macOS runner, separate Mac machine, or a different build path.
