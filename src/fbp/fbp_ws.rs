//! FBP backend WebSocket client (runs with host server logic).
//!
//! Flutter integration guide: see `src/fbp/FLUTTER_WS.md`.

use std::sync::RwLock;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use hbb_common::{
    config::LocalConfig,
    config::Config,
    password_security::{self, temporary_enabled},
    log,
    serde_json::{self, json, Value},
    tokio::{
        self,
        sync::mpsc::{unbounded_channel, UnboundedSender},
        time::{sleep, timeout},
    },
    ResultType,
};
use lazy_static::lazy_static;
use serde::Serialize;
use tokio_tungstenite::{
    connect_async,
    tungstenite::{
        client::IntoClientRequest,
        http,
        protocol::Message as WsMessage,
        Error as WsError,
    },
};
use url::Url;
use uuid::Uuid;

// Must match `flutter/lib/custom/config.dart` and `activation_state.dart`.
const KEY_DEVICE_TOKEN: &str = "device_activation_token";
const KEY_DEVICE_ID: &str = "device_activation_device_id";
const KEY_WEBSOCKET_URL: &str = "custom_websocket_url";
const DEFAULT_WEBSOCKET_URL: &str = "wss://api.fbpdesk.ru";

const EVENT_NAME: &str = "fbp_ws_status";
const CONNECT_TIMEOUT_MS: u64 = 15_000;
const PING_INTERVAL_SECS: u64 = 30;
const RECONNECT_MIN_SECS: u64 = 5;
const RECONNECT_MAX_SECS: u64 = 60;
const RECONNECT_BLOCKED_SECS: u64 = 300;

/// UI-facing status values (also sent in Flutter events).
pub const STATUS_NOT_ACTIVATED: &str = "not_activated";
pub const STATUS_CONNECTING: &str = "connecting";
pub const STATUS_CONNECTED: &str = "connected";
pub const STATUS_ERROR: &str = "error";

/// Machine-readable error codes for Flutter.
pub const CODE_NONE: &str = "";
pub const CODE_MISSING_CREDENTIALS: &str = "missing_credentials";
pub const CODE_BAD_DEVICE_ID: &str = "bad_device_id";
pub const CODE_BLOCKED: &str = "blocked";
pub const CODE_INTERNAL_SERVER_ERROR: &str = "internal_server_error";
pub const CODE_IO_ERROR: &str = "io_error";
pub const CODE_CLOSED: &str = "closed";

#[derive(Debug, Clone, Serialize)]
pub struct FbpWsStatus {
    pub status: String,
    pub code: String,
    pub detail: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub connected_since: Option<i64>,
}

struct WsRuntime {
    status: FbpWsStatus,
    out_tx: Option<UnboundedSender<String>>,
}

lazy_static! {
    static ref RUNTIME: RwLock<WsRuntime> = RwLock::new(WsRuntime {
        status: FbpWsStatus {
            status: STATUS_NOT_ACTIVATED.to_string(),
            code: CODE_NONE.to_string(),
            detail: String::new(),
            connected_since: None,
        },
        out_tx: None,
    });
}

struct Credentials {
    device_id: String,
    token: String,
    ws_base_url: String,
}

#[derive(Debug, Clone)]
struct HandshakeError {
    http_status: u16,
    code: String,
    detail: String,
}

enum SessionError {
    Handshake(HandshakeError),
    Other(String),
}

/// Whether the WS client should run in this process.
///
/// With an installed app + Windows service, host logic runs in `--server` while
/// Flutter UI, credentials, and status FFI live in the main process.
#[inline]
fn ws_should_run() -> bool {
    #[cfg(all(feature = "flutter", not(any(target_os = "android", target_os = "ios"))))]
    {
        if crate::is_server() {
            return false;
        }
        if crate::common::is_main() {
            return true;
        }
    }
    crate::is_server() || crate::is_server_running()
}

/// Start WS client in the Flutter UI process (once per process).
pub fn spawn_client() {
    use std::sync::Once;
    static STARTED: Once = Once::new();
    STARTED.call_once(|| {
        log::info!("fbp ws: spawning client in UI process");
        hbb_common::tokio::spawn(async {
            if let Err(e) = ws_client_loop().await {
                log::error!("fbp ws client loop exited: {e}");
            }
        });
    });
}

// ---------------------------------------------------------------------------

