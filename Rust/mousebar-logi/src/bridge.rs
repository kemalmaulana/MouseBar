//! The plumbing every exported function shares: one Tokio runtime, one call
//! at a time, a per-call time budget, panic containment, and the `{"ok"}` /
//! `{"error"}` JSON envelope.

use std::ffi::{CString, c_char};
use std::future::Future;
use std::panic::{self, AssertUnwindSafe};
use std::sync::{Mutex, OnceLock, PoisonError};
use std::time::Duration;

use serde::Serialize;
use tokio::runtime::{Builder, Runtime};

/// Budget of a call that addresses one device by route (settings reads,
/// writes), so a device that stops answering cannot hang the caller's thread.
pub(crate) const DEVICE_BUDGET: Duration = Duration::from_secs(5);

/// Budget of a call that runs OpenLogi's one-shot enumerate (device list,
/// battery). A cold Lightspeed pass can spend 1.5 s draining arrivals plus
/// 3.5 s probing a slot, and the one-shot scan retries up to 4 passes.
pub(crate) const SCAN_BUDGET: Duration = Duration::from_secs(15);

/// Serializes calls process-wide. OpenLogi takes a per-receiver lock while it
/// opens a route or probes (up to 8 s); an overlapping call in this process
/// would spend its own budget waiting on that lock.
///
/// A std mutex held around `block_on`, not a Tokio one: callers already block
/// their thread for the whole call, so waiting here keeps the wait outside
/// the runtime and before the budget timer starts. It guards no data, so a
/// panic that poisoned it is recovered from rather than wedging later calls.
static CALLS: Mutex<()> = Mutex::new(());

/// Runs every call. Built on first use and kept for the life of the process.
static RUNTIME: OnceLock<Runtime> = OnceLock::new();

/// What every exported function returns, before it becomes a C string:
/// `{"ok": <value>}` or `{"error": "<message>"}`.
#[derive(Serialize)]
#[serde(rename_all = "lowercase")]
enum Envelope<T> {
    Ok(T),
    Error(String),
}

fn runtime() -> Result<&'static Runtime, String> {
    if let Some(runtime) = RUNTIME.get() {
        return Ok(runtime);
    }
    let built = Builder::new_multi_thread()
        .worker_threads(2)
        .thread_name("mousebar-logi")
        .enable_all()
        .build()
        .map_err(|error| error.to_string())?;
    // Two first calls may race here; the loser's runtime is dropped unused.
    let _ = RUNTIME.set(built);
    RUNTIME
        .get()
        .ok_or_else(|| "runtime unavailable".to_owned())
}

/// Runs a synchronous operation with panics contained and encodes its outcome.
pub(crate) fn guarded<T, F>(operation: F) -> *mut c_char
where
    T: Serialize,
    F: FnOnce() -> Result<T, String>,
{
    let outcome = panic::catch_unwind(AssertUnwindSafe(operation))
        .unwrap_or_else(|_| Err("internal error".to_owned()));
    encode(outcome)
}

/// Runs an async operation on the shared runtime, one call at a time, within
/// `budget` (counted from when this call holds [`CALLS`]), with panics
/// contained, and encodes its outcome.
pub(crate) fn run<T, F, Fut>(budget: Duration, operation: F) -> *mut c_char
where
    T: Serialize,
    F: FnOnce() -> Fut,
    Fut: Future<Output = Result<T, String>>,
{
    guarded(|| {
        let _serial = CALLS.lock().unwrap_or_else(PoisonError::into_inner);
        runtime()?.block_on(async {
            tokio::time::timeout(budget, operation())
                .await
                .unwrap_or_else(|_| Err("timed out".to_owned()))
        })
    })
}

/// Turns an outcome into a caller-owned C string, released with
/// `mb_logi_free`.
pub(crate) fn encode<T: Serialize>(outcome: Result<T, String>) -> *mut c_char {
    let envelope = match outcome {
        Ok(value) => Envelope::Ok(value),
        Err(message) => Envelope::Error(message),
    };
    let text = serde_json::to_string(&envelope)
        .unwrap_or_else(|error| format!("{{\"error\":{}}}", quoted(&error.to_string())));
    // JSON escapes U+0000, so the text never holds an interior NUL; the
    // fallback only keeps the "always a JSON string" contract unconditional.
    CString::new(text)
        .unwrap_or_else(|_| c"{\"error\":\"internal error\"}".to_owned())
        .into_raw()
}

/// `text` as a JSON string literal.
fn quoted(text: &str) -> String {
    serde_json::to_string(text).unwrap_or_else(|_| "\"internal error\"".to_owned())
}
