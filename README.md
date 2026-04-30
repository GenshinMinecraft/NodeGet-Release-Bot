# NodeGet-Release-Bot

Rust webhook service for building NodeGet releases on your own server.

It receives GitHub push webhooks, verifies `X-Hub-Signature-256`, responds only to `refs/tags/v*`, builds NodeGet on your VPS, packages binaries, and uploads a GitHub Release asset with `gh`.

## Runtime Defaults

- Public webhook: `https://release.aqa.cc/nodeget-release-webhook`
- Local listen: `127.0.0.1:8787`
- NodeGet repo path: `/root/NodeGet`
- GitHub repo: `eeviriyi/NodeGet`
- Asset name: `nodeget-linux-x86_64.tar.gz`

## Server Requirements

- Rust stable for this bot
- Rust nightly for building NodeGet
- `gh` authenticated with release permissions
- Existing NodeGet checkout at `/root/NodeGet`
- Caddy reverse proxy to `127.0.0.1:8787`

You already verified manual release creation with `gh`, so the same auth is reused.

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
3. Run `cargo +nightly build --release -p nodeget-server -p nodeget-agent`.
4. Package `nodeget-server` and `nodeget-agent`.
5. Create or update the GitHub Release asset.
