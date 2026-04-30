use axum::body::Bytes;
use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use hmac::{Hmac, Mac};
use serde::Deserialize;
use serde_json::json;
use sha2::Sha256;
use std::collections::HashSet;
use std::env;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::process::Command;
use tokio::sync::Mutex;
use tracing::{error, info, warn};

type HmacSha256 = Hmac<Sha256>;

#[derive(Clone)]
struct AppState {
    config: Arc<Config>,
    running_tags: Arc<Mutex<HashSet<String>>>,
}

#[derive(Debug)]
struct Config {
    host: String,
    port: u16,
    webhook_path: String,
    webhook_secret: String,
    repo_dir: PathBuf,
    github_repo: String,
    asset_name: String,
    build_script: PathBuf,
}

#[derive(Debug, Deserialize)]
struct PushPayload {
    #[serde(default)]
    r#ref: String,
    repository: Option<Repository>,
}

#[derive(Debug, Deserialize)]
struct Repository {
    full_name: Option<String>,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::dotenv();

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,tower_http=warn".into()),
        )
        .init();

    let config = Arc::new(Config::from_env()?);
    let state = AppState {
        config: config.clone(),
        running_tags: Arc::new(Mutex::new(HashSet::new())),
    };

    let app = Router::new()
        .route("/health", get(health))
        .route(config.webhook_path.as_str(), post(webhook))
        .with_state(state);

    let addr: SocketAddr = format!("{}:{}", config.host, config.port).parse()?;
    let listener = tokio::net::TcpListener::bind(addr).await?;
    info!("NodeGet release bot listening on http://{}", addr);
    axum::serve(listener, app).await?;

    Ok(())
}

async fn health() -> Json<serde_json::Value> {
    Json(json!({ "ok": true }))
}

async fn webhook(State(state): State<AppState>, headers: HeaderMap, body: Bytes) -> Response {
    if let Err(response) = verify_signature(&state.config.webhook_secret, &headers, &body) {
        return response;
    }

    let event = headers
        .get("x-github-event")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default();
    if event != "push" {
        return json_response(StatusCode::OK, json!({ "ok": true, "ignored": event }));
    }

    let payload: PushPayload = match serde_json::from_slice(&body) {
        Ok(payload) => payload,
        Err(e) => {
            warn!(error = %e, "invalid webhook payload");
            return json_response(StatusCode::BAD_REQUEST, json!({ "error": "invalid json" }));
        }
    };

    if !payload.r#ref.starts_with("refs/tags/v") {
        return json_response(
            StatusCode::OK,
            json!({ "ok": true, "ignored": payload.r#ref }),
        );
    }

    if let Some(full_name) = payload.repository.and_then(|repo| repo.full_name)
        && full_name != state.config.github_repo
    {
        warn!(repo = full_name, expected = state.config.github_repo, "repository mismatch");
        return json_response(StatusCode::FORBIDDEN, json!({ "error": "repository mismatch" }));
    }

    let tag = payload.r#ref.trim_start_matches("refs/tags/").to_owned();
    {
        let mut running = state.running_tags.lock().await;
        if !running.insert(tag.clone()) {
            return json_response(
                StatusCode::OK,
                json!({ "ok": true, "ignored": format!("already running {tag}") }),
            );
        }
    }

    let run_state = state.clone();
    let run_tag = tag.clone();
    tokio::spawn(async move {
        if let Err(e) = run_build(&run_state.config, &run_tag).await {
            error!(tag = run_tag, error = %e, "release build failed");
        }
        run_state.running_tags.lock().await.remove(&run_tag);
    });

    json_response(StatusCode::OK, json!({ "ok": true, "queued": tag }))
}

async fn run_build(config: &Config, tag: &str) -> anyhow::Result<()> {
    info!(tag, "release build started");

    let mut child = Command::new(&config.build_script)
        .arg(tag)
        .current_dir(&config.repo_dir)
        .env("REPO_DIR", &config.repo_dir)
        .env("GITHUB_REPO", &config.github_repo)
        .env("ASSET_NAME", &config.asset_name)
        .spawn()?;

    let status = child.wait().await?;
    if !status.success() {
        anyhow::bail!("build script exited with {status}");
    }

    info!(tag, "release build finished");
    Ok(())
}

fn verify_signature(secret: &str, headers: &HeaderMap, body: &[u8]) -> Result<(), Response> {
    let Some(signature) = headers
        .get("x-hub-signature-256")
        .and_then(|v| v.to_str().ok())
    else {
        return Err(json_response(
            StatusCode::UNAUTHORIZED,
            json!({ "error": "missing signature" }),
        ));
    };

    let Some(actual_hex) = signature.strip_prefix("sha256=") else {
        return Err(json_response(
            StatusCode::UNAUTHORIZED,
            json!({ "error": "bad signature format" }),
        ));
    };

    let actual = match hex::decode(actual_hex) {
        Ok(bytes) => bytes,
        Err(_) => {
            return Err(json_response(
                StatusCode::UNAUTHORIZED,
                json!({ "error": "bad signature encoding" }),
            ));
        }
    };

    let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).map_err(|_| {
        json_response(
            StatusCode::INTERNAL_SERVER_ERROR,
            json!({ "error": "bad secret" }),
        )
    })?;
    mac.update(body);

    mac.verify_slice(&actual).map_err(|_| {
        json_response(
            StatusCode::UNAUTHORIZED,
            json!({ "error": "bad signature" }),
        )
    })
}

fn json_response(status: StatusCode, body: serde_json::Value) -> Response {
    (status, Json(body)).into_response()
}

impl Config {
    fn from_env() -> anyhow::Result<Self> {
        Ok(Self {
            host: env_or("HOST", "127.0.0.1"),
            port: env_or("PORT", "8787").parse()?,
            webhook_path: env_or("WEBHOOK_PATH", "/nodeget-release-webhook"),
            webhook_secret: env_required("WEBHOOK_SECRET")?,
            repo_dir: PathBuf::from(env_or("REPO_DIR", "/root/NodeGet")),
            github_repo: env_or("GITHUB_REPO", "eeviriyi/NodeGet"),
            asset_name: env_or("ASSET_NAME", "nodeget-linux-x86_64.tar.gz"),
            build_script: PathBuf::from(env_or(
                "BUILD_SCRIPT",
                "/root/NodeGet-Release-Bot/scripts/build-release.sh",
            )),
        })
    }
}

fn env_or(key: &str, default: &str) -> String {
    env::var(key).unwrap_or_else(|_| default.to_owned())
}

fn env_required(key: &str) -> anyhow::Result<String> {
    env::var(key).map_err(|_| anyhow::anyhow!("missing env {key}"))
}
