# MouseBar: native macOS companion app for SteelSeries mice

Date: 2026-10-10
Status: draft, awaiting user review
Working codename: `MouseBar` (renamable; the product name must not contain "SteelSeries").

## 1. Purpose and success criteria

SteelSeries GG 108.3.0 is unusable on this Apple Silicon Mac (macOS 27.0.1): it crashes, force-closes, and is unstable. MouseBar replaces GG for the user's mouse.

Success means:

1. The app is a native, arm64-only Swift app. No Rosetta, no x86_64 code, no kernel extension, no dependency on GG.
2. The battery level (and charging state) of the connected mouse is visible in the macOS menu bar at the top right.
3. Every setting the mouse exposes through rivalcfg can be changed from the app, and survives reconnects and reboots.
4. The user's SteelSeries Prime Mini Wireless is fully working (dongle and wired modes), verified on real hardware.
5. All other mice supported by rivalcfg (76 USB IDs) are reachable, clearly labelled as untested until verified.

Non-goals (v1): macros, animated or multi-zone lighting, GG's low-power gaming mode, Sonar/Prism/Moments/GameSense integrations, non-mouse SteelSeries devices, Windows/Linux, Intel Macs.

Distribution: personal use plus open source on GitHub, signed with a Developer ID if available, not sandboxed, not on the Mac App Store.

## 2. Findings that drive the design

### 2.1 SteelSeries GG on this system

- All executables are x86_64: `SteelSeries GG`, `SteelSeriesGG`, `SteelSeriesEngine`, `libSSEdevice.dylib`, and the Electron client (105 MB `app.asar`). GG runs only through Rosetta. A legacy `SteelSeriesEngine3Driver.kext` is installed in `/Library/Extensions`.
- GG's architecture is Electron UI, local Go services, `SteelSeriesEngine` (localhost HTTPS/WSS), `libSSEdevice`, HID. Its device descriptors (`.edevice`) are encrypted and are not used by this project.
- GG's logs show its device layer failing against the user's Prime Mini Wireless: `Error writing to SteelSeries Prime Mini Wireless(polling_rate) via SendCommand: 0xbeefbeef` (same on `direct_write`, `power_saving_timeout`, `default_lighting_enabled`, and reads of `fw_version_mouse` / `fw_version_dongle`), plus `Cannot monitor the Power Events`. This is evidence, not a proven root cause; the design does not depend on one.
- The user's mouse is a Prime Mini Wireless: `1038:1848` (2.4 GHz dongle) and `1038:184a` (wired).

### 2.2 rivalcfg 4.17.0

- `~/rivalcfg/rivalcfg` is an arm64 standalone build (Python 3.14 + hidapi, about 25 MB with libraries), WTFPL licensed, 76 USB IDs, 35 device profile files, 12 value-type handlers.
- It can set: DPI presets, polling rate, static LED color, button mapping, sleep timer, dim timer, startup lighting, factory reset; it can read battery level and charging state. It cannot read settings back, emit events, produce structured output, or do macros/animated lighting.
- Its profiles are declarative data, which makes a native port data-driven instead of per-device code.

### 2.3 Prime Wireless family protocol (reference for the first native driver)

Source: `rivalcfg/devices/prime_wireless_wired.py` and `prime_wireless_wireless.py`.

