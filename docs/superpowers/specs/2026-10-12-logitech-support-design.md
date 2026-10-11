# Logitech mouse support through OpenLogi's HID++ code

Date: 2026-10-12
Status: approved by the owner in plan mode (2026-10-12); "go for the implementation, use SDD"
Branch: `feat/logitech-support` (from `feat/hardware-check-wizard` at `5d74ab6`)

## 1. Purpose and success criteria

MouseBar supports SteelSeries mice only. The owner also uses a **Logitech G304 Lightspeed** (2021) on its USB receiver (`046d:c53f`, wireless product id `0x4074`) and wants MouseBar to show and set it too, without Logitech G HUB. The Logitech protocol is HID++ 2.0. Instead of writing a HID++ driver, MouseBar links the HID++ code of [OpenLogi](https://github.com/AprilNEA/OpenLogi) (Rust, MIT OR Apache-2.0; its `hidpp` crate is 0BSD) through a small C ABI.

Success means:

1. With the G304 receiver plugged in, MouseBar lists the G304 next to the SteelSeries mouse and the owner picks which one the menu bar shows.
2. For the G304, MouseBar shows the battery level and reads the current DPI and report rate from the mouse (HID++ can report them, so no "Default" capsule for those).
3. The owner can set DPI and report rate in Settings. Each write is read back; a mismatch is an error, not a silent success.
4. SteelSeries behavior does not change: same settings, same writes, the existing 106 tests pass.
5. `swift build`, `swift test`, CI and the release workflow build the Rust part themselves.

Non-goals: button remapping, lighting, onboard profiles, SmartShift, Bluetooth-only Logitech devices, Logitech in the Hardware Check wizard, Windows/Linux, more than one active mouse shown at a time. No new unit tests (owner's decision).

## 2. Findings that shape the design

- OpenLogi `0f69d75be99439da97291ff4163aba83dfc6df96` (v0.8.13) is a CLI, a background agent and a GUI; it has no API for other apps. Its crates are usable as libraries: `openlogi-hid` (host functions: `enumerate()`, `get_dpi_info(route)`, `set_dpi(route, dpi)`, transport over IOKit), `openlogi-core` (types: `DeviceInventory`, `PairedDevice { slot, codename, wpid, kind, online, battery, capabilities, … }`, `DeviceRoute`, `DpiInfo { current, capabilities }` where capabilities is a sorted list of supported values), `openlogi-hidpp` (features, including `ReportRateFeature` `0x8060`: `get_report_rate_list`, `get_report_rate`, `set_report_rate(ms)`). All inventory types derive `Serialize`.
- Lightspeed receivers use the Unifying protocol path: route `DeviceRoute::Unifying { receiver_uid, slot }`.
- `openlogi list` (read-only) on the owner's Mac: `Lightspeed Receiver (vid=046d pid=c53f)`, `slot 1 ○ Unknown device (mouse, wpid=4074, battery=—)`. `○` means `online: false`: the mouse was asleep or off for two minutes of polling, so battery, DPI and report rate are **not yet read on hardware**.
- OpenLogi's registry has no name for wpid `0x4074`; MouseBar names it.
- Only one program should drive a receiver at a time: G HUB, Logi Options+, Solaar and the OpenLogi agent conflict.
- Building OpenLogi's CLI took about 4 minutes on this Mac (Rust 1.99; OpenLogi needs 1.98+).

## 3. Architecture

```
MouseBar app ──► MouseCore (protocol MouseDriver) ◄── MouseDevice   (SteelSeries, unchanged I/O)
     │                                           ◄── LogitechDevice (MouseLogi)
     ├──► DeviceManager (SteelSeries IOHID, vendor 0x1038)
     └──► LogitechWatcher (MouseLogi; IOHID vendor 0x046D, usage page 0xFF00 → enumerate via FFI)
                                   MouseLogi ──► MouseBarLogiFFI (binary target, Rust static lib, C ABI, JSON)
                                                     └── openlogi-hid / openlogi-core / hidpp (pinned git rev)
```

### 3.1 Rust FFI crate `Rust/mousebar-logi`

- `crate-type = ["staticlib"]`, aarch64-apple-darwin only. Depends on `openlogi-hid`, `openlogi-core` and `hidpp` (package `openlogi-hidpp`) by `git = "https://github.com/AprilNEA/OpenLogi", rev = "0f69d75be99439da97291ff4163aba83dfc6df96"`, plus `tokio`, `serde`, `serde_json`. `Cargo.lock` is committed.
- One process-wide Tokio runtime (`OnceLock`). Every exported function blocks on it with a 5 s timeout, catches panics, and returns a heap C string with JSON: `{"ok": …}` or `{"error": "<message>"}`. `mb_logi_free(char *)` frees it.
- Its own flat DTOs, so OpenLogi's wire types never reach Swift. A device's route is passed to Swift as an opaque JSON string (serde of `DeviceRoute`) and handed back unchanged.
- C header `Rust/mousebar-logi/include/mousebar_logi.h` with a `module.modulemap`.
- `Scripts/build-logi.sh` builds the release static lib and packages `Vendor/MouseBarLogi.xcframework` (git-ignored). SwiftPM uses it as a `binaryTarget`.

### 3.2 `MouseDriver` seam in MouseCore

A protocol for one connected mouse, with exactly what `MouseSession`, `BatteryMonitor` and the hardware check use today: `apply`, `save`, `readBattery`, `rawBatteryQuery`, `close`, plus `readSettings()` (current values the mouse can report; default empty). `MouseDevice` conforms unchanged. `ConnectedMouse.device` and `BatteryMonitor` take `any MouseDriver`.

### 3.3 `MouseLogi` target (Swift)

- `LogiFFI`: async wrappers that run each blocking C call on one serial `DispatchQueue` and decode the JSON.
- `LogitechDevice: MouseDriver` (actor) for one receiver slot: `readBattery` (nil when offline), `readSettings` (DPI, report rate), `apply("dpi" | "polling_rate")` with read-back check, `save` no-op, `rawBatteryQuery` nil.
- `LogitechFamily`: builds a `DeviceFamily` per device from what it reports: setting `dpi` (`valueType: "range"`, `inputRange: [min, max, step]` from the supported list; the driver snaps to the nearest supported value) and setting `polling_rate` (`valueType: "choice"`, choices from the supported report rates, labelled in Hz). `persistsOnDevice: false` (re-applied on connect and on wake like the SteelSeries LED color), no battery spec, no save command.
- `LogitechNames`: wpid → name table (`0x4074`: "Logitech G304 / G305"); codename fallback, then "Logitech mouse".
- `LogitechWatcher` (actor): consumes an `HIDTransport` matching vendor `0x046D`, usage page `0xFF00` (no device is opened by the watcher, so no Input Monitoring prompt); on receiver add or remove it re-enumerates through the FFI (debounced 500 ms) and emits `DeviceEvent.connected` / `.disconnected` for mice (kind mouse). A mouse that is offline at enumeration still connects; its battery reads nil, so the app shows it asleep.

### 3.4 App

- `AppModel` merges the SteelSeries and Logitech event streams. A mouse picker (panel header menu) appears when more than one physical mouse is available; the choice is remembered in UserDefaults (`activeMouse`, the `DeviceModel.mouse` id). Without a remembered choice, the existing cable-over-dongle policy applies.
- Session start: stored values are re-applied as today; for keys not stored, values from `readSettings()` are shown, and those keys show no "Default" capsule.
- Settings tabs and panel controls stay data-driven: a tab with no settings for the active mouse is hidden; the LED swatch and DPI preset controls appear only when the family has those settings; "dpi" is mapped to Performance with the label "DPI".
- Hardware Check is SteelSeries-only: hidden for a Logitech mouse.
- Conflict banner: G HUB (`lghub`, `lghub_agent`, `lghub_updater`), Logi Options+ (`logioptionsplus_agent`) or the OpenLogi agent (`openlogi-agent`) running.
- `--demo` adds a simulated Logitech G304 (no FFI calls), so the picker and the Logitech UI can be driven without hardware. The real watcher never starts in demo mode.
- A read-only `logiprobe` executable prints the FFI's enumerate and settings JSON for the hardware check of this feature.

### 3.5 Build, CI, release

- CI and release workflows install the stable Rust toolchain (`rustup`, aarch64-apple-darwin), cache `~/.cargo` and `Rust/mousebar-logi/target`, and run `Scripts/build-logi.sh` before `swift build`.
- The app bundle carries `THIRD_PARTY_NOTICES.md` (OpenLogi MIT/Apache-2.0, hidpp 0BSD, Rust dependencies' licences) in `Contents/Resources`.

## 4. Safety

- Logitech writes happen only when the owner changes DPI or report rate in Settings, or when MouseBar re-applies a value the owner set before. Nothing is written on first connect of an unknown mouse.
- Every write is read back; a mismatch raises an error banner.
- No Logitech write is run on hardware during implementation. Read-only calls (`enumerate`, settings and battery reads) are allowed.
- SteelSeries safety rules stay in force.

## 5. Verification

- `Scripts/build-logi.sh` succeeds; `swift build --arch arm64` with zero warnings; `swift test` 106 pass; `--demo` launch with the simulated G304 selectable.
- Owner hardware run (read-only first): `logiprobe` with the G304 awake shows battery, DPI and report rate. Writes after that, with the owner's go-ahead. Results go in `docs/superpowers/notes/2026-10-12-logitech-g304-verification.md`.

## 6. Risks

- OpenLogi is pre-1.0 and changes often; MouseBar pins one revision and must be updated by hand.
- The G304 has onboard profiles (`0x8100`); in onboard mode DPI or report rate writes may be ignored or overridden. The read-back check exposes this.
- Bigger app binary and longer builds (Rust static lib, Tokio).
- The G304 has not answered yet on hardware (asleep or off during the spike).
