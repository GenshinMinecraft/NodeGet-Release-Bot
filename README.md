# NodeGet-Release-Bot

Self-hosted GitHub webhook service for building and publishing NodeGet releases.

The bot receives GitHub push webhooks, verifies `X-Hub-Signature-256`, accepts only `refs/tags/v*`, queues builds one at a time, then runs `scripts/build-release.sh` and uploads release assets with `gh`.

## What It Builds

- Linux server binaries with `cross`
- Linux agent binaries with `cross`
- Windows x86_64 GNU server and agent binaries with MinGW

Artifact names follow the upstream release style, for example:

- `nodeget-server-linux-x86_64-musl`
- `nodeget-agent-linux-aarch64-gnu`
- `nodeget-server-windows-x86_64.exe`
- `nodeget-agent-windows-x86_64.exe`

macOS and Windows MSVC/aarch64 builds are not handled by this Linux-hosted bot.

## Requirements

- Existing NodeGet checkout
- Rust stable for this bot
- Rust nightly for building NodeGet
- Docker or Podman for `cross`
- `cross` available in `PATH`
- MinGW for Windows x86_64 GNU builds
- `gh` authenticated with permission to create releases
- A reverse proxy, such as Caddy or nginx, if exposing the webhook publicly

On Debian/Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y build-essential pkg-config libssl-dev docker.io gcc-mingw-w64-x86-64
sudo systemctl enable --now docker
cargo install cross --git https://github.com/cross-rs/cross
rustup target add x86_64-pc-windows-gnu --toolchain nightly
```

Optional binary compression:

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

Use the same value for `.env` and the GitHub webhook secret.

## Configuration

Minimal `.env`:

```env
WEBHOOK_SECRET=replace-with-openssl-rand-hex-32
REPO_DIR=/root/NodeGet
GITHUB_REPO=owner/NodeGet
```

Common options:

```env
HOST=127.0.0.1
PORT=8787
WEBHOOK_PATH=/nodeget-release-webhook
RUST_TOOLCHAIN=nightly
BUILD_CONCURRENCY=8
CROSS_JOBS=8
CLEAN_BUILD=0
ENABLE_UPX=1
BUILD_TARGET_SET=all
ALLOW_PARTIAL=1
```

`BUILD_TARGET_SET` controls what the build script produces:

- `all`: Linux plus Windows x86_64 GNU
- `linux`: Linux only
- `windows`: Windows x86_64 GNU only, useful for backfilling assets into an existing release

`ALLOW_PARTIAL=1` uploads successful artifacts even if one target fails. Set it to `0` if any failed target should fail the whole release.

`ENABLE_UPX=1` compresses binaries with `upx` when available. This is slower but produces smaller assets.

`BUILD_CONCURRENCY` controls how many targets build at the same time. `CROSS_JOBS` controls the internal cargo jobs per target. On a large build server, start with `BUILD_CONCURRENCY=8` and `CROSS_JOBS=8`, then tune based on CPU, memory, and disk IO.

`CLEAN_BUILD=0` keeps the shared `target/` cache between releases. Set `CLEAN_BUILD=1` when you need a fully clean rebuild.

Build logs are written per target under `dist/logs`.

Advanced overrides, usually unnecessary:

- `BUILD_SCRIPT`: path to a custom build script
- `CROSS_BIN`: alternative `cross` executable name or path

## Run

Manual:

```bash
./target/release/nodeget-release-bot
```

Health check:

```bash
curl -I http://127.0.0.1:8787/health
```

systemd:

```bash
sudo cp systemd/nodeget-release-bot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now nodeget-release-bot
sudo systemctl status nodeget-release-bot --no-pager
```

The included service file assumes the bot is installed at `/root/NodeGet-Release-Bot`. If you use another path, update `WorkingDirectory`, `EnvironmentFile`, and `ExecStart`.

Logs:

```bash
sudo journalctl -u nodeget-release-bot -f
```

## Reverse Proxy

Example Caddy config:

```caddyfile
release.example.com {
    reverse_proxy 127.0.0.1:8787
}
```

The public webhook URL would then be:

```text
https://release.example.com/nodeget-release-webhook
```

## GitHub Webhook

In the target NodeGet repository settings:

- Payload URL: your public webhook URL
- Content type: `application/json`
- Secret: same value as `WEBHOOK_SECRET`
- Events: push events
- Active: enabled

## Release Flow

Push a version tag in the NodeGet repository:

```bash
git tag v0.0.4-custom.1
git push origin v0.0.4-custom.1
```

The bot will fetch the tag, check it out, build configured targets, and create or update the GitHub Release.

Backfill only Windows assets into an existing tag:

```bash
cd /root/NodeGet-Release-Bot
BUILD_TARGET_SET=windows ./scripts/build-release.sh v0.0.4-custom.1
```

## Targets

Current output count with `BUILD_TARGET_SET=all` is 32 files:

- 10 Linux server binaries
- 20 Linux agent binaries
- 2 Windows x86_64 GNU binaries

The exact target list is defined in `scripts/build-release.sh`.
