//! MouseBar's bridge to OpenLogi's HID++ crates: a small C ABI.
//!
//! Every `char *` result is UTF-8 JSON, `{"ok": <value>}` or
//! `{"error": "<message>"}`, owned by the caller and released with
//! [`mb_logi_free`]. A device is addressed by the opaque `route` string that
//! [`mb_logi_enumerate`] lists for it, passed back unchanged.
//!
//! Each call blocks the calling thread for at most five seconds.

use std::ffi::{CStr, CString, c_char};

use openlogi_hid::DeviceRoute;
use serde::Serialize;

mod bridge;
mod ops;

/// The OpenLogi revision this crate is built against (see `Cargo.toml`).
const OPENLOGI_REV: &str = "0f69d75be99439da97291ff4163aba83dfc6df96";

const INVALID_ROUTE: &str = "invalid route";

#[derive(Serialize)]
struct Version {
    #[serde(rename = "crate")]
    crate_version: &'static str,
    openlogi_rev: &'static str,
}

/// Decodes a `route` argument.
///
/// # Safety
///
/// `route` is null or points to a NUL-terminated string valid for reads for
/// the duration of the call.
unsafe fn route_arg(route: *const c_char) -> Result<DeviceRoute, String> {
    if route.is_null() {
        return Err(INVALID_ROUTE.to_owned());
    }
    // SAFETY: non-null, and NUL-terminated and readable per this function's
    // contract.
    let text = unsafe { CStr::from_ptr(route) }
        .to_str()
        .map_err(|_| INVALID_ROUTE.to_owned())?;
    serde_json::from_str(text).map_err(|_| INVALID_ROUTE.to_owned())
}

/// `{"ok":{"crate":"0.1.0","openlogi_rev":"<sha>"}}`.
#[unsafe(no_mangle)]
pub extern "C" fn mb_logi_version() -> *mut c_char {
    bridge::guarded(|| {
        Ok(Version {
            crate_version: env!("CARGO_PKG_VERSION"),
            openlogi_rev: OPENLOGI_REV,
        })
    })
}

/// `{"ok":[Device, …]}`: every paired device on this host.
#[unsafe(no_mangle)]
pub extern "C" fn mb_logi_enumerate() -> *mut c_char {
    bridge::run(ops::enumerate)
}

/// `{"ok":Settings}`: DPI and report rate, each `null` when unsupported.
///
/// # Safety
///
/// `route` is null or points to a NUL-terminated string valid for reads for
/// the duration of the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mb_logi_read_settings(route: *const c_char) -> *mut c_char {
    // SAFETY: forwarded from this function's contract.
    let route = unsafe { route_arg(route) };
    bridge::run(|| async move { ops::read_settings(&route?).await })
}

/// `{"ok":{"percent":80,"charging":false}}`, or `{"ok":null}` when the device
/// is offline or unreachable.
///
/// # Safety
///
/// `route` is null or points to a NUL-terminated string valid for reads for
/// the duration of the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mb_logi_read_battery(route: *const c_char) -> *mut c_char {
    // SAFETY: forwarded from this function's contract.
    let route = unsafe { route_arg(route) };
    bridge::run(|| async move { ops::read_battery(&route?).await })
}

/// `{"ok":null}` once the device took the new sensor DPI.
///
/// # Safety
///
/// `route` is null or points to a NUL-terminated string valid for reads for
/// the duration of the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mb_logi_set_dpi(route: *const c_char, dpi: u32) -> *mut c_char {
    // SAFETY: forwarded from this function's contract.
    let route = unsafe { route_arg(route) };
    bridge::run(|| async move { ops::set_dpi(&route?, dpi).await })
}

/// `{"ok":null}` once the device took the new report interval;
/// `{"error":"unsupported report rate"}` when it does not list `interval_ms`.
///
/// # Safety
///
/// `route` is null or points to a NUL-terminated string valid for reads for
/// the duration of the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mb_logi_set_report_rate(
    route: *const c_char,
    interval_ms: u8,
) -> *mut c_char {
    // SAFETY: forwarded from this function's contract.
    let route = unsafe { route_arg(route) };
    bridge::run(|| async move { ops::set_report_rate(&route?, interval_ms).await })
}

/// Releases a string this library returned. `NULL` is a no-op.
///
/// # Safety
///
/// `s` is null or a pointer one of this library's functions returned that has
/// not been freed yet.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn mb_logi_free(s: *mut c_char) {
    if !s.is_null() {
        // SAFETY: `s` came from `CString::into_raw` in this library and is
        // freed exactly once per this function's contract.
        drop(unsafe { CString::from_raw(s) });
    }
}