- HID interface (endpoint) 3, output reports.
- Opcodes: `0x2D` DPI, `0x2B` polling, `0x21 0x01 0x00` color, `0x2A` buttons, `0x29` sleep timer, `0x23 0x0F 0x01 0x00 0x00` dim timer, `0x27` startup lighting, `0x92` battery, `0x11 0x00` save.
- 2.4 GHz dongle variant: `command[0] |= 0x40`, 64-byte readback.
- Battery reply: `data[1]` bit 7 is the charging flag; level = `((data[1] & 0x7F) - 1) * 5`.
- Commands are spaced at least 50 ms apart (rivalcfg's `command_delay`; some mice misbehave if flooded).

## 3. Architecture

Swift Package `MouseCore` (no UI) plus a SwiftUI app target. Minimum macOS 14, arm64 only.

### 3.1 MouseCore units

Each unit has one purpose and a narrow interface.

| Unit | Purpose | Depends on |
|---|---|---|
| `HIDTransport` (protocol) | Open an interface, write an output report, read with timeout, stream hotplug events | none |
| `IOHIDTransport` | Real implementation on `IOHIDManager`, matching vendor `0x1038` | IOKit |
| `FakeTransport` | In-memory implementation for tests | none |
| `DeviceProfile` (Codable) | One mouse family: models (vid/pid/endpoint), settings (opcode bytes, value type, parameters, label, description, default), battery decoder tag, save command, wireless flag and readback length | generated `profiles.json` |
| `SettingEncoder` | One pure function per value type, `(setting, value) -> [UInt8]` (12 value types) | `DeviceProfile` |
| `MouseDevice` (actor) | Serializes commands with at least 50 ms spacing; applies settings; reads battery | `HIDTransport`, `SettingEncoder` |
| `DeviceManager` (actor) | Hotplug, product ID to profile, dongle vs wired; emits `DeviceEvent` | `HIDTransport`, `DeviceProfile` |
| `BatteryMonitor` | Polls battery about every 60 s plus on connect/wake; publishes level, charging, and freshness | `MouseDevice` |
| `SettingsStore` | Persists the desired state per device in `~/Library/Application Support/MouseBar/` and re-applies it on connect (the device is write-only) | `MouseDevice` |
| `MouseBackend` (protocol) | Common interface for applying settings and reading battery | none |
| `NativeBackend` | `MouseBackend` over `MouseDevice` | the units above |
| `CLIFallbackBackend` | `MouseBackend` that spawns the bundled `rivalcfg` with `Process` and parses `--battery-level` text | bundled binary |

### 3.2 Profile generator

`Tools/gen_profiles.py` imports pinned `rivalcfg==4.17.0` and writes:

1. `profiles.json`: all device profiles as data.
2. Golden vectors: for every setting and value type, the bytes rivalcfg writes, captured through rivalcfg's own `FakeDevice`.

Lambdas (battery and firmware decoders) cannot be serialized. They become tagged decoders (`"prime_wireless_battery"`, and so on) implemented by hand in Swift; there are only a handful.

### 3.3 App target

- `MenuBarExtra` with a battery SF Symbol and percentage in the label (bolt when charging, dimmed when stale or asleep). The menu shows device name, connection mode, battery, "Settings…", and Quit. A quick DPI preset switch is included only if the Phase 0 spike confirms that preset selection works through the sensitivity command.
- Settings window: pages generated from each profile's declared settings (rivalcfg ships a `label` and `description` per setting for exactly this purpose). Controls: DPI preset editor, polling rate, color picker, button remap grid, sleep and dim timers, startup lighting, factory reset.
- Launch at login via `SMAppService.mainApp`. Low-battery notification via `UNUserNotificationCenter` with a user-set threshold.
- `LSUIElement` is true (no Dock icon).

### 3.4 Support tiers

Shown per device in the UI:

1. **Verified**: tested on real hardware. v1 contains exactly one: Prime Mini Wireless.
2. **Profile-driven (untested)**: native driver generated from the rivalcfg profile. Disabled by default for each device; the user enables it with an explicit "I understand" toggle, because wrong bytes sent to an unverified mouse can misconfigure it (factory reset is the recovery).
3. **CLI fallback**: used when the native encoder cannot express a setting, or when the user selects it for a device.

## 4. Data flow

Hotplug event from `IOHIDManager` → `DeviceManager` resolves the profile and creates a `MouseDevice` → `SettingsStore` re-applies saved state → `BatteryMonitor` publishes state → SwiftUI observes it.

A UI edit goes to `SettingsStore` → `MouseDevice` encodes and writes → the setting is saved to the device with the profile's `save_command` when the profile defines one. Settings that rivalcfg documents as not persisted on the device (static color) are re-applied by `SettingsStore` on every connect.

Save rule: the device's internal memory (rivalcfg does not say whether it is EEPROM or flash) has limited write cycles. `SettingsStore` applies edits to the mouse immediately but debounces the `save_command`: it is sent once, about 2 seconds after the last edit, never per slider tick. The wireless dongle variant sends the save command with `command[0] |= 0x40` (`0x51 0x00`) and reads back 64 bytes; the wired variant sends `0x11 0x00`. Arbitrary byte writes to the device are out of scope; only settings defined in the profile are stored.

## 5. Error handling

- Device missing or interface not found: state is "disconnected"; no crash; recovery on the next hotplug event.
- HID write or read failure: retry once after the command delay; then mark the device "degraded" and offer the CLI fallback.
- Battery read with no reply: keep the last known value marked stale; after two consecutive failures show "asleep" with the last known value and its age. Never show 0% for a missing reply.
- GG running at the same time: detect a running `SteelSeriesEngine` process and show a warning. The app never kills it. The warning recommends uninstalling GG (`/Applications/SteelSeries GG/SteelSeries GG Uninstaller.app`).

## 6. Risks

| Risk | Mitigation |
|---|---|
| macOS HID permissions (Input Monitoring / TCC) for a non-sandboxed Developer ID app on macOS 27 are unverified | Phase 0 spike decides go or no-go for the native path before any app code |
| Only one mouse is available for hardware testing | Tier labels; per-device opt-in for untested profiles; golden-vector tests cover byte-level correctness for all profiles |
| rivalcfg is reverse-engineered; a firmware update could change behavior | Pin rivalcfg 4.17.0; keep the CLI fallback and golden tests so drift is detectable |
| Concurrent access with GG's engine | Detect and warn; recommend uninstalling GG |
| Trademark | Product name excludes "SteelSeries"; README credits rivalcfg and its author even though WTFPL does not require it |

## 7. Phases

0. **Spike** (requires the mouse to be plugged in; output is an answer, code is throwaway): run `~/rivalcfg/rivalcfg --battery-level` on dongle and wired; then a throwaway Swift script opens interface 3 through `IOHIDManager` and sends `0x92`. Confirms permissions, report format, the `0x40` wireless variant, and whether DPI preset selection works. Go or no-go.
1. **MVP**: `MouseCore` with native Prime Mini Wireless support and the menu bar battery item.
2. **Settings UI** for Prime Mini Wireless: all settings, persistence, re-apply on connect.
3. **Breadth**: `gen_profiles.py`, all 12 encoders with golden tests, tier-2 devices, `CLIFallbackBackend`.
4. **Polish**: launch at login, low-battery alerts, per-app profile switching (frontmost app via `NSWorkspace`), signing and notarization, GitHub release.

## 8. Verification

- **Unit**: for every value type and every profile, `SettingEncoder` output equals the golden vectors from rivalcfg byte for byte.
- **Integration on the real Prime Mini Wireless**: each setting applied from the app is observed on the mouse (DPI step, LED color, timers, button remap, polling rate) and matches what `rivalcfg` does for the same value; battery percentage matches `rivalcfg --battery-level`.
- **Hotplug**: unplugging and replugging the dongle, and mouse sleep and wake, update the menu bar state without relaunching the app.
- **Architecture**: build with `xcodebuild -destination 'platform=macOS,arch=arm64'`; `lipo -archs` on the app binary and on the bundled `rivalcfg` shows `arm64` only; `sysctl sysctl.proc_translated` reports `0` for the running app.
- **Coexistence**: with GG's engine running, the app shows the warning and does not crash.