/// JSON snapshot for `main_get_fbp_ws_status()` FFI.
pub fn status_json() -> String {
    serde_json::to_string(&current_status()).unwrap_or_else(|_| "{}".to_string())
}

/// Queue an outbound text frame from Flutter or other Rust code.
pub fn send_message(text: &str) -> ResultType<()> {
    let tx = RUNTIME
        .read()
        .map_err(|_| hbb_common::anyhow::anyhow!("fbp ws runtime poisoned"))?
        .out_tx
        .clone();
    if let Some(tx) = tx {
        tx.send(text.to_string())
            .map_err(|e| hbb_common::anyhow::anyhow!("fbp ws send channel closed: {e}"))?;
        log::info!("fbp ws outbound queued ({} bytes)", text.len());
        Ok(())
    } else {
        hbb_common::bail!("fbp ws is not connected");
    }
}

/// Main loop — spawn from `server.rs` when `is_server == true`.
pub async fn ws_client_loop() -> ResultType<()> {
    log::info!("fbp ws client loop started");
    let mut backoff = RECONNECT_MIN_SECS;

    loop {
        if !ws_should_run() {
            log::info!("fbp ws loop stopping");
            set_status(STATUS_NOT_ACTIVATED, CODE_NONE, "server stopped", None);
            break;
        }

        let creds = match load_credentials() {
            Some(c) => c,
            None => {
                log::info!("fbp ws: device not activated (token/device_id missing), waiting");
                set_status(
                    STATUS_NOT_ACTIVATED,
                    CODE_NONE,
                    "device not activated",
                    None,
                );
                backoff = RECONNECT_MIN_SECS;
                sleep(Duration::from_secs(backoff)).await;
                continue;
            }
        };

        if let Err(e) = validate_device_id(&creds.device_id) {
            log::error!("fbp ws: invalid device_id in config: {e}");
            set_status(STATUS_ERROR, CODE_BAD_DEVICE_ID, &e.to_string(), None);
            sleep(Duration::from_secs(RECONNECT_BLOCKED_SECS)).await;
            continue;
        }

        let url = match build_ws_url(&creds) {
            Ok(u) => u,
            Err(e) => {
                log::error!("fbp ws: failed to build url: {e}");
                set_status(STATUS_ERROR, CODE_IO_ERROR, &e.to_string(), None);
                sleep(Duration::from_secs(backoff)).await;
                backoff = (backoff * 2).min(RECONNECT_MAX_SECS);
                continue;
            }
        };

        log::info!("fbp ws: connecting to {}", redact_ws_url(&url));
        set_status(STATUS_CONNECTING, CODE_NONE, "connecting", None);

        match connect_and_run(&url, &creds).await {
            Ok(()) => {
                log::info!("fbp ws: session ended");
                set_status(STATUS_ERROR, CODE_CLOSED, "connection closed", None);
                backoff = RECONNECT_MIN_SECS;
            }
            Err(SessionError::Handshake(h)) => {
                log::error!(
                    "fbp ws handshake failed: http {} code={} detail={}",
                    h.http_status,
                    h.code,
                    h.detail
                );
                if h.code == CODE_MISSING_CREDENTIALS {
                    set_status(STATUS_NOT_ACTIVATED, &h.code, &h.detail, None);
                    backoff = RECONNECT_BLOCKED_SECS;
                } else {
                    set_status(STATUS_ERROR, &h.code, &h.detail, None);
                    backoff = if h.code == CODE_BLOCKED {
                        RECONNECT_BLOCKED_SECS
                    } else {
                        (backoff * 2).min(RECONNECT_MAX_SECS)
                    };
                }
            }
            Err(SessionError::Other(detail)) => {
                log::error!("fbp ws session error: {detail}");
                set_status(STATUS_ERROR, CODE_IO_ERROR, &detail, None);
                backoff = (backoff * 2).min(RECONNECT_MAX_SECS);
            }
        }

        clear_outbound_channel();
        sleep(Duration::from_secs(backoff)).await;
    }

    Ok(())
}

// ---------------------------------------------------------------------------
// Customize here: inbound JSON -> optional outbound JSON/text
// ---------------------------------------------------------------------------

