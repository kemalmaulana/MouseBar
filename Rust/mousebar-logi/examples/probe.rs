//! Hardware probe over the C ABI that changes no mouse setting: prints the version, the device
//! list, and the settings and battery of every online device.
//!
//! It never calls a setter.

use std::ffi::{CStr, CString, c_char};
use std::time::Instant;

use mousebar_logi::{
    mb_logi_enumerate, mb_logi_free, mb_logi_read_battery, mb_logi_read_settings,
    mb_logi_version,
};

/// Copies a library result into a `String` and frees it.
fn take(result: *mut c_char) -> String {
    // SAFETY: every library result is a non-null, NUL-terminated string from
    // `CString::into_raw`.
    let text = unsafe { CStr::from_ptr(result) }
        .to_string_lossy()
        .into_owned();
    // SAFETY: `result` came from this library and is freed exactly once.
    unsafe { mb_logi_free(result) };
    text
}

/// Runs one call and prints its JSON with how long it took.
fn show(label: &str, call: impl FnOnce() -> *mut c_char) -> String {
    let started = Instant::now();
    let text = take(call());
    println!("{label} ({} ms): {text}", started.elapsed().as_millis());
    text
}

fn main() {
    show("version", || mb_logi_version());
    let devices = show("enumerate", || mb_logi_enumerate());

    let parsed: serde_json::Value = serde_json::from_str(&devices).unwrap_or_default();
    for device in parsed["ok"].as_array().into_iter().flatten() {
        if device["online"] != true {
            continue;
        }
        let Some(Ok(route)) = device["route"].as_str().map(CString::new) else {
            continue;
        };
        println!("device {}:", route.to_string_lossy());
        // SAFETY: `route` is a live NUL-terminated string for both calls.
        show("  read_settings", || unsafe {
            mb_logi_read_settings(route.as_ptr())
        });
        // SAFETY: as above.
        show("  read_battery", || unsafe {
            mb_logi_read_battery(route.as_ptr())
        });
    }
}
