# Logitech Support (OpenLogi HID++) Implementation Plan

Spec: `docs/superpowers/specs/2026-10-12-logitech-support-design.md` (binding).
Branch: `feat/logitech-support` (from `feat/hardware-check-wizard` at `5d74ab6`).
Execution: superpowers:subagent-driven-development.

Goal: MouseBar shows and sets a Logitech G304 (Lightspeed receiver `046d:c53f`, wpid `0x4074`) next to the SteelSeries mouse, using OpenLogi's Rust HID++ crates through a small C ABI.

## Global Constraints

- arm64 only, macOS 14+, SwiftPM (`swift-tools-version: 6.2`). `MouseCore` stays Swift 6 language mode and strict-concurrency clean. `swift build --arch arm64` must print zero `warning:` and zero `error:` lines.
- No new unit tests and no TDD (owner's decision). Verification: zero-warning build, the existing `swift test` suite (106 tests) still passes, a `--demo` launch, read-only hardware probes.
- OpenLogi is pinned at `0f69d75be99439da97291ff4163aba83dfc6df96` (`https://github.com/AprilNEA/OpenLogi`). Never a branch or tag.
- Rust: stable toolchain (1.98+), target `aarch64-apple-darwin`, `MACOSX_DEPLOYMENT_TARGET=14.0`. `Cargo.lock` is committed. `target/` and `Vendor/` are never committed.
- **Hardware safety.** A real SteelSeries mouse and a real Logitech G304 are attached, and the owner may be running the real MouseBar.
  - Never launch MouseBar without `--demo`. Before a demo launch record `pgrep -x MouseBar`; afterwards kill only the new PID. Never `pkill`/`killall`.
  - Never touch `~/Library/Application Support/MouseBar`.
  - No `hidprobe`, no rivalcfg writes, no `openlogi diag`, no OpenLogi agent.
  - No Logitech write on hardware: never call `mb_logi_set_dpi` / `mb_logi_set_report_rate` (or anything that writes) against a real device. Read-only calls (`mb_logi_version`, `mb_logi_enumerate`, `mb_logi_read_settings`, `mb_logi_read_battery`, `logiprobe`) are allowed.
- Commits: conventional style, end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never commit `.DS_Store`, `build/`, `.build/`, `target/`, `Vendor/`, `design/`, `.superpowers/`.
- The implementer never dispatches subagents.

## Review Focus

1. FFI memory and threading: every returned string freed exactly once; no Rust panic crosses the C boundary; no call blocks the Swift cooperative pool or the main actor.
2. SteelSeries behavior unchanged (same writes, same order, same tests).
3. Logitech writes only on an owner action or a re-apply of a value the owner set; every write read back.
4. Nothing in demo mode reaches real hardware or the real settings store.
5. Licence notices for linked code.

## Interface (decided here, used across tasks)

C ABI (Task 1 produces, Task 2 consumes). Every `char *` result is UTF-8 JSON `{"ok": <value>}` or `{"error": "<message>"}`, owned by the caller, freed with `mb_logi_free`.

```c
char *mb_logi_version(void);   // {"ok":{"crate":"0.1.0","openlogi_rev":"0f69d75be99439da97291ff4163aba83dfc6df96"}}
char *mb_logi_enumerate(void); // {"ok":[Device, ...]}
char *mb_logi_read_settings(const char *route); // {"ok":Settings}
char *mb_logi_read_battery(const char *route);  // {"ok":{"percent":80,"charging":false}} or {"ok":null} when unreachable
char *mb_logi_set_dpi(const char *route, uint32_t dpi);            // {"ok":null}
char *mb_logi_set_report_rate(const char *route, uint8_t interval_ms); // {"ok":null}
void  mb_logi_free(char *s);
```

`Device`: `{"route": "<opaque string>", "receiver_name": "Lightspeed Receiver", "receiver_product_id": 50495, "slot": 1, "wpid": 16500 | null, "codename": "G305" | null, "kind": "mouse", "online": true, "battery": {"percent": 80, "charging": false} | null}`. `kind` is lowercase (`mouse`, `keyboard`, `other`, …). `route` is the serde JSON of OpenLogi's `DeviceRoute`, passed back unchanged; Swift never parses it.

`Settings`: `{"dpi": {"current": 1600, "supported": [200, 250, …]} | null, "report_rate": {"current_ms": 1, "supported_ms": [1, 2, 4, 8]} | null}` (null when the device lacks the feature).

Swift (Task 3 produces, Tasks 4-6 consume), in `Sources/MouseCore/MouseDriver.swift`:

```swift
public protocol MouseDriver: Actor {
    func apply(_ key: String, _ value: SettingValue) async throws
    func save() async throws
    func readBattery() async throws -> BatteryReading?
    func rawBatteryQuery() async throws -> [UInt8]?
    /// Current values the mouse can report itself; empty when it can't.
    func readSettings() async -> [String: SettingValue]
    func close() async
}
```

Logitech setting keys: `"dpi"` (`.int`) and `"polling_rate"` (`.choice("<Hz>")`, e.g. `"1000"`).

---

### Task 1: Rust FFI crate and build script

**Files:** create `Rust/mousebar-logi/Cargo.toml`, `Rust/mousebar-logi/Cargo.lock`, `Rust/mousebar-logi/src/lib.rs` (split into modules if it passes ~300 lines), `Rust/mousebar-logi/include/mousebar_logi.h`, `Rust/mousebar-logi/include/module.modulemap`, `Rust/mousebar-logi/examples/probe.rs`, `Scripts/build-logi.sh`; modify `.gitignore` (add `Vendor/` and `Rust/mousebar-logi/target/`).

1. `Cargo.toml`: package `mousebar-logi`, version `0.1.0`, edition 2024, `license = "MIT OR Apache-2.0"`, `[lib] crate-type = ["staticlib", "rlib"]` (rlib so the example links), dependencies `openlogi-hid`, `openlogi-core`, `hidpp = { package = "openlogi-hidpp", … }`, all three `git = "https://github.com/AprilNEA/OpenLogi", rev = "0f69d75be99439da97291ff4163aba83dfc6df96"`; plus `tokio` (`rt-multi-thread`, `time`), `serde` (derive), `serde_json`. `[profile.release] lto = "thin"`, `codegen-units = 1`, `panic = "unwind"` (needed by `catch_unwind`), `strip = "debuginfo"`.
2. Runtime: one `static RUNTIME: OnceLock<tokio::runtime::Runtime>` (multi-thread, 2 worker threads, `enable_all`). One internal helper runs an async closure with `block_on` + `tokio::time::timeout(5 s)`, inside `std::panic::catch_unwind`, and turns the outcome into the `{"ok"}` / `{"error"}` JSON (`CString::into_raw`). Error text is the error's `Display`; a timeout is `"timed out"`; a panic is `"internal error"`.
3. Implement the seven functions of the Interface section exactly, with `#[unsafe(no_mangle)] pub extern "C"`. Null or non-UTF-8 `route` gives `{"error":"invalid route"}`. `mb_logi_free(NULL)` is a no-op.
   - `mb_logi_enumerate`: `openlogi_hid::enumerate()`; one `Device` per `PairedDevice` of every `DeviceInventory`; `route` = `serde_json::to_string(&route)` of the `DeviceRoute` that reaches it (look at how OpenLogi's CLI/agent builds a route from an inventory entry and reuse that code, do not re-derive the rules).
   - `mb_logi_read_settings`: DPI via `openlogi_hid::get_dpi_info(&route)` (`current`, capabilities' sorted values); report rate via hidpp `ReportRateFeature` (`0x8060`: `get_report_rate_list`, `get_report_rate`), reached the same way `openlogi-device`'s `write/dpi.rs` reaches `AdjustableDpi` (channel from the route, feature lookup). A missing feature gives `null` for that part, not an error.
   - `mb_logi_read_battery`: the route's battery as percent + charging, `{"ok":null}` when the device is offline/unreachable. Prefer a direct HID++ battery read for that route through the helpers OpenLogi uses during inventory probing; if that is not reachable from the public API, enumerate and take the matching device's `battery`. Record which in the report.
   - `mb_logi_set_dpi`: `openlogi_hid::set_dpi(&route, Dpi)`. `mb_logi_set_report_rate`: hidpp `set_report_rate(ms)`, only when `ms` is in the supported list, else `{"error":"unsupported report rate"}`.
4. `include/mousebar_logi.h`: include guard, `<stdint.h>`, the seven prototypes with one comment line each (ownership: "free with mb_logi_free"). `include/module.modulemap`: `module MouseBarLogiFFI { header "mousebar_logi.h" export * }`.
5. `examples/probe.rs` (read-only): prints `mb_logi_version`, `mb_logi_enumerate`, then for each device with `online: true`, `mb_logi_read_settings` and `mb_logi_read_battery`; frees every string. It never calls a setter.
6. `Scripts/build-logi.sh` (`set -euo pipefail`, runs from any cwd): checks `cargo` exists (message: install with rustup), `rustup target add aarch64-apple-darwin` if missing, `MACOSX_DEPLOYMENT_TARGET=14.0 cargo build --release --locked --target aarch64-apple-darwin --manifest-path Rust/mousebar-logi/Cargo.toml`, then `rm -rf Vendor/MouseBarLogi.xcframework` and `xcodebuild -create-xcframework -library <…>/libmousebar_logi.a -headers Rust/mousebar-logi/include -output Vendor/MouseBarLogi.xcframework`. Prints the xcframework path and the static lib size.
7. Run `cargo rustc --release --target aarch64-apple-darwin --manifest-path Rust/mousebar-logi/Cargo.toml --crate-type staticlib -- --print native-static-libs` (or read it from a normal build) and write the exact `native-static-libs` line into the report: Task 2 needs it for linker settings.

**Verify:** `Scripts/build-logi.sh` succeeds; `nm -gU …/libmousebar_logi.a | grep mb_logi_` lists the seven symbols; `cargo run --release --example probe --manifest-path Rust/mousebar-logi/Cargo.toml` (read-only) prints JSON with the Lightspeed receiver and the wpid-16500 device (online or not); `cargo clippy --release` has no warnings in this crate. Record build time and static lib size.

**Commit:** `feat(logi): Rust FFI over OpenLogi's HID++ crates and xcframework build script`.

---

### Task 2: SwiftPM integration, `MouseLogi` bridge, `logiprobe`

**Files:** modify `Package.swift`; create `Sources/MouseLogi/LogiFFI.swift`, `Sources/MouseLogi/LogiTypes.swift`, `Sources/logiprobe/main.swift`.

1. `Package.swift`: add `.binaryTarget(name: "MouseBarLogiFFI", path: "Vendor/MouseBarLogi.xcframework")`; `.target(name: "MouseLogi", dependencies: ["MouseCore", "MouseBarLogiFFI"], linkerSettings: […])` in Swift 6 language mode, with linker settings from Task 1's `native-static-libs` line (frameworks via `.linkedFramework`, libraries via `.linkedLibrary`; skip `-lSystem`/`-lc`/`-lm` that Swift links anyway); `.executableTarget(name: "logiprobe", dependencies: ["MouseLogi"])`; add `"MouseLogi"` to the `MouseBar` target's dependencies; add `.library(name: "MouseLogi", targets: ["MouseLogi"])` and `.executable(name: "logiprobe", targets: ["logiprobe"])` products.
2. `LogiTypes.swift`: `Codable, Sendable, Equatable` structs matching the Interface JSON: `LogiDevice` (`route`, `receiverName`, `receiverProductID`, `slot`, `wpid: Int?`, `codename: String?`, `kind`, `online`, `battery: LogiBattery?`), `LogiBattery` (`percent`, `charging`), `LogiSettings` (`dpi: LogiDPI?`, `reportRate: LogiReportRate?`), `LogiDPI` (`current`, `supported`), `LogiReportRate` (`currentMs`, `supportedMs`), `LogiVersion` (`crate`, `openlogiRev`). Snake-case JSON keys via `CodingKeys` (not a decoder strategy, so the mapping is explicit). `LogiError: Error, CustomStringConvertible` (`.device(String)` from `{"error"}`, `.decoding(String)`).
3. `LogiFFI.swift`: `public enum LogiFFI` with `static func version() async throws -> LogiVersion`, `enumerate() async throws -> [LogiDevice]`, `readSettings(route:) async throws -> LogiSettings`, `readBattery(route:) async throws -> LogiBattery?`, `setDPI(route:dpi:) async throws`, `setReportRate(route:intervalMs:) async throws`. Each runs its C call on one private serial `DispatchQueue(label: "mousebar.logi.ffi")` inside `withCheckedThrowingContinuation`, copies the result with `String(cString:)`, calls `mb_logi_free` exactly once, and decodes `{"ok"}`/`{"error"}`. No C call runs on the caller's thread.
4. `logiprobe/main.swift` (read-only, async top-level code): prints `LogiFFI.version()`, every device from `enumerate()`, and for each online device `readSettings` and `readBattery`, as readable lines; exits 1 with the error text on failure. It never calls a setter.

**Verify:** `Scripts/build-logi.sh` (if `Vendor/` is missing), `swift build --arch arm64` zero warnings/errors (linker warnings count), `swift test` 106 pass, `swift run logiprobe` (read-only) prints the receiver and the wpid-16500 mouse. Paste the probe output into the report.

**Commit:** `feat(logi): Swift bridge to the Logitech FFI and a read-only logiprobe tool`.

---

### Task 3: `MouseDriver` seam in MouseCore

**Files:** create `Sources/MouseCore/MouseDriver.swift`; modify `Sources/MouseCore/MouseDevice.swift`, `Sources/MouseCore/DeviceManager.swift` (`ConnectedMouse`), `Sources/MouseCore/BatteryMonitor.swift`, plus any file that stops compiling because it used `MouseDevice`-only API through `mouse.device` (likely `Sources/MouseBar/HardwareCheck/CheckRunner.swift`, `Sources/MouseBar/AppModel.swift`, tests).

1. Add the `MouseDriver` protocol exactly as in the Interface section, plus `extension MouseDriver { public func readSettings() async -> [String: SettingValue] { [:] } }`.
2. `MouseDevice` conforms (`extension MouseDevice: MouseDriver {}`); no behavior change.
3. `ConnectedMouse.device` becomes `any MouseDriver`; `BatteryMonitor.init(device:)` takes `any MouseDriver`. Callers that read `device.family` / `device.model` switch to `mouse.family` / `mouse.model`.
4. No other change: no renames, no new behavior.

**Verify:** zero-warning build; `swift test` 106 pass; `--demo` launch per the safety rules.

**Commit:** `refactor(core): MouseDriver protocol so a mouse can come from another backend`.

---

### Task 4: Logitech driver, family, names, watcher

**Files:** create `Sources/MouseLogi/LogitechDevice.swift`, `Sources/MouseLogi/LogitechFamily.swift`, `Sources/MouseLogi/LogitechNames.swift`, `Sources/MouseLogi/LogitechWatcher.swift`, `Sources/MouseLogi/SimulatedLogitechDevice.swift`; modify `Sources/MouseHID/IOHIDTransport.swift`.

1. `IOHIDTransport.init(vendorID: Int = 0x1038, usagePage: Int? = nil)`: when `usagePage` is set, the matching dictionary also has `kIOHIDDeviceUsagePageKey`. Default behavior unchanged.
2. `LogitechNames.name(wpid:codename:)`: `0x4074` → `"Logitech G304 / G305"`; else the codename prefixed `"Logitech "`; else `"Logitech mouse"`.
3. `LogitechFamily.make(device: LogiDevice, settings: LogiSettings) -> (DeviceFamily, DeviceModel)`:
   - `DeviceModel`: `name` from `LogitechNames`, `mouse` = `"logitech-" + lowercase hex wpid` (4 digits; `"logitech-slot<N>"` if wpid is nil), `vendorId` `0x046D`, `productId` = receiver product id, `endpoint` 0, `isWireless` true.
   - `DeviceFamily`: `id` = model's `mouse`, `name` = model name, `models` = [model], `battery` nil, `saveCommand` nil, settings in this order:
     - when `settings.dpi` exists: key `"dpi"`, label `"DPI"`, `valueType "range"`, `inputRange [min, max, step]` where step is the smallest gap between consecutive supported values (at least 1), `defaultText` = current value as text, `persistsOnDevice false`, empty `command`/`commandSuffix`, `readbackLength 0`, `packetLength 0`.
     - when `settings.reportRate` exists: key `"polling_rate"`, label `"Polling rate"`, `valueType "choice"`, `choices` = one `ChoiceEntry(key: "<Hz>", value: <ms>)` per supported interval, Hz = `1000 / ms`, sorted by Hz ascending, `defaultText` = current Hz, `persistsOnDevice false`.
4. `LogitechDevice` (actor, `MouseDriver`): holds the `route`, the supported DPI list and supported intervals.
   - `readBattery()`: `LogiFFI.readBattery` → `BatteryReading(level: percent, isCharging: charging)` or nil; errors give nil (an unreachable mouse is asleep, not broken).
   - `readSettings()`: `LogiFFI.readSettings` → `["dpi": .int(current), "polling_rate": .choice("<Hz>")]` for the parts present; empty on error.
   - `apply("dpi", .int(v))`: snap `v` to the nearest supported value, `setDPI`, read back; if the read-back DPI differs, throw `MouseCoreError.invalidValue("The mouse kept \(actual) DPI instead of \(snapped). Its onboard profile may be in control.")`. `apply("polling_rate", .choice(hz))`: map to ms, `setReportRate`, read back the same way (message names Hz). Other keys throw `MouseCoreError.unknownSetting`. Wrong value types throw `MouseCoreError.valueMismatch`.
   - `save()` no-op; `rawBatteryQuery()` nil; `close()` no-op.
5. `LogitechWatcher` (actor): `init(transport: any HIDTransport)`, `nonisolated let events: AsyncStream<DeviceEvent>`, `start()`, `stop()`. On every transport `.added`/`.removed` it schedules one re-enumeration 500 ms later (events in that window coalesce). Enumeration keeps `kind == "mouse"` devices, builds `ConnectedMouse(hidID:family:model:device:)` with `LogitechFamily` and a `LogitechDevice` (one `readSettings` FFI call per newly seen online device), and diffs against the known set by `route`: new → `.connected`, gone → `.disconnected(hidID:)`. A device that is offline (or whose `readSettings` fails) connects with a family that has no settings. While any known device has no settings, the watcher re-enumerates every 30 s; when such a device answers `readSettings`, the watcher emits `.disconnected(hidID:)` then `.connected` with the rebuilt family and the same `hidID`, so the app starts a fresh session with the settings. `hidID` = FNV-1a 64-bit hash of the route string with the top bit set (never collides with IORegistry ids, which are below 2^63). Enumeration errors are ignored except the first, which is yielded as `.openFailed` with a synthetic `HIDDeviceInfo` (vendor `0x046D`) and the error text.
6. `SimulatedLogitechDevice` (actor, `MouseDriver`, for `--demo`): no FFI. Battery 80 % not charging; DPI supported 200…12000 step 50, current 1600; report rate supported 1/2/4/8 ms, current 1 ms; `apply` stores the value. `static func connectedMouse() -> ConnectedMouse` builds the family with `LogitechFamily` from equivalent `LogiDevice`/`LogiSettings` values (wpid `0x4074`, receiver product id `0xC53F`), hidID = `UInt64.max - 1`.

**Verify:** zero-warning build; `swift test` 106 pass; `swift run logiprobe` still works. No app wiring yet.

**Commit:** `feat(logi): Logitech mouse driver, settings family and receiver watcher`.

---

### Task 5: App wiring — both backends, mouse picker, readable settings

**Files:** modify `Sources/MouseBar/AppModel.swift`, `Sources/MouseCore/DeviceManager.swift` (`ActiveMousePolicy`), `Sources/MouseCore/MouseSession.swift`, `Sources/MouseBar/Views/MenuPanel.swift`, `Sources/MouseBar/Components/DefaultCapsule.swift` (or wherever the capsule is decided).

1. `ActiveMousePolicy.choose(from:preferred:)`: `preferred` is a `DeviceModel.mouse` id; if a mouse with that id is available, choose it (cable over dongle among its models); otherwise the existing rule. Keep the one-argument form calling it with `nil`.
2. `AppModel`: outside demo mode, also start `LogitechWatcher(transport: IOHIDTransport(vendorID: 0x046D, usagePage: 0xFF00))` and feed its events into the same handler as the SteelSeries `DeviceManager`. In demo mode, never start the watcher; instead add `SimulatedLogitechDevice.connectedMouse()` as an extra available mouse.
3. Picker: `AppModel` exposes the distinct physical mice available (one entry per `model.mouse`, name without the connection suffix) and `selectMouse(_ id:)`, which stores the id in `UserDefaults` key `activeMouse` (demo mode: in memory only) and switches the active session. `MenuPanel`'s header shows a `Menu` with those names when there is more than one; otherwise the header is unchanged.
4. `MouseSession.start`: after re-applying stored values, `let live = await mouse.device.readSettings()`; for each key in `live` with no stored value, set `values[key] = live[key]`. Expose `public var readableKeys: Set<String>` (the keys in `live`). `AppModel` mirrors it; the "Default" capsule is not shown for a key in `readableKeys`.
5. Session error text from Logitech read-back mismatches reaches the existing error banner unchanged.

**Verify:** zero-warning build; 106 tests pass; `--demo` launch: the panel shows a mouse menu with both mice; switching to the simulated G304 shows battery 80 %, Settings shows DPI 1600 and Polling rate 1000 Hz without "Default" capsules. (Drive the UI only if a UI-driving tool is available; otherwise say so in the report.)

**Commit:** `feat(app): Logitech mice next to SteelSeries with a mouse picker; show values the mouse reports`.

---

### Task 6: UI gating, names, conflict warning

**Files:** modify `Sources/MouseBar/Names/SettingsLayout.swift`, `Sources/MouseBar/Views/SettingsView.swift`, `Sources/MouseBar/Views/MenuPanel.swift`, `Sources/MouseBar/Views/DeviceTab.swift`, `Sources/MouseCore/GGDetector.swift` (or a new `ConflictDetector.swift` beside it), and the places that open the Hardware Check.

1. `SettingsLayout`: entry `"dpi": Entry(tab: .performance, order: 0, label: "DPI")`; `ValueFormat` shows `"1600 DPI"` for it.
2. Settings tabs: a tab with no settings for the active family is hidden (Device always shows). The selected tab falls back to Performance or Device if hidden.
3. `MenuPanel`: the LED swatch appears only when the family has a `"color"` setting; the polling control uses whatever `"polling_rate"` choices the family has (already data-driven; check it).
4. Hardware Check is SteelSeries-only: its panel footer item and the Device-tab button are hidden when the active mouse's `model.vendorId != 0x1038`.
5. Conflict detector: keep `GGDetector.isEngineRunning()` behavior and add `ConflictDetector.runningApps() -> [String]` returning display names for running processes: `SteelSeriesEngine`/`SteelSeriesGG` → "SteelSeries GG"; `lghub`, `lghub_agent`, `lghub_updater` → "Logitech G HUB"; `logioptionsplus_agent` → "Logi Options+"; `openlogi-agent` → "OpenLogi". The existing banner shows the SteelSeries text unchanged when GG runs; a Logitech conflict shows "<name> is running. It can fight MouseBar over the Logitech receiver. Quit it while you use MouseBar." Detection only; MouseBar never quits other apps.
6. `DeviceTab`: a "Protocol" row: SteelSeries → "SteelSeries (rivalcfg profiles)" with the existing profile version; Logitech → "Logitech HID++ (OpenLogi 0f69d75)" from `LogiFFI.version()` (short rev, 7 chars), "—" in demo mode.

**Verify:** zero-warning build; 106 tests pass; `--demo` launch with the simulated G304 selected: Buttons and Lighting tabs hidden, no Hardware Check item, DPI row labelled "DPI".

**Commit:** `feat(app): hide controls a mouse lacks, SteelSeries-only hardware check, Logitech conflict warning`.

---

### Task 7: CI, release, notices, README, verification note

**Files:** modify `.github/workflows/macos.yml`, `.github/workflows/release.yml`, `Scripts/bundle.sh`, `README.md`; create `THIRD_PARTY_NOTICES.md`, `docs/superpowers/notes/2026-10-12-logitech-g304-verification.md`.

1. Both workflows, in every job that runs `swift build`/`swift test`/`bundle.sh`: `dtolnay/rust-toolchain@stable` with `targets: aarch64-apple-darwin` (pin the action to a commit SHA you look up), `actions/cache@v4` for `~/.cargo/registry`, `~/.cargo/git` and `Rust/mousebar-logi/target` keyed on `Rust/mousebar-logi/Cargo.lock`, then `Scripts/build-logi.sh` before the Swift build. The zero-warning grep stays as is.
2. `Scripts/bundle.sh`: copies `THIRD_PARTY_NOTICES.md` into `Contents/Resources`; fails with a clear message if `Vendor/MouseBarLogi.xcframework` is missing.
3. `THIRD_PARTY_NOTICES.md`: rivalcfg (WTFPL, existing credit), OpenLogi (MIT OR Apache-2.0, copyright line from its repo), hidpp (0BSD, Lukas Schulte Pelkum), and the licence list of the Rust dependency tree produced by `cargo metadata --format-version 1 --manifest-path Rust/mousebar-logi/Cargo.toml` (name, version, licence per crate; a script one-liner in the file's header says how it was generated).
4. `README.md`: "Logitech mice" section: supported (G304 on Lightspeed tested only read-only so far), what works (battery, DPI, polling rate), quit G HUB/Options+ first, building needs Rust (`Scripts/build-logi.sh` before `swift build`), the onboard-profile caveat.
5. Verification note: rows for enumerate, battery, DPI read, report rate read, DPI write + read-back, report rate write + read-back, wake re-apply, picker; each `NOT RUN` except what Tasks 1-2 actually observed (enumeration: receiver found, wpid `4074`, online or not).

**Verify:** `actionlint` if installed (else say so); `Scripts/build-logi.sh && swift build --arch arm64` zero warnings; `Scripts/bundle.sh release` → `build/MouseBar.app` contains `Contents/Resources/THIRD_PARTY_NOTICES.md`, `lipo -archs` is `arm64`.

**Commit:** `ci: build the Logitech FFI in CI and release; licence notices and docs`.

---

## After the plan (owner)

- Wake the G304 (switch on, fresh AA) and run `swift run logiprobe` (read-only).
- With the owner's go-ahead: change DPI and polling rate in Settings on the G304 and fill the verification note.