/// Called for every **text** WebSocket frame from the server.
///
/// Return `Some(payload)` to send a reply; `None` to stay silent.
/// Edit this function to implement your protocol.
pub fn handle_incoming_message(value: &Value) -> Option<String> {
    if let Some(err) = value.get("error").and_then(|v| v.as_str()) {
        log::warn!("fbp ws server message error field: {err}");
    }

    match value.get("type").and_then(|v| v.as_str()) {
        Some("ping") => Some(json!({"type": "pong"}).to_string()),
        Some("echo") => {
            let data = value.get("data").cloned().unwrap_or(Value::Null);
            Some(json!({"type": "echo_reply", "data": data}).to_string())
        }
        Some("payload") => Some(hello_payload_json()),
        Some("password-request") => value
            .get("request_id")
            .and_then(|v| v.as_str())
            .map(|request_id| password_response_json(request_id))
            .or_else(|| {
                log::warn!("fbp ws password-request without request_id: {value}");
                None
            }),
        _ => {
            log::debug!("fbp ws unhandled message: {value}");
            None
        }
    }
}

/// Optional hook: outbound messages sent right after a successful handshake.
pub fn on_connected() -> Vec<String> {
    vec![hello_payload_json()]
}

fn hello_payload_json() -> String {
    build_agent_payload("agent-hello", None)
}

fn password_response_json(request_id: &str) -> String {
    build_agent_payload("password-response", Some(request_id))
}

fn build_agent_payload(msg_type: &str, request_id: Option<&str>) -> String {
    let mut payload = json!({
        "type": msg_type,
        "version": crate::VERSION,
        "id": Config::get_id(),
    });

    if let Some(rid) = request_id {
        payload["request_id"] = json!(rid);
    }

    if let Some(pwd) = current_temporary_password() {
        payload["temporary_password"] = json!(pwd);
    } else {
        log::debug!("fbp ws {msg_type}: no temporary password (disabled or empty)");
    }

    payload.to_string()
}

fn current_temporary_password() -> Option<String> {
    if !temporary_enabled() {
        return None;
    }
    let pwd = password_security::temporary_password();
    if pwd.is_empty() {
        None
    } else {
        Some(pwd)
    }
}

// ---------------------------------------------------------------------------

async fn connect_and_run(url: &str, creds: &Credentials) -> Result<(), SessionError> {
    let ws_stream = connect_ws(url).await?;
    let (mut write, mut read) = ws_stream.split();

    let (out_tx, mut out_rx) = unbounded_channel::<String>();
    if let Ok(mut rt) = RUNTIME.write() {
        rt.out_tx = Some(out_tx);
    }

    let connected_at = chrono::Utc::now().timestamp();
    set_status(STATUS_CONNECTED, CODE_NONE, "connected", Some(connected_at));
    log::info!("fbp ws connected (device_id={})", creds.device_id);

    for msg in on_connected() {
        if write.send(WsMessage::Text(msg.into())).await.is_err() {
            log::error!("fbp ws failed to send on_connected message");
            return Err(SessionError::Other(
                "failed to send on_connected message".to_string(),
            ));
        }
    }

    let mut ping_tick = tokio::time::interval(Duration::from_secs(PING_INTERVAL_SECS));
    ping_tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

    loop {
        tokio::select! {
            _ = ping_tick.tick() => {
                log::debug!("fbp ws sending protocol Ping");
                if write.send(WsMessage::Ping(Vec::new().into())).await.is_err() {
                    log::error!("fbp ws ping failed");
                    return Err(SessionError::Other("ping failed".to_string()));
                }
            }
            out = out_rx.recv() => {
                match out {
                    Some(text) => {
                        log::info!("fbp ws sending outbound ({} bytes)", text.len());
                        if write.send(WsMessage::Text(text.into())).await.is_err() {
                            log::error!("fbp ws outbound write failed");
                            return Err(SessionError::Other("write failed".to_string()));
                        }
                    }
                    None => {
                        log::warn!("fbp ws outbound channel closed");
                        break;
                    }
                }
            }
            incoming = read.next() => {
                match incoming {
                    Some(Ok(WsMessage::Text(text))) => {
                        log::info!(
                            "fbp ws received text ({} bytes): {}",
                            text.len(),
                            truncate_log(&text)
                        );
                        if let Err(e) = process_incoming_text(&text, &mut write).await {
                            return Err(e);
                        }
                    }
                    Some(Ok(WsMessage::Binary(data))) => {
                        log::info!("fbp ws received binary ({} bytes)", data.len());
                    }
                    Some(Ok(WsMessage::Ping(payload))) => {
                        if write.send(WsMessage::Pong(payload)).await.is_err() {
                            log::error!("fbp ws pong failed");
                            return Err(SessionError::Other("pong failed".to_string()));
                        }
                    }
                    Some(Ok(WsMessage::Pong(_))) => {}
                    Some(Ok(WsMessage::Close(frame))) => {
                        let reason = frame
                            .as_ref()
                            .map(|f| f.reason.to_string())
                            .unwrap_or_default();
                        log::warn!("fbp ws closed by server: {reason}");
                        if is_blocked_reason(&reason) {
                            set_status(STATUS_ERROR, CODE_BLOCKED, &reason, None);
                        } else {
                            set_status(STATUS_ERROR, CODE_CLOSED, &reason, None);
                        }
                        break;
                    }
                    Some(Ok(WsMessage::Frame(_))) => {}
                    Some(Err(e)) => {
                        return Err(SessionError::Other(format!("read error: {e:?}")));
                    }
                    None => {
                        log::warn!("fbp ws stream ended (EOF)");
                        break;
                    }
                }
            }
        }

        if !ws_should_run() {
            log::info!("fbp ws closing");
            let _ = write.send(WsMessage::Close(None)).await;
            break;
        }
    }

    Ok(())
}

async fn process_incoming_text(
    text: &str,
    write: &mut (impl SinkExt<WsMessage> + Unpin),
) -> Result<(), SessionError> {
    let value: Value = match serde_json::from_str(text) {
        Ok(v) => v,
        Err(e) => {
            log::warn!("fbp ws invalid json: {e}; payload={}", truncate_log(text));
            return Ok(());
        }
    };

    if let Some(err) = value.get("error").and_then(|v| v.as_str()) {
        log::error!("fbp ws server error payload: {err}");
        if err.eq_ignore_ascii_case("blocked") {
            set_status(STATUS_ERROR, CODE_BLOCKED, err, None);
            write.send(WsMessage::Close(None)).await.ok();
            return Err(SessionError::Handshake(HandshakeError {
                http_status: 401,
                code: CODE_BLOCKED.to_string(),
                detail: err.to_string(),
            }));
        }
    }

    if let Some(reply) = handle_incoming_message(&value) {
        log::info!("fbp ws auto-reply ({} bytes)", reply.len());
        if write.send(WsMessage::Text(reply.into())).await.is_err() {
            log::error!("fbp ws reply write failed");
            return Err(SessionError::Other("reply write failed".to_string()));
        }
    }

    Ok(())
}

async fn connect_ws(
    url: &str,
) -> Result<tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>, SessionError>
{
    let request = url
        .into_client_request()
        .map_err(|e| SessionError::Other(format!("invalid ws request: {e}")))?;

    match timeout(
        Duration::from_millis(CONNECT_TIMEOUT_MS),
        connect_async(request),
    )
    .await
    {
        Ok(Ok((stream, _resp))) => Ok(stream),
        Ok(Err(e)) => Err(map_connect_error(e)),
        Err(_) => Err(SessionError::Other("websocket connect timeout".to_string())),
    }
}

fn http_response_body(resp: &http::Response<Option<Vec<u8>>>) -> String {
    resp.body()
        .as_ref()
        .map(|body| String::from_utf8_lossy(body).into_owned())
        .unwrap_or_default()
}

fn map_connect_error(err: WsError) -> SessionError {
    if let WsError::Http(resp) = err {
        let status = resp.status().as_u16();
        let body = http_response_body(&resp);
        log::error!(
            "fbp ws http handshake {} body={}",
            status,
            truncate_log(&body)
        );
        let (code, detail) = map_http_error(status, &body);
        return SessionError::Handshake(HandshakeError {
            http_status: status,
            code: code.to_string(),
            detail,
        });
    }
    SessionError::Other(format!("websocket connect failed: {err:?}"))
}

fn map_http_error(status: u16, body: &str) -> (&'static str, String) {
    let api_error = serde_json::from_str::<Value>(body)
        .ok()
        .and_then(|v| v.get("error").and_then(|e| e.as_str()).map(|s| s.to_string()));

    match (status, api_error.as_deref()) {
        (401, Some("Missing credentials")) => (CODE_MISSING_CREDENTIALS, body.to_string()),
        (400, Some("Bad device ID")) => (CODE_BAD_DEVICE_ID, body.to_string()),
        (401, Some("Blocked")) => (CODE_BLOCKED, body.to_string()),
        (500, _) => (CODE_INTERNAL_SERVER_ERROR, body.to_string()),
        (401, Some(msg)) if msg.eq_ignore_ascii_case("blocked") => {
            (CODE_BLOCKED, body.to_string())
        }
        (401, _) if body.contains("Missing credentials") => {
            (CODE_MISSING_CREDENTIALS, body.to_string())
        }
        (400, _) if body.contains("Bad device ID") => (CODE_BAD_DEVICE_ID, body.to_string()),
        _ => (CODE_IO_ERROR, format!("http {status}: {body}")),
    }
}

fn load_credentials() -> Option<Credentials> {
    let token = LocalConfig::get_option(KEY_DEVICE_TOKEN);
    let device_id = LocalConfig::get_option(KEY_DEVICE_ID);
    if token.is_empty() || device_id.is_empty() {
        return None;
    }
    let mut ws_base_url = LocalConfig::get_option(KEY_WEBSOCKET_URL);
    if ws_base_url.is_empty() {
        ws_base_url = DEFAULT_WEBSOCKET_URL.to_string();
    }
    Some(Credentials {
        device_id,
        token,
        ws_base_url,
    })
}

fn validate_device_id(device_id: &str) -> ResultType<()> {
    Uuid::parse_str(device_id)
        .map_err(|e| hbb_common::anyhow::anyhow!("device_id is not a valid GUID: {e}"))?;
    Ok(())
}

fn build_ws_url(creds: &Credentials) -> ResultType<String> {
    let mut url = Url::parse(&creds.ws_base_url)?;
    if url.path() == "/" || url.path().is_empty() {
        url.set_path("/ws");
    }
    {
        let mut pairs = url.query_pairs_mut();
        pairs.append_pair("device_id", &creds.device_id);
        pairs.append_pair("token", &creds.token);
    }
    Ok(url.to_string())
}

fn current_status() -> FbpWsStatus {
    RUNTIME
        .read()
        .map(|g| g.status.clone())
        .unwrap_or(FbpWsStatus {
            status: STATUS_NOT_ACTIVATED.to_string(),
            code: CODE_NONE.to_string(),
            detail: String::new(),
            connected_since: None,
        })
}

fn set_status(status: &str, code: &str, detail: &str, connected_since: Option<i64>) {
    let snapshot = FbpWsStatus {
        status: status.to_string(),
        code: code.to_string(),
        detail: detail.to_string(),
        connected_since,
    };
    log::info!(
        "fbp ws status -> {} code={} detail={}",
        snapshot.status,
        snapshot.code,
        snapshot.detail
    );
    if let Ok(mut rt) = RUNTIME.write() {
        rt.status = snapshot.clone();
    }
    push_flutter_event(&snapshot);
}

fn push_flutter_event(status: &FbpWsStatus) {
    #[cfg(feature = "flutter")]
    {
        let mut evt = serde_json::Map::new();
        evt.insert("name".into(), json!(EVENT_NAME));
        evt.insert("status".into(), json!(status.status));
        evt.insert("code".into(), json!(status.code));
        evt.insert("detail".into(), json!(status.detail));
        if let Some(ts) = status.connected_since {
            evt.insert("connected_since".into(), json!(ts));
        }
        if let Ok(payload) = serde_json::to_string(&evt) {
            crate::flutter::push_global_event(crate::flutter::APP_TYPE_MAIN, payload);
        }
    }
}

fn clear_outbound_channel() {
    if let Ok(mut rt) = RUNTIME.write() {
        rt.out_tx = None;
    }
}

fn redact_ws_url(url: &str) -> String {
    if let Ok(mut parsed) = Url::parse(url) {
        let pairs: Vec<(String, String)> = parsed
            .query_pairs()
            .map(|(k, v)| {
                if k == "token" {
                    (k.into_owned(), "***".to_string())
                } else {
                    (k.into_owned(), v.into_owned())
                }
            })
            .collect();
        parsed.set_query(None);
        for (k, v) in pairs {
            parsed.query_pairs_mut().append_pair(&k, &v);
        }
        return parsed.to_string();
    }
    url.to_string()
}

fn truncate_log(s: &str) -> String {
    const MAX: usize = 512;
    if s.len() <= MAX {
        s.to_string()
    } else {
        format!("{}…", &s[..MAX])
    }
}

fn is_blocked_reason(reason: &str) -> bool {
    reason.to_ascii_lowercase().contains("block")
}
