# MouseBar Phases 0–2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native arm64 macOS menu bar app that shows the battery of the user's SteelSeries Prime Mini Wireless and edits all of its rivalcfg-supported settings, talking to the mouse through our own Swift HID driver.

**Architecture:** `MouseCore` is a pure-Swift package target: data-driven profiles generated from rivalcfg 4.17.0, one pure encoder per value type, a `MouseDevice` actor over an abstract `HIDTransport`, battery monitoring, settings persistence, and a `MouseSession` that ties them together. `MouseHID` holds the only IOKit code (`IOHIDTransport`). `MouseBar` is the SwiftUI menu bar app. Golden byte vectors generated from rivalcfg's own fake device prove the encoders byte for byte; a simulated transport lets everything except real hardware be tested and demoed without a mouse.

**Tech Stack:** Swift 6.4 / Xcode 27 (installed here), SwiftPM only (no `.xcodeproj`), Swift Testing, SwiftUI `MenuBarExtra`, IOKit `IOHIDManager`, Python 3 + `rivalcfg==4.17.0` (generator tooling only, never shipped).

**Spec:** `docs/superpowers/specs/2026-10-10-macos-mouse-companion-design.md`

**Scope:** Spec phases 0, 1 and 2 (hardware spike, battery MVP, settings UI for the Prime Mini Wireless). Not in this plan: the other 75 USB IDs, `CLIFallbackBackend`, support tiers UI, launch at login, low-battery alerts, per-app profiles, notarization (spec phases 3–4 get their own plan).

## Global Constraints

- Native, arm64-only Swift app. No Rosetta, no x86_64 code, no kernel extension, no dependency on GG.
- Minimum macOS 14. `swift-tools-version: 6.0`. No Xcode project file; everything builds with `swift build --arch arm64`.
- The product name must not contain "SteelSeries". Codename `MouseBar`, bundle id `dev.mousebar.MouseBar`.
- Commands to the mouse are spaced at least 50 ms apart.
- Device save is debounced: sent once, about 2 s after the last edit, never per slider tick. Static LED color is not saved on the device and is re-applied on every connect.
- Battery polled about every 60 s. One failed read → stale. Two consecutive failed reads → asleep. A missing reply never shows as 0%.
- rivalcfg is pinned to 4.17.0. Credit rivalcfg and its author in the README.
- Not sandboxed. If GG's `SteelSeriesEngine` process is running, warn; never kill it.
- `LSUIElement` is true (no Dock icon).
- All commits end with the trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

The spec implies these inputs but no happy-path test would exercise them. Each has a test in the task named in brackets.

1. **Mouse asleep or out of range**: battery read times out. Expect last known value with an "asleep" label after two failures, never 0%. [Task 9]
2. **Garbage battery byte** (`0x00`, anything above `0x15` after masking, or a 1-byte reply). Expect "unreadable", never a negative or over-100% level. [Task 6]
3. **DPI list of 0 presets, 6 presets, or values outside 100–18000.** Expect a thrown error for 0 and 6, nearest-supported clamping for out-of-range, and nothing written to the device on error. [Task 4]
4. **Button remap that leaves no left click** (for example `button1=disabled` with nothing mapped to `button1`). Expect rejection before any write, because the user could lose the ability to click. [Tasks 5 and 11]
5. **Dongle and USB cable connected at the same time.** Expect the wired device to be used, and a fall back to the dongle when the cable is removed. [Task 9]

## File Structure

```
Package.swift
.gitignore
README.md
Scripts/bundle.sh                         # builds MouseBar.app (Task 12)
Tools/requirements.txt                    # rivalcfg==4.17.0
Tools/gen_profiles.py                     # emits Generated/GeneratedProfiles.swift + golden.json
Sources/MouseCore/                        # pure Swift 6, no IOKit
  Generated/GeneratedProfiles.swift       # generated: profiles + layouts JSON as string constants
  Values.swift                            # MouseCoreError, Bytes, RGBColor, ButtonMapping, SettingValue
  Profiles.swift                          # DeviceFamily/Model/SettingSpec, ProfileCatalog, ButtonLayouts
  SettingEncoder.swift                    # choice, range, rgbcolor, multidpi_range_choice, buttons
  Battery.swift                           # BatteryReading, BatteryDecoder
  HID.swift                               # HIDTransport/HIDConnection protocols, HIDDeviceInfo, HIDError
  SimulatedHID.swift                      # SimulatedHIDTransport/Connection (tests + --demo)
  Sleeper.swift                           # Sleeper protocol + SystemSleeper
  MouseDevice.swift                       # actor: paced writes, readback, retry, save, battery
  DeviceManager.swift                     # hotplug -> ConnectedMouse, ActiveMousePolicy
  BatteryMonitor.swift                    # BatteryState, BatteryMonitor, BatteryPresentation
  SettingsStore.swift                     # per-mouse persisted desired state + DefaultSettings
  SaveDebouncer.swift
  MouseSession.swift                      # apply-on-connect, set/submit/reset, debounced save, battery loop
  GGDetector.swift
Sources/MouseHID/                         # Swift 5 language mode, IOKit only
  IOHIDTransport.swift
  IOHIDConnection.swift
Sources/hidprobe/main.swift               # diagnostic CLI (Phase 0 spike tool, kept)
Sources/MouseBar/                         # SwiftUI app, Swift 5 language mode
  MouseBarApp.swift, AppModel.swift, AppDelegate.swift, DemoTransport.swift
  Views/BatteryLabel.swift, MenuContent.swift, SettingsView.swift, SettingRows.swift
Tests/MouseCoreTests/
  Fixtures/golden.json                    # generated
  Support/Golden.swift, Support/TestDoubles.swift
  *Tests.swift
docs/superpowers/notes/                   # spike + hardware verification notes
```

---

### Task 1: Scaffold, generator, generated data

**Files:**
- Create: `.gitignore`, `Package.swift`, `Tools/requirements.txt`, `Tools/gen_profiles.py`
- Create: `Sources/MouseBar/main.swift` (placeholder, deleted in Task 12), `Sources/hidprobe/main.swift` (placeholder, replaced in Task 8), `Sources/MouseHID/Placeholder.swift` (deleted in Task 8)
- Generated: `Sources/MouseCore/Generated/GeneratedProfiles.swift`, `Tests/MouseCoreTests/Fixtures/golden.json`

**Interfaces:**
- Produces: `GeneratedData.profilesJSON: String` and `GeneratedData.layoutsJSON: String` (internal to `MouseCore`); `golden.json` with this shape:
  `{"rivalcfgVersion": "4.17.0", "families": {"<familyId>": {"settings": [{"setting": String, "value": <SettingValue JSON>, "hex": String}], "saveHex": String, "batteryQueryHex": String, "battery": [{"reply": hexString, "expected": {"level": Int, "isCharging": Bool} | null}]}}}`
- `profilesJSON` shape: `{"rivalcfgVersion": String, "families": [DeviceFamily]}` where camelCase keys match Task 2's Codable structs exactly (see `Profiles.swift` in Task 2).
- `layoutsJSON` shape: `{"keyboard": {name: code}, "multimedia": {name: code}, "keyboardKeys": [String], "multimediaKeys": [String]}`. `keyboard`/`multimedia` are lowercased with aliases resolved; the `*Keys` lists hold canonical display names in rivalcfg order.

- [ ] **Step 1: Commit the existing spec and this plan**

```bash
cd /Users/maulana/XcodeProjects/Steelseries
git add docs
git commit -m "docs: add MouseBar design spec and phase 0-2 implementation plan" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2: Write `.gitignore`**

```
.build/
.venv/
build/
*.xcuserstate
.DS_Store
.swiftpm/
```

- [ ] **Step 3: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MouseBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MouseCore", targets: ["MouseCore"]),
        .executable(name: "MouseBar", targets: ["MouseBar"]),
        .executable(name: "hidprobe", targets: ["hidprobe"]),
    ],
    targets: [
        // Pure logic. Swift 6 language mode, no IOKit.
        .target(name: "MouseCore"),
        // The only IOKit code. Swift 5 mode: C callbacks and CF types fight strict concurrency.
        .target(
            name: "MouseHID",
            dependencies: ["MouseCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "hidprobe",
            dependencies: ["MouseCore", "MouseHID"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MouseBar",
            dependencies: ["MouseCore", "MouseHID"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MouseCoreTests",
            dependencies: ["MouseCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 4: Write placeholders so the package builds**

`Sources/MouseBar/main.swift`:
```swift
print("MouseBar placeholder")
```
`Sources/hidprobe/main.swift`:
```swift
print("hidprobe placeholder")
```
`Sources/MouseHID/Placeholder.swift`:
```swift
enum Placeholder {}
```

- [ ] **Step 5: Write `Tools/requirements.txt`**

```
rivalcfg==4.17.0
```

- [ ] **Step 6: Write `Tools/gen_profiles.py`**

```python
#!/usr/bin/env python3
"""Generate MouseCore data from rivalcfg: profiles, button layouts, golden byte vectors.

Run inside a venv that has rivalcfg==4.17.0 (see Tools/requirements.txt):
    .venv/bin/python -I Tools/gen_profiles.py
"""
import json
import os
import sys
import tempfile
from pathlib import Path

# Must be set before importing rivalcfg: fake device, no pacing, throwaway settings dir
# (rivalcfg keeps a local settings cache under $XDG_CONFIG_HOME; keep it out of ~/.config).
os.environ["RIVALCFG_DRY"] = "1"
os.environ["RIVALCFG_DEBUG_NO_COMMAND_DELAY"] = "1"
os.environ["XDG_CONFIG_HOME"] = tempfile.mkdtemp(prefix="rivalcfg-gen-")

from rivalcfg import mouse as rivalcfg_mouse  # noqa: E402
from rivalcfg.version import VERSION  # noqa: E402
from rivalcfg.devices import prime_wireless_wired, prime_wireless_wireless  # noqa: E402
from rivalcfg.handlers.buttons import layout_multimedia, layout_qwerty  # noqa: E402

PINNED_VERSION = "4.17.0"
ROOT = Path(__file__).resolve().parent.parent
SWIFT_OUT = ROOT / "Sources/MouseCore/Generated/GeneratedProfiles.swift"
GOLDEN_OUT = ROOT / "Tests/MouseCoreTests/Fixtures/golden.json"

# family id -> (rivalcfg profile dict, is_wireless, product id used to open the fake device)
FAMILIES = {
    "prime_wireless_wired": (prime_wireless_wired.profile, False, 0x184A),
    "prime_wireless_wireless": (prime_wireless_wireless.profile, True, 0x1848),
}
# product id -> physical mouse (wired + dongle of the same mouse share saved settings)
MOUSE_GROUP = {
    0x1842: "prime_wireless",
    0x1840: "prime_wireless",
    0x184A: "prime_mini_wireless",
    0x1848: "prime_mini_wireless",
}
# rivalcfg docs: Prime Wireless LED colors are not saved to onboard memory
NOT_PERSISTED = {"color"}


def setting_dict(key, info):
    out = {
        "key": key,
        "label": info["label"],
        "description": info["description"],
        "command": list(info["command"]),
        "commandSuffix": list(info.get("command_suffix", [])),
        "valueType": info.get("value_type") or "none",
        "defaultText": str(info.get("default", "")),
        "readbackLength": info.get("readback_length", 0),
        "packetLength": info.get("packet_length", 0),
        "persistsOnDevice": key not in NOT_PERSISTED,
    }
    optional = {
        "inputRange": info.get("input_range"),
        "outputRange": info.get("output_range"),
        "rangeLengthByte": info.get("range_length_byte"),
        "dpiLengthByte": info.get("dpi_length_byte"),
        "firstPreset": info.get("first_preset"),
        "maxPresetCount": info.get("max_preset_count"),
        "buttonFieldLength": info.get("button_field_length"),
        "buttonDisable": info.get("button_disable"),
        "buttonKeyboard": info.get("button_keyboard"),
        "buttonMultimedia": info.get("button_multimedia"),
        "buttonDpiSwitch": info.get("button_dpi_switch"),
        "buttonScrollUp": info.get("button_scroll_up"),
        "buttonScrollDown": info.get("button_scroll_down"),
    }
    out.update({k: v for k, v in optional.items() if v is not None})
    if "choices" in info:
        out["choices"] = [{"key": str(k), "value": v} for k, v in info["choices"].items()]
    if "output_choices" in info:
        out["outputChoices"] = [[k, v] for k, v in sorted(info["output_choices"].items())]
    if "buttons" in info:
        out["buttons"] = [
            {"name": n, "id": d["id"], "offset": d["offset"], "defaultAction": d["default"]}
            for n, d in info["buttons"].items()
        ]
    return out


def family_dict(family_id, profile, wireless):
    battery = profile["battery_level"]
    save = profile["save_command"]
    return {
        "id": family_id,
        "name": profile["name"],
        "models": [
            {
                "name": m["name"],
                "mouse": MOUSE_GROUP[m["product_id"]],
                "vendorId": m["vendor_id"],
                "productId": m["product_id"],
                "endpoint": m["endpoint"],
                "isWireless": wireless,
            }
            for m in profile["models"]
        ],
        "settings": [setting_dict(k, v) for k, v in profile["settings"].items()],
        "battery": {
            "command": list(battery["command"]),
            "responseLength": battery["response_length"],
            "readbackLength": battery.get("readback_length", 0),
            "decoder": "prime_wireless",
        },
        "saveCommand": {
            "command": list(save["command"]),
            "readbackLength": save.get("readback_length", 0),
        },
    }


def resolved_layout(module):
    """Same as rivalcfg's build_layout(): lowercased names, aliases resolved."""
    full = {k.lower(): v for k, v in module.layout.items()}
    for alias, ref in module.aliases.items():
        full[alias.lower()] = module.layout[ref]
    return full


# ---- golden cases: (setting key, rivalcfg call args, SettingValue JSON) ----
def dpi(presets, selected=None):
    return {"type": "dpi", "presets": presets, "selected": selected}


def choice(value):
    return {"type": "choice", "value": str(value)}


def integer(value):
    return {"type": "int", "value": value}


def color(r, g, b):
    return {"type": "color", "r": r, "g": g, "b": b}


def buttons(assignments):
    """rivalcfg wants the 'buttons(a=b; c=d)' string; Swift gets the dict."""
    if not assignments:
        return ("default",), {"type": "buttons", "assignments": {}}
    text = "buttons(" + "; ".join(f"{k}={v}" for k, v in assignments.items()) + ")"
    return (text,), {"type": "buttons", "assignments": assignments}


def setting_cases():
    cases = [
        ("sensitivity", ("400, 800, 1200, 2400, 3200",), dpi([400, 800, 1200, 2400, 3200])),
        ("sensitivity", ("800",), dpi([800])),
        ("sensitivity", ("100, 18000",), dpi([100, 18000])),
        ("sensitivity", ("400, 800, 1200", 1), dpi([400, 800, 1200], 1)),
        ("sensitivity", ("150, 17999",), dpi([150, 17999])),
        ("polling_rate", (1000,), choice(1000)),
        ("polling_rate", (500,), choice(500)),
        ("polling_rate", (250,), choice(250)),
        ("polling_rate", (125,), choice(125)),
        ("color", ((255, 128, 0),), color(255, 128, 0)),
        ("color", ((255, 0, 0),), color(255, 0, 0)),
        ("color", ((0, 255, 0),), color(0, 255, 0)),
        ("sleep_timer", (5,), integer(5)),
        ("sleep_timer", (0,), integer(0)),
        ("sleep_timer", (20,), integer(20)),
        ("sleep_timer", (25,), integer(25)),
        ("dim_timer", (30,), integer(30)),
        ("dim_timer", (0,), integer(0)),
        ("dim_timer", (1200,), integer(1200)),
        ("default_lighting", ("off",), choice("off")),
        ("default_lighting", ("rainbow",), choice("rainbow")),
    ]
    for assignments in [
        {},
        {"button1": "button2", "button2": "button1"},
        {"button6": "PlayPause", "button4": "VolumeUp"},
        {"button5": "disabled", "button3": "a"},
        {"button4": "vol+", "button5": "prev"},
        {"scrolldown": "scrollup"},
        {"button4": "dpi"},
    ]:
        args, value = buttons(assignments)
        cases.append(("buttons_mapping", args, value))
    return cases


BATTERY_REPLIES = [
    [0x00, 0x15],  # 100%
    [0x00, 0x95],  # 100%, charging
    [0x00, 0x0B],  # 50%
    [0x00, 0x02],  # 5%
    [0x00, 0x01],  # 0% (valid)
    [0x00, 0x00],  # -5 -> unreadable
    [0x00, 0x16],  # 105 -> unreadable
    [0x00],        # too short -> unreadable
]


def expected_battery(profile, data):
    info = profile["battery_level"]
    try:
        level = info["level"](data)
        charging = info["is_charging"](data)
    except Exception:
        return None
    if level < 0 or level > 100:
        return None
    return {"level": level, "isCharging": bool(charging)}


def capture_family(profile, product_id):
    mouse = rivalcfg_mouse.get_mouse(0x1038, product_id)
    device = mouse._hid_device

    def take():
        raw = device.bytes.getvalue()
        device.bytes.seek(0)
        device.bytes.truncate()
        return raw[2:].hex()  # drop FakeDevice's report-type byte and the report id

    rows = []
    for key, args, value in setting_cases():
        getattr(mouse, "set_" + key)(*args)
        rows.append({"setting": key, "value": value, "hex": take()})
    mouse.save()
    save_hex = take()
    mouse.battery  # noqa: B018  (property access sends the query)
    battery_hex = take()
    return {
        "settings": rows,
        "saveHex": save_hex,
        "batteryQueryHex": battery_hex,
        "battery": [
            {"reply": bytes(r).hex(), "expected": expected_battery(profile, r)}
            for r in BATTERY_REPLIES
        ],
    }


SWIFT_TEMPLATE = '''// Generated by Tools/gen_profiles.py from rivalcfg {version}. Do not edit.

enum GeneratedData {{
    static let profilesJSON = #"""
{profiles}
"""#

    static let layoutsJSON = #"""
{layouts}
"""#
}}
'''


def main():
    if VERSION != PINNED_VERSION:
        sys.exit(f"rivalcfg {VERSION} installed, expected {PINNED_VERSION}")

    profiles = {
        "rivalcfgVersion": VERSION,
        "families": [family_dict(fid, p, w) for fid, (p, w, _) in FAMILIES.items()],
    }
    layouts = {
        "keyboard": resolved_layout(layout_qwerty),
        "multimedia": resolved_layout(layout_multimedia),
        "keyboardKeys": list(layout_qwerty.layout.keys()),
        "multimediaKeys": list(layout_multimedia.layout.keys()),
    }
    golden = {
        "rivalcfgVersion": VERSION,
        "families": {fid: capture_family(p, pid) for fid, (p, _, pid) in FAMILIES.items()},
    }

    SWIFT_OUT.parent.mkdir(parents=True, exist_ok=True)
    SWIFT_OUT.write_text(
        SWIFT_TEMPLATE.format(
            version=VERSION,
            profiles=json.dumps(profiles, separators=(",", ":")),
            layouts=json.dumps(layouts, separators=(",", ":")),
        )
    )
    GOLDEN_OUT.parent.mkdir(parents=True, exist_ok=True)
    GOLDEN_OUT.write_text(json.dumps(golden, indent=1) + "\n")
    cases = sum(len(f["settings"]) for f in golden["families"].values())
    print(f"wrote {SWIFT_OUT.relative_to(ROOT)} and {GOLDEN_OUT.relative_to(ROOT)} "
          f"({len(profiles['families'])} families, {cases} golden setting cases)")


if __name__ == "__main__":
    main()
```

- [ ] **Step 7: Create the venv and run the generator**

```bash
cd /Users/maulana/XcodeProjects/Steelseries
python3 -m venv .venv
.venv/bin/pip install -q -r Tools/requirements.txt
.venv/bin/python -I Tools/gen_profiles.py
```
Expected: `wrote Sources/MouseCore/Generated/GeneratedProfiles.swift and Tests/MouseCoreTests/Fixtures/golden.json (2 families, 56 golden setting cases)`.

- [ ] **Step 8: Check the output is sane and deterministic**

```bash
cd /Users/maulana/XcodeProjects/Steelseries
shasum Sources/MouseCore/Generated/GeneratedProfiles.swift Tests/MouseCoreTests/Fixtures/golden.json > /tmp/gen1.sha
.venv/bin/python -I Tools/gen_profiles.py >/dev/null
shasum Sources/MouseCore/Generated/GeneratedProfiles.swift Tests/MouseCoreTests/Fixtures/golden.json | diff - /tmp/gen1.sha && echo deterministic
```
Expected: `deterministic`.

```bash
python3 - <<'EOF'
import json
g = json.load(open("Tests/MouseCoreTests/Fixtures/golden.json"))
def hexes(fid, setting): return [c["hex"] for c in g["families"][fid]["settings"] if c["setting"] == setting]
assert hexes("prime_wireless_wired", "sensitivity")[0] == "2d050004090d1b26"
assert hexes("prime_wireless_wireless", "sensitivity")[0] == "6d050004090d1b26"
assert g["families"]["prime_wireless_wired"]["saveHex"] == "1100"
assert g["families"]["prime_wireless_wireless"]["saveHex"] == "5100"
assert g["families"]["prime_wireless_wired"]["batteryQueryHex"] == "92"
assert g["families"]["prime_wireless_wireless"]["batteryQueryHex"] == "d2"
print("golden spot checks ok")
EOF
```
Expected: `golden spot checks ok`.

- [ ] **Step 9: Build**

Run: `swift build --arch arm64`
Expected: `Build complete!`

- [ ] **Step 10: Commit**

```bash
git add .gitignore Package.swift Tools Sources Tests
git commit -m "build: scaffold package and rivalcfg profile/golden generator" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Value types and profile catalog

**Files:**
- Create: `Sources/MouseCore/Values.swift`, `Sources/MouseCore/Profiles.swift`
- Create: `Tests/MouseCoreTests/Support/Golden.swift`
- Test: `Tests/MouseCoreTests/ProfileCatalogTests.swift`, `Tests/MouseCoreTests/ValuesTests.swift`

**Interfaces:**
- Produces (all `public` unless noted):
  - `enum MouseCoreError: Error, Equatable, Sendable { case overflow, unknownSetting(String), unsupportedValueType(String), valueMismatch(setting: String, expected: String), invalidValue(String), noPrimaryClick }`
  - `enum Bytes` (internal): `static func littleEndian(_ value: Int, length: Int) throws -> [UInt8]`, `static func u8(_ ints: [Int]) -> [UInt8]`
  - `struct RGBColor: Equatable, Sendable, Codable { var r, g, b: UInt8; init(r:g:b:); init?(parsing: String); var hexString: String }`
  - `struct ButtonMapping: Equatable, Sendable, Codable { var assignments: [String: String]; init(assignments: [String: String] = [:]) }` (keys and values lowercased)
  - `enum SettingValue: Equatable, Sendable, Codable { case int(Int), choice(String), dpiPresets(presets: [Int], selected: Int?), color(RGBColor), buttons(ButtonMapping) }`
  - `struct ChoiceEntry: Codable, Sendable { var key: String; var value: Int }`, `struct ButtonSpec: Codable, Sendable { var name: String; var id: Int; var offset: Int; var defaultAction: String }`
  - `struct SettingSpec: Codable, Sendable, Identifiable` with the fields listed in Step 3 below
  - `struct CommandSpec`, `struct BatterySpec`, `struct DeviceModel`, `struct DeviceFamily` (`func setting(_ key: String) -> SettingSpec?`), `struct MatchedProfile`, `struct ProfileCatalog` (`static func load() throws -> ProfileCatalog`, `func match(vendorID:productID:) -> MatchedProfile?`), `struct ButtonLayouts` (`static func load() throws -> ButtonLayouts`)
  - Test support: `GoldenFile` (`static func load() throws -> GoldenFile`), `func hex(_ bytes: [UInt8]) -> String`, `func spec(_ familyID: String, _ key: String) throws -> SettingSpec`

- [ ] **Step 1: Write the failing tests**

`Tests/MouseCoreTests/Support/Golden.swift`:
```swift
import Foundation
import Testing
@testable import MouseCore

let primeFamilyIDs = ["prime_wireless_wired", "prime_wireless_wireless"]

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

func bytes(fromHex text: String) -> [UInt8] {
    stride(from: 0, to: text.count, by: 2).map { i in
        let start = text.index(text.startIndex, offsetBy: i)
        return UInt8(text[start..<text.index(start, offsetBy: 2)], radix: 16)!
    }
}

struct GoldenFile: Decodable {
    struct Case: Decodable {
        let setting: String
        let value: SettingValue
        let hex: String
    }
    struct Expected: Decodable, Equatable {
        let level: Int
        let isCharging: Bool
    }
    struct Battery: Decodable {
        let reply: String
        let expected: Expected?
    }
    struct Family: Decodable {
        let settings: [Case]
        let saveHex: String
        let batteryQueryHex: String
        let battery: [Battery]
    }
    let rivalcfgVersion: String
    let families: [String: Family]

    static func load() throws -> GoldenFile {
        let url = try #require(
            Bundle.module.url(forResource: "golden", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(GoldenFile.self, from: Data(contentsOf: url))
    }
}

func spec(_ familyID: String, _ key: String) throws -> SettingSpec {
    let catalog = try ProfileCatalog.load()
    let family = try #require(catalog.families.first { $0.id == familyID })
    return try #require(family.setting(key))
}

/// Checks the encoder against every golden case of `familyID` whose setting key is in `keys`.
func assertGolden(familyID: String, keys: Set<String>) throws {
    let golden = try #require(try GoldenFile.load().families[familyID])
    let encoder = SettingEncoder(layouts: try ButtonLayouts.load())
    var checked = 0
    for c in golden.settings where keys.contains(c.setting) {
        let encoded = try encoder.encode(try spec(familyID, c.setting), value: c.value)
        #expect(hex(encoded) == c.hex, "\(familyID) \(c.setting) \(c.value)")
        checked += 1
    }
    #expect(checked > 0, "no golden cases for \(keys)")
}
```

`Tests/MouseCoreTests/ProfileCatalogTests.swift`:
```swift
import Testing
@testable import MouseCore

@Suite struct ProfileCatalogTests {
    @Test func loadsBothPrimeWirelessFamilies() throws {
        let catalog = try ProfileCatalog.load()
        #expect(catalog.rivalcfgVersion == "4.17.0")
        #expect(catalog.families.map(\.id) == primeFamilyIDs)
    }

    @Test func matchesDongleToWirelessFamily() throws {
        let catalog = try ProfileCatalog.load()
        let match = try #require(catalog.match(vendorID: 0x1038, productID: 0x1848))
        #expect(match.family.id == "prime_wireless_wireless")
        #expect(match.model.name == "SteelSeries Prime Mini Wireless (2.4 GHz wireless mode)")
        #expect(match.model.endpoint == 3)
        #expect(match.model.mouse == "prime_mini_wireless")
        #expect(match.model.isWireless)
    }

    @Test func matchesCableToWiredFamilyWithSameMouseGroup() throws {
        let catalog = try ProfileCatalog.load()
        let match = try #require(catalog.match(vendorID: 0x1038, productID: 0x184A))
        #expect(match.family.id == "prime_wireless_wired")
        #expect(match.model.mouse == "prime_mini_wireless")
        #expect(!match.model.isWireless)
    }

    @Test func unknownProductDoesNotMatch() throws {
        let catalog = try ProfileCatalog.load()
        #expect(catalog.match(vendorID: 0x1038, productID: 0xFFFF) == nil)
        #expect(catalog.match(vendorID: 0x046D, productID: 0x1848) == nil)
    }

    @Test func wiredFamilyDeclaresTheSevenRivalcfgSettingsInOrder() throws {
        let catalog = try ProfileCatalog.load()
        let family = try #require(catalog.families.first { $0.id == "prime_wireless_wired" })
        #expect(family.settings.map(\.key) == [
            "sensitivity", "polling_rate", "color", "buttons_mapping",
            "sleep_timer", "dim_timer", "default_lighting",
        ])
        #expect(family.saveCommand?.command == [0x11, 0x00])
        #expect(family.battery?.command == [0x92])
    }

    @Test func wirelessFamilyCommandsCarryTheWirelessFlagAndReadback() throws {
        let catalog = try ProfileCatalog.load()
        let family = try #require(catalog.families.first { $0.id == "prime_wireless_wireless" })
        #expect(family.setting("polling_rate")?.command == [0x6B])
        #expect(family.setting("polling_rate")?.readbackLength == 64)
        #expect(family.saveCommand?.command == [0x51, 0x00])
        #expect(family.battery?.command == [0xD2])
    }

    @Test func colorIsNotPersistedOnDeviceButOtherSettingsAre() throws {
        let catalog = try ProfileCatalog.load()
        let family = try #require(catalog.families.first { $0.id == "prime_wireless_wired" })
        #expect(family.setting("color")?.persistsOnDevice == false)
        #expect(family.setting("polling_rate")?.persistsOnDevice == true)
    }

    @Test func layoutsResolveAliasesAndLowercase() throws {
        let layouts = try ButtonLayouts.load()
        #expect(layouts.multimedia["playpause"] == 0xCD)
        #expect(layouts.multimedia["vol+"] == 0xE9)
        #expect(layouts.keyboard["a"] == 0x04)
        #expect(layouts.multimediaKeys.contains("PlayPause"))
    }
}
```

`Tests/MouseCoreTests/ValuesTests.swift`:
```swift
import Foundation
import Testing
@testable import MouseCore

@Suite struct ValuesTests {
    @Test func littleEndianBytes() throws {
        #expect(try Bytes.littleEndian(0x0493E0, length: 3) == [0xE0, 0x93, 0x04])
        #expect(try Bytes.littleEndian(0, length: 1) == [0])
        #expect(try Bytes.littleEndian(255, length: 1) == [255])
    }

    @Test func littleEndianOverflowThrows() {
        #expect(throws: MouseCoreError.overflow) { try Bytes.littleEndian(256, length: 1) }
        #expect(throws: MouseCoreError.overflow) { try Bytes.littleEndian(-1, length: 1) }
    }

    @Test(arguments: [
        ("ff8000", RGBColor(r: 255, g: 128, b: 0)),
        ("#ff8000", RGBColor(r: 255, g: 128, b: 0)),
        ("#f80", RGBColor(r: 255, g: 136, b: 0)),
        ("f80", RGBColor(r: 255, g: 136, b: 0)),
        ("red", RGBColor(r: 255, g: 0, b: 0)),
        ("RED", RGBColor(r: 255, g: 0, b: 0)),
        ("navy", RGBColor(r: 0, g: 0, b: 128)),
    ])
    func parsesColors(text: String, expected: RGBColor) {
        #expect(RGBColor(parsing: text) == expected)
    }

    @Test(arguments: ["", "ggg", "#12345", "+f0", "ff80001", "notacolor"])
    func rejectsBadColors(text: String) {
        #expect(RGBColor(parsing: text) == nil)
    }

    @Test func hexStringRoundTrips() {
        #expect(RGBColor(r: 255, g: 128, b: 0).hexString == "ff8000")
    }

    @Test func buttonMappingLowercasesKeysAndValues() {
        let mapping = ButtonMapping(assignments: ["Button1": "Button2", "ScrollUp": "VolumeUp"])
        #expect(mapping.assignments == ["button1": "button2", "scrollup": "volumeup"])
    }

    @Test(arguments: [
        SettingValue.int(5),
        .choice("1000"),
        .dpiPresets(presets: [400, 800], selected: 1),
        .dpiPresets(presets: [400], selected: nil),
        .color(RGBColor(r: 1, g: 2, b: 3)),
        .buttons(ButtonMapping(assignments: ["button1": "button2"])),
    ])
    func settingValueRoundTripsThroughJSON(value: SettingValue) throws {
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(SettingValue.self, from: data) == value)
    }

    @Test func settingValueDecodesTheGeneratorFormat() throws {
        let json = #"{"type":"dpi","presets":[400,800],"selected":null}"#
        #expect(try JSONDecoder().decode(SettingValue.self, from: Data(json.utf8))
                == .dpiPresets(presets: [400, 800], selected: nil))
    }

    @Test func unknownSettingValueTypeFailsToDecode() {
        let json = #"{"type":"nope"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SettingValue.self, from: Data(json.utf8))
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "ProfileCatalogTests|ValuesTests"`
Expected: compile FAIL (`cannot find 'ProfileCatalog' in scope`, `cannot find 'Bytes'`, `cannot find 'SettingEncoder'`).

`SettingEncoder` is referenced by `assertGolden` in the support file, so add a one-line stub first so this task's tests can compile: create `Sources/MouseCore/SettingEncoder.swift` with
```swift
public struct SettingEncoder: Sendable {
    public let layouts: ButtonLayouts
    public init(layouts: ButtonLayouts) { self.layouts = layouts }
    public func encode(_ spec: SettingSpec, value: SettingValue) throws -> [UInt8] {
        throw MouseCoreError.unsupportedValueType(spec.valueType)
    }
}
```
(Task 3 replaces this file body.)

- [ ] **Step 3: Write `Sources/MouseCore/Values.swift`**

```swift
import Foundation

public enum MouseCoreError: Error, Equatable, Sendable {
    case overflow
    case unknownSetting(String)
    case unsupportedValueType(String)
    case valueMismatch(setting: String, expected: String)
    case invalidValue(String)
    case noPrimaryClick
}

enum Bytes {
    /// `value` as `length` little-endian bytes. Mirrors rivalcfg `uint_to_little_endian_bytearray`.
    static func littleEndian(_ value: Int, length: Int) throws -> [UInt8] {
        guard value >= 0, length >= 1, length <= 8 else { throw MouseCoreError.overflow }
        if length < 8, value > (1 << (8 * length)) - 1 { throw MouseCoreError.overflow }
        return (0..<length).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }

    static func u8(_ ints: [Int]) -> [UInt8] {
        ints.map { UInt8(truncatingIfNeeded: $0) }
    }
}

public struct RGBColor: Equatable, Sendable, Codable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    static let named: [String: RGBColor] = [
        "white": RGBColor(r: 0xFF, g: 0xFF, b: 0xFF),
        "silver": RGBColor(r: 0xC0, g: 0xC0, b: 0xC0),
        "gray": RGBColor(r: 0x80, g: 0x80, b: 0x80),
        "black": RGBColor(r: 0x00, g: 0x00, b: 0x00),
        "red": RGBColor(r: 0xFF, g: 0x00, b: 0x00),
        "maroon": RGBColor(r: 0x80, g: 0x00, b: 0x00),
        "yellow": RGBColor(r: 0xFF, g: 0xFF, b: 0x00),
        "olive": RGBColor(r: 0x80, g: 0x80, b: 0x00),
        "lime": RGBColor(r: 0x00, g: 0xFF, b: 0x00),
        "green": RGBColor(r: 0x00, g: 0x80, b: 0x00),
        "aqua": RGBColor(r: 0x00, g: 0xFF, b: 0xFF),
        "teal": RGBColor(r: 0x00, g: 0x80, b: 0x80),
        "blue": RGBColor(r: 0x00, g: 0x00, b: 0xFF),
        "navy": RGBColor(r: 0x00, g: 0x00, b: 0x80),
        "fuchsia": RGBColor(r: 0xFF, g: 0x00, b: 0xFF),
        "purple": RGBColor(r: 0x80, g: 0x00, b: 0x80),
    ]

    /// Accepts rivalcfg color strings: a named color, `rgb`, `#rgb`, `rrggbb`, `#rrggbb`.
    public init?(parsing text: String) {
        let lower = text.lowercased()
        if let color = Self.named[lower] {
            self = color
            return
        }
        var digits = lower.hasPrefix("#") ? String(lower.dropFirst()) : lower
        guard digits.count == 3 || digits.count == 6,
              digits.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) })
        else { return nil }
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard let value = UInt32(digits, radix: 16) else { return nil }
        self.init(r: UInt8((value >> 16) & 0xFF), g: UInt8((value >> 8) & 0xFF), b: UInt8(value & 0xFF))
    }

    public var hexString: String {
        String(format: "%02x%02x%02x", r, g, b)
    }
}

public struct ButtonMapping: Equatable, Sendable, Codable {
    /// Lowercased button name -> lowercased action token. `"default"` means the factory action.
    public var assignments: [String: String]

    public init(assignments: [String: String] = [:]) {
        self.assignments = Dictionary(
            assignments.map { ($0.key.lowercased(), $0.value.lowercased()) },
            uniquingKeysWith: { _, latest in latest }
        )
    }
}

public enum SettingValue: Equatable, Sendable, Codable {
    case int(Int)
    case choice(String)
    case dpiPresets(presets: [Int], selected: Int?)
    case color(RGBColor)
    case buttons(ButtonMapping)

    private enum CodingKeys: String, CodingKey {
        case type, value, presets, selected, r, g, b, assignments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "int":
            self = .int(try c.decode(Int.self, forKey: .value))
        case "choice":
            self = .choice(try c.decode(String.self, forKey: .value))
        case "dpi":
            self = .dpiPresets(
                presets: try c.decode([Int].self, forKey: .presets),
                selected: try c.decodeIfPresent(Int.self, forKey: .selected)
            )
        case "color":
            self = .color(RGBColor(
                r: try c.decode(UInt8.self, forKey: .r),
                g: try c.decode(UInt8.self, forKey: .g),
                b: try c.decode(UInt8.self, forKey: .b)
            ))
        case "buttons":
            self = .buttons(ButtonMapping(assignments: try c.decode([String: String].self, forKey: .assignments)))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "unknown setting value type"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .int(let v):
            try c.encode("int", forKey: .type)
            try c.encode(v, forKey: .value)
        case .choice(let v):
            try c.encode("choice", forKey: .type)
            try c.encode(v, forKey: .value)
        case .dpiPresets(let presets, let selected):
            try c.encode("dpi", forKey: .type)
            try c.encode(presets, forKey: .presets)
            try c.encode(selected, forKey: .selected)
        case .color(let color):
            try c.encode("color", forKey: .type)
            try c.encode(color.r, forKey: .r)
            try c.encode(color.g, forKey: .g)
            try c.encode(color.b, forKey: .b)
        case .buttons(let mapping):
            try c.encode("buttons", forKey: .type)
            try c.encode(mapping.assignments, forKey: .assignments)
        }
    }
}
```

- [ ] **Step 4: Write `Sources/MouseCore/Profiles.swift`**

```swift
import Foundation

public struct ChoiceEntry: Codable, Sendable, Equatable {
    public var key: String
    public var value: Int
}

public struct ButtonSpec: Codable, Sendable, Equatable {
    public var name: String
    public var id: Int
    public var offset: Int
    public var defaultAction: String
}

public struct SettingSpec: Codable, Sendable, Identifiable, Equatable {
    public var id: String { key }
    public var key: String
    public var label: String
    public var description: String
    public var command: [Int]
    public var commandSuffix: [Int]
    public var valueType: String
    public var defaultText: String
    public var readbackLength: Int
    public var packetLength: Int
    public var persistsOnDevice: Bool
    // range / multidpi_range_choice
    public var inputRange: [Int]?
    public var outputRange: [Int]?
    public var rangeLengthByte: Int?
    public var dpiLengthByte: Int?
    public var firstPreset: Int?
    public var maxPresetCount: Int?
    public var outputChoices: [[Int]]?
    // choice
    public var choices: [ChoiceEntry]?
    // buttons
    public var buttons: [ButtonSpec]?
    public var buttonFieldLength: Int?
    public var buttonDisable: Int?
    public var buttonKeyboard: Int?
    public var buttonMultimedia: Int?
    public var buttonDpiSwitch: Int?
    public var buttonScrollUp: Int?
    public var buttonScrollDown: Int?
}

public struct CommandSpec: Codable, Sendable, Equatable {
    public var command: [Int]
    public var readbackLength: Int
}

public struct BatterySpec: Codable, Sendable, Equatable {
    public var command: [Int]
    public var responseLength: Int
    public var readbackLength: Int
    public var decoder: String
}

public struct DeviceModel: Codable, Sendable, Equatable {
    public var name: String
    /// Physical mouse id; the cable and the dongle of one mouse share saved settings.
    public var mouse: String
    public var vendorId: Int
    public var productId: Int
    public var endpoint: Int
    public var isWireless: Bool
}

public struct DeviceFamily: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var models: [DeviceModel]
    public var settings: [SettingSpec]
    public var battery: BatterySpec?
    public var saveCommand: CommandSpec?

    public func setting(_ key: String) -> SettingSpec? {
        settings.first { $0.key == key }
    }
}

public struct MatchedProfile: Sendable {
    public let family: DeviceFamily
    public let model: DeviceModel
}

public struct ProfileCatalog: Codable, Sendable {
    public var rivalcfgVersion: String
    public var families: [DeviceFamily]

    public static func load() throws -> ProfileCatalog {
        try JSONDecoder().decode(ProfileCatalog.self, from: Data(GeneratedData.profilesJSON.utf8))
    }

    public func match(vendorID: Int, productID: Int) -> MatchedProfile? {
        for family in families {
            if let model = family.models.first(where: { $0.vendorId == vendorID && $0.productId == productID }) {
                return MatchedProfile(family: family, model: model)
            }
        }
        return nil
    }
}

public struct ButtonLayouts: Codable, Sendable {
    /// Lowercased key name (aliases included) -> USB HID usage code.
    public var keyboard: [String: Int]
    /// Lowercased media key name (aliases included) -> code.
    public var multimedia: [String: Int]
    /// Canonical display names in rivalcfg order, for pickers.
    public var keyboardKeys: [String]
    public var multimediaKeys: [String]

    public static func load() throws -> ButtonLayouts {
        try JSONDecoder().decode(ButtonLayouts.self, from: Data(GeneratedData.layoutsJSON.utf8))
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter "ProfileCatalogTests|ValuesTests"`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat(core): value types, profile catalog and golden test support" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Setting encoder — choice, range, rgbcolor

**Files:**
- Modify: `Sources/MouseCore/SettingEncoder.swift` (replace the Task 2 stub)
- Test: `Tests/MouseCoreTests/EncoderBasicTests.swift`

**Interfaces:**
- Consumes: `SettingSpec`, `SettingValue`, `ButtonLayouts`, `Bytes`, `MouseCoreError` (Task 2), `assertGolden`, `spec(_:_:)`, `hex(_:)` (Task 2 support)
- Produces: `SettingEncoder.encode(_ spec: SettingSpec, value: SettingValue) throws -> [UInt8]` returning the HID payload **without** the report id (for example `[0x2B, 0x01]`); `SettingEncoder.nearestInRange(start:stop:step:value:) -> Int` (internal static). `dpiBytes` and `buttonBytes` are added by Tasks 4 and 5 and are declared here as private methods that throw `unsupportedValueType` until then.

- [ ] **Step 1: Write the failing tests**

`Tests/MouseCoreTests/EncoderBasicTests.swift`:
```swift
import Testing
@testable import MouseCore

@Suite struct EncoderBasicTests {
    let encoder = SettingEncoder(layouts: ButtonLayouts(keyboard: [:], multimedia: [:], keyboardKeys: [], multimediaKeys: []))

    @Test(arguments: primeFamilyIDs)
    func choiceRangeAndColorMatchRivalcfg(familyID: String) throws {
        try assertGolden(
            familyID: familyID,
            keys: ["polling_rate", "default_lighting", "sleep_timer", "dim_timer", "color"]
        )
    }

    @Test func pollingRateWiredBytes() throws {
        let s = try spec("prime_wireless_wired", "polling_rate")
        #expect(try encoder.encode(s, value: .choice("500")) == [0x2B, 0x01])
    }

    @Test func unknownChoiceThrowsAndNamesTheValidOnes() throws {
        let s = try spec("prime_wireless_wired", "polling_rate")
        #expect(throws: MouseCoreError.self) { try encoder.encode(s, value: .choice("333")) }
    }

    @Test func rangeClampsAboveAndBelow() throws {
        let s = try spec("prime_wireless_wired", "sleep_timer")
        let max = try encoder.encode(s, value: .int(20))
        #expect(try encoder.encode(s, value: .int(25)) == max)
        let zero = try encoder.encode(s, value: .int(0))
        #expect(try encoder.encode(s, value: .int(-3)) == zero)
    }

    @Test func rangeSleepTimerFiveMinutesIsThreeHundredThousandMillis() throws {
        let s = try spec("prime_wireless_wired", "sleep_timer")
        #expect(try encoder.encode(s, value: .int(5)) == [0x29, 0xE0, 0x93, 0x04])
    }

    @Test func nearestInRangeRoundsToNearestStep() {
        #expect(SettingEncoder.nearestInRange(start: 0, stop: 1000, step: 100, value: 110) == 100)
        #expect(SettingEncoder.nearestInRange(start: 0, stop: 1000, step: 100, value: 190) == 200)
        #expect(SettingEncoder.nearestInRange(start: 42, stop: 1000, step: 100, value: 150) == 142)
    }

    @Test func wrongValueKindForSettingThrowsMismatch() throws {
        let s = try spec("prime_wireless_wired", "polling_rate")
        #expect(throws: MouseCoreError.valueMismatch(setting: "polling_rate", expected: "choice")) {
            try encoder.encode(s, value: .int(500))
        }
    }

    @Test func colorPayloadIsCommandThenRGB() throws {
        let s = try spec("prime_wireless_wired", "color")
        #expect(try encoder.encode(s, value: .color(RGBColor(r: 1, g: 2, b: 3))) == [0x21, 0x01, 0x00, 1, 2, 3])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EncoderBasicTests`
Expected: FAIL (`unsupportedValueType` thrown by the stub, or `nearestInRange` missing).

- [ ] **Step 3: Replace `Sources/MouseCore/SettingEncoder.swift`**

```swift
import Foundation

/// Port of rivalcfg's value-type handlers. Pure functions: no I/O, no state.
public struct SettingEncoder: Sendable {
    public let layouts: ButtonLayouts

    public init(layouts: ButtonLayouts) {
        self.layouts = layouts
    }

    /// The HID payload for one setting, without the report id (rivalcfg writes `[0x00] + payload`).
    public func encode(_ spec: SettingSpec, value: SettingValue) throws -> [UInt8] {
        let data: [UInt8]
        switch (spec.valueType, value) {
        case ("choice", .choice(let key)):
            data = [try choiceByte(spec, key)]
        case ("range", .int(let v)):
            data = try rangeBytes(spec, v)
        case ("rgbcolor", .color(let c)):
            data = [c.r, c.g, c.b]
        case ("multidpi_range_choice", .dpiPresets(let presets, let selected)):
            data = try dpiBytes(spec, presets: presets, selected: selected)
        case ("buttons", .buttons(let mapping)):
            data = try buttonBytes(spec, mapping)
        case ("choice", _), ("range", _), ("rgbcolor", _), ("multidpi_range_choice", _), ("buttons", _):
            throw MouseCoreError.valueMismatch(setting: spec.key, expected: spec.valueType)
        default:
            throw MouseCoreError.unsupportedValueType(spec.valueType)
        }
        var packet = Bytes.u8(spec.command) + data + Bytes.u8(spec.commandSuffix)
        if spec.packetLength > packet.count {
            packet += [UInt8](repeating: 0, count: spec.packetLength - packet.count)
        }
        return packet
    }

    // MARK: choice

    private func choiceByte(_ spec: SettingSpec, _ key: String) throws -> UInt8 {
        guard let entry = spec.choices?.first(where: { $0.key == key }) else {
            let valid = (spec.choices ?? []).map(\.key).joined(separator: ", ")
            throw MouseCoreError.invalidValue("\(spec.key): '\(key)' must be one of [\(valid)]")
        }
        return UInt8(truncatingIfNeeded: entry.value)
    }

    // MARK: range

    /// rivalcfg `matches_value_in_range`: clamp, then round to the nearest step.
    static func nearestInRange(start: Int, stop: Int, step: Int, value: Int) -> Int {
        if value <= start { return start }
        if value >= stop { return stop }
        let delta = (value - start) % step
        if delta == 0 { return value }
        return Double(delta) < Double(step) / 2 ? value - delta : value - delta + step
    }

    private func rangeBytes(_ spec: SettingSpec, _ value: Int) throws -> [UInt8] {
        guard let input = spec.inputRange, input.count == 3, input[2] > 0,
              let output = spec.outputRange, output.count == 3, output[2] > 0
        else { throw MouseCoreError.invalidValue("\(spec.key): profile has no valid range") }
        let inputCount = (input[1] - input[0]) / input[2] + 1
        let outputCount = (output[1] - output[0]) / output[2] + 1
        guard inputCount == outputCount else {
            throw MouseCoreError.invalidValue("\(spec.key): input and output ranges differ in length")
        }
        let matched = Self.nearestInRange(start: input[0], stop: input[1], step: input[2], value: value)
        let index = (matched - input[0]) / input[2]
        return try Bytes.littleEndian(output[0] + index * output[2], length: spec.rangeLengthByte ?? 1)
    }

    // MARK: Added by Tasks 4 and 5

    private func dpiBytes(_ spec: SettingSpec, presets: [Int], selected: Int?) throws -> [UInt8] {
        throw MouseCoreError.unsupportedValueType(spec.valueType)
    }

    private func buttonBytes(_ spec: SettingSpec, _ mapping: ButtonMapping) throws -> [UInt8] {
        throw MouseCoreError.unsupportedValueType(spec.valueType)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter EncoderBasicTests`
Expected: all PASS, including both families' golden cases.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat(core): encode choice, range and rgbcolor settings" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Setting encoder — DPI presets

**Files:**
- Modify: `Sources/MouseCore/SettingEncoder.swift` (replace the `dpiBytes` stub)
- Test: `Tests/MouseCoreTests/EncoderDPITests.swift`

**Interfaces:**
- Consumes: `SettingEncoder`, `SettingSpec.outputChoices/firstPreset/maxPresetCount/dpiLengthByte`, `Bytes.littleEndian`
- Produces: `.dpiPresets(presets:selected:)` support in `encode`. Payload layout: `command + [presetCount, selectedPreset] + one little-endian code per preset`.

- [ ] **Step 1: Write the failing tests**

`Tests/MouseCoreTests/EncoderDPITests.swift`:
```swift
import Testing
@testable import MouseCore

@Suite struct EncoderDPITests {
    let encoder = SettingEncoder(layouts: ButtonLayouts(keyboard: [:], multimedia: [:], keyboardKeys: [], multimediaKeys: []))

    @Test(arguments: primeFamilyIDs)
    func dpiMatchesRivalcfg(familyID: String) throws {
        try assertGolden(familyID: familyID, keys: ["sensitivity"])
    }

    @Test func defaultFivePresetsWired() throws {
        let s = try spec("prime_wireless_wired", "sensitivity")
        let out = try encoder.encode(s, value: .dpiPresets(presets: [400, 800, 1200, 2400, 3200], selected: nil))
        #expect(out == [0x2D, 0x05, 0x00, 0x04, 0x09, 0x0D, 0x1B, 0x26])
    }

    @Test func selectedPresetIsEncodedAsSecondByte() throws {
        let s = try spec("prime_wireless_wired", "sensitivity")
        let out = try encoder.encode(s, value: .dpiPresets(presets: [400, 800, 1200], selected: 2))
        #expect(out[1] == 3)
        #expect(out[2] == 2)
    }

    @Test func emptyPresetListThrowsAndWritesNothing() throws {
        let s = try spec("prime_wireless_wired", "sensitivity")
        #expect(throws: MouseCoreError.self) {
            try encoder.encode(s, value: .dpiPresets(presets: [], selected: nil))
        }
    }

    @Test func sixPresetsThrowBecauseTheMouseHoldsFive() throws {
        let s = try spec("prime_wireless_wired", "sensitivity")
        #expect(throws: MouseCoreError.self) {
            try encoder.encode(s, value: .dpiPresets(presets: [400, 800, 1200, 1600, 2000, 2400], selected: nil))
        }
    }

    @Test func selectedPresetBeyondTheListThrows() throws {
        let s = try spec("prime_wireless_wired", "sensitivity")
        #expect(throws: MouseCoreError.self) {
            try encoder.encode(s, value: .dpiPresets(presets: [400, 800], selected: 2))
        }
        #expect(throws: MouseCoreError.self) {
            try encoder.encode(s, value: .dpiPresets(presets: [400, 800], selected: -1))
        }
    }

    @Test func outOfRangeDpiClampsToNearestSupportedValue() throws {
        let s = try spec("prime_wireless_wired", "sensitivity")
        let clamped = try encoder.encode(s, value: .dpiPresets(presets: [50, 20000], selected: nil))
        let exact = try encoder.encode(s, value: .dpiPresets(presets: [100, 18000], selected: nil))
        #expect(clamped == exact)
    }

    @Test func tieBetweenTwoSupportedValuesPicksTheLowerOne() throws {
        let s = try spec("prime_wireless_wired", "sensitivity")
        let tie = try encoder.encode(s, value: .dpiPresets(presets: [150], selected: nil))
        let low = try encoder.encode(s, value: .dpiPresets(presets: [100], selected: nil))
        #expect(tie == low)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EncoderDPITests`
Expected: FAIL (`unsupportedValueType("multidpi_range_choice")`).

- [ ] **Step 3: Replace the `dpiBytes` stub in `SettingEncoder.swift`**

```swift
    // MARK: multidpi_range_choice

    private func dpiBytes(_ spec: SettingSpec, presets: [Int], selected: Int?) throws -> [UInt8] {
        guard let table = spec.outputChoices, let first = spec.firstPreset,
              let maxCount = spec.maxPresetCount, let codeLength = spec.dpiLengthByte
        else { throw MouseCoreError.invalidValue("\(spec.key): profile is missing DPI parameters") }
        guard !presets.isEmpty else {
            throw MouseCoreError.invalidValue("you must provide at least one preset")
        }
        guard presets.count <= maxCount else {
            throw MouseCoreError.invalidValue(
                "you provided \(presets.count) presets but the device accepts a maximum of \(maxCount)"
            )
        }
        let selectedPreset = first + (selected ?? 0)
        guard selectedPreset >= first, selectedPreset < presets.count + first else {
            throw MouseCoreError.invalidValue("the selected preset is out of range")
        }
        let sorted = table.compactMap { $0.count == 2 ? (dpi: $0[0], code: $0[1]) : nil }.sorted { $0.dpi < $1.dpi }
        guard !sorted.isEmpty else { throw MouseCoreError.invalidValue("\(spec.key): empty DPI table") }

        var out: [UInt8] = [UInt8(truncatingIfNeeded: presets.count), UInt8(truncatingIfNeeded: selectedPreset)]
        for dpi in presets {
            // rivalcfg find_nearest_choice: ascending scan, strict '<', so ties pick the lower DPI.
            var best = sorted[0]
            for entry in sorted where abs(entry.dpi - dpi) < abs(best.dpi - dpi) {
                best = entry
            }
            out += try Bytes.littleEndian(best.code, length: codeLength)
        }
        return out
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter EncoderDPITests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat(core): encode DPI preset lists with rivalcfg rounding" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Setting encoder — button mapping and click validation

**Files:**
- Modify: `Sources/MouseCore/SettingEncoder.swift` (replace the `buttonBytes` stub, add `validateButtons`)
- Test: `Tests/MouseCoreTests/EncoderButtonsTests.swift`

**Interfaces:**
- Consumes: `ButtonMapping`, `ButtonLayouts`, `SettingSpec.buttons/buttonFieldLength/button*`
- Produces: `.buttons(ButtonMapping)` support in `encode`; `SettingEncoder.validateButtons(_ mapping: ButtonMapping, spec: SettingSpec) throws` (throws `MouseCoreError.noPrimaryClick` when no physical button resolves to the first button, `button1`, and `invalidValue` for unknown buttons or actions); `SettingEncoder.resolvedActions(spec:mapping:) throws -> [(button: ButtonSpec, action: String)]` (internal).

- [ ] **Step 1: Write the failing tests**

`Tests/MouseCoreTests/EncoderButtonsTests.swift`:
```swift
import Testing
@testable import MouseCore

@Suite struct EncoderButtonsTests {
    let encoder: SettingEncoder

    init() throws {
        encoder = SettingEncoder(layouts: try ButtonLayouts.load())
    }

    @Test(arguments: primeFamilyIDs)
    func buttonsMatchRivalcfg(familyID: String) throws {
        try assertGolden(familyID: familyID, keys: ["buttons_mapping"])
    }

    @Test func defaultMappingIsFortyBytes() throws {
        let s = try spec("prime_wireless_wired", "buttons_mapping")
        let out = try encoder.encode(s, value: .buttons(ButtonMapping()))
        #expect(out.count == 1 + 40)
        #expect(out[0] == 0x2A)
        #expect(Array(out[1...5]) == [0x01, 0, 0, 0, 0])          // button1 -> button1
        #expect(Array(out[26...30]) == [0x30, 0, 0, 0, 0])        // button6 -> dpi
    }

    @Test func mediaKeyUsesMultimediaPrefixAndCode() throws {
        let s = try spec("prime_wireless_wired", "buttons_mapping")
        let out = try encoder.encode(s, value: .buttons(ButtonMapping(assignments: ["button4": "PlayPause"])))
        #expect(Array(out[16...17]) == [0x61, 0xCD])
    }

    @Test func keyboardKeyUsesKeyboardPrefixAndCode() throws {
        let s = try spec("prime_wireless_wired", "buttons_mapping")
        let out = try encoder.encode(s, value: .buttons(ButtonMapping(assignments: ["button3": "a"])))
        #expect(Array(out[11...12]) == [0x51, 0x04])
    }

    @Test func aliasesResolve() throws {
        let s = try spec("prime_wireless_wired", "buttons_mapping")
        let alias = try encoder.encode(s, value: .buttons(ButtonMapping(assignments: ["button4": "vol+"])))
        let canonical = try encoder.encode(s, value: .buttons(ButtonMapping(assignments: ["button4": "VolumeUp"])))
        #expect(alias == canonical)
    }

    @Test func unknownButtonAndUnknownActionThrow() throws {
        let s = try spec("prime_wireless_wired", "buttons_mapping")
        #expect(throws: MouseCoreError.self) {
            try encoder.encode(s, value: .buttons(ButtonMapping(assignments: ["button9": "button1"])))
        }
        #expect(throws: MouseCoreError.self) {
            try encoder.encode(s, value: .buttons(ButtonMapping(assignments: ["button2": "notakey"])))
        }
    }

    @Test func validationAcceptsDefaultAndSwap() throws {
        let s = try spec("prime_wireless_wired", "buttons_mapping")
        try encoder.validateButtons(ButtonMapping(), spec: s)
        try encoder.validateButtons(ButtonMapping(assignments: ["button1": "button2", "button2": "button1"]), spec: s)
    }

    @Test func validationRejectsMappingWithNoLeftClick() throws {
        let s = try spec("prime_wireless_wired", "buttons_mapping")
        #expect(throws: MouseCoreError.noPrimaryClick) {
            try encoder.validateButtons(ButtonMapping(assignments: ["button1": "disabled"]), spec: s)
        }
        #expect(throws: MouseCoreError.noPrimaryClick) {
            try encoder.validateButtons(ButtonMapping(assignments: ["button1": "a"]), spec: s)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EncoderButtonsTests`
Expected: FAIL (`unsupportedValueType("buttons")` and missing `validateButtons`).

- [ ] **Step 3: Replace the `buttonBytes` stub in `SettingEncoder.swift` and add validation**

```swift
    // MARK: buttons

    /// Each physical button with the action it ends up with (lowercased token), in profile order.
    func resolvedActions(spec: SettingSpec, mapping: ButtonMapping) throws -> [(button: ButtonSpec, action: String)] {
        guard let buttons = spec.buttons else {
            throw MouseCoreError.invalidValue("\(spec.key): profile has no buttons")
        }
        let known = Set(buttons.map { $0.name.lowercased() })
        for name in mapping.assignments.keys where !known.contains(name) {
            throw MouseCoreError.invalidValue("This mouse has no button named '\(name)'")
        }
        return buttons.map { button in
            let requested = mapping.assignments[button.name.lowercased()]
            let action = (requested == nil || requested == "default") ? button.defaultAction : requested!
            return (button, action.lowercased())
        }
    }

    private func buttonBytes(_ spec: SettingSpec, _ mapping: ButtonMapping) throws -> [UInt8] {
        guard let buttons = spec.buttons, let fieldLength = spec.buttonFieldLength else {
            throw MouseCoreError.invalidValue("\(spec.key): profile is missing button parameters")
        }
        let byName = Dictionary(buttons.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var specials: [String: Int] = [:]
        if let v = spec.buttonDisable { specials["disable"] = v; specials["disabled"] = v }
        if let v = spec.buttonDpiSwitch { specials["dpi"] = v }
        if let v = spec.buttonScrollUp { specials["scrollup"] = v }
        if let v = spec.buttonScrollDown {
            specials["scrolldown"] = v; specials["scrolldwn"] = v; specials["scrolldn"] = v
        }

        var packet = [UInt8](repeating: 0, count: buttons.count * fieldLength)
        for (button, action) in try resolvedActions(spec: spec, mapping: mapping) {
            let at = button.offset
            guard at + 1 < packet.count else {
                throw MouseCoreError.invalidValue("\(spec.key): button offset out of packet")
            }
            // Same precedence as rivalcfg: mouse button, special action, media key, keyboard key.
            if let target = byName[action] {
                packet[at] = UInt8(truncatingIfNeeded: target.id)
            } else if let code = specials[action] {
                packet[at] = UInt8(truncatingIfNeeded: code)
            } else if let prefix = spec.buttonMultimedia, let code = layouts.multimedia[action] {
                packet[at] = UInt8(truncatingIfNeeded: prefix)
                packet[at + 1] = UInt8(truncatingIfNeeded: code)
            } else if let prefix = spec.buttonKeyboard, let code = layouts.keyboard[action] {
                packet[at] = UInt8(truncatingIfNeeded: prefix)
                packet[at + 1] = UInt8(truncatingIfNeeded: code)
            } else {
                throw MouseCoreError.invalidValue("Unknown button, key or action '\(action)'")
            }
        }
        return packet
    }

    /// Rejects mappings after which no physical button produces the primary click (`button1`).
    /// rivalcfg warns: "keep button1 mapped to a working button, or you won't be able to click".
    public func validateButtons(_ mapping: ButtonMapping, spec: SettingSpec) throws {
        guard let primary = spec.buttons?.first?.name.lowercased() else {
            throw MouseCoreError.invalidValue("\(spec.key): profile has no buttons")
        }
        let actions = try resolvedActions(spec: spec, mapping: mapping)
        guard actions.contains(where: { $0.action == primary }) else {
            throw MouseCoreError.noPrimaryClick
        }
    }
```
Remove the old `buttonBytes` stub; keep everything else.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter EncoderButtonsTests`
Expected: all PASS, including both families' golden button cases.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat(core): encode button mappings and reject mappings without a left click" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Battery decoding

**Files:**
- Create: `Sources/MouseCore/Battery.swift`
- Test: `Tests/MouseCoreTests/BatteryDecoderTests.swift`

**Interfaces:**
- Produces: `struct BatteryReading: Equatable, Sendable { var level: Int; var isCharging: Bool }`; `enum BatteryDecoder { static func decode(decoder: String, reply: [UInt8]) -> BatteryReading? }`. Returns `nil` for any reply that rivalcfg would reject (level outside 0…100, reply too short, unknown decoder).

- [ ] **Step 1: Write the failing tests**

`Tests/MouseCoreTests/BatteryDecoderTests.swift`:
```swift
import Testing
@testable import MouseCore

@Suite struct BatteryDecoderTests {
    @Test func goldenRepliesMatchRivalcfg() throws {
        let golden = try GoldenFile.load()
        for familyID in primeFamilyIDs {
            for row in try #require(golden.families[familyID]).battery {
                let decoded = BatteryDecoder.decode(decoder: "prime_wireless", reply: bytes(fromHex: row.reply))
                if let expected = row.expected {
                    #expect(decoded == BatteryReading(level: expected.level, isCharging: expected.isCharging),
                            "reply \(row.reply)")
                } else {
                    #expect(decoded == nil, "reply \(row.reply) must be unreadable")
                }
            }
        }
    }

    @Test func fullChargingAndEmpty() {
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: [0x00, 0x15]) == BatteryReading(level: 100, isCharging: false))
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: [0x00, 0x95]) == BatteryReading(level: 100, isCharging: true))
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: [0x00, 0x01]) == BatteryReading(level: 0, isCharging: false))
    }

    @Test func garbageIsUnreadableNotNegativeOrOverHundred() {
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: [0x00, 0x00]) == nil)
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: [0x00, 0x16]) == nil)
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: [0x00, 0xFF]) == nil)
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: [0x00]) == nil)
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: []) == nil)
    }

    @Test func unknownDecoderIsUnreadable() {
        #expect(BatteryDecoder.decode(decoder: "nope", reply: [0x00, 0x15]) == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BatteryDecoderTests`
Expected: compile FAIL (`cannot find 'BatteryDecoder'`).

- [ ] **Step 3: Write `Sources/MouseCore/Battery.swift`**

```swift
public struct BatteryReading: Equatable, Sendable, Codable {
    public var level: Int
    public var isCharging: Bool

    public init(level: Int, isCharging: Bool) {
        self.level = level
        self.isCharging = isCharging
    }
}

public enum BatteryDecoder {
    /// Decodes the reply to a battery query. `nil` means "unreadable": the caller must not show 0%.
    public static func decode(decoder: String, reply: [UInt8]) -> BatteryReading? {
        switch decoder {
        case "prime_wireless":
            // rivalcfg: charging = bit 7 of reply[1]; level = ((reply[1] & 0x7F) - 1) * 5
            guard reply.count >= 2 else { return nil }
            let raw = Int(reply[1])
            let level = ((raw & 0x7F) - 1) * 5
            guard (0...100).contains(level) else { return nil }
            return BatteryReading(level: level, isCharging: raw & 0x80 != 0)
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BatteryDecoderTests`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat(core): decode Prime Wireless battery replies" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: HID abstraction, simulated transport and `MouseDevice`

**Files:**
- Create: `Sources/MouseCore/HID.swift`, `Sources/MouseCore/Sleeper.swift`, `Sources/MouseCore/SimulatedHID.swift`, `Sources/MouseCore/MouseDevice.swift`
- Create: `Tests/MouseCoreTests/Support/TestDoubles.swift`
- Test: `Tests/MouseCoreTests/MouseDeviceTests.swift`

**Interfaces:**
- Consumes: `DeviceFamily`, `DeviceModel`, `SettingEncoder`, `SettingValue`, `BatteryDecoder`, `Bytes` (Tasks 2–6)
- Produces:
  - `struct HIDDeviceInfo: Sendable, Hashable { id: UInt64; vendorID: Int; productID: Int; interfaceNumber: Int?; usagePage: Int; usage: Int; product: String? ; public init(...) }`
  - `enum HIDEvent: Sendable { case added(HIDDeviceInfo), removed(UInt64) }`
  - `enum HIDError: Error, Equatable, Sendable { case openFailed(code: Int32), writeFailed(code: Int32), notOpen, simulated(String) }`
  - `protocol HIDConnection: Sendable { func write(_ payload: [UInt8]) async throws; func read(length: Int, timeout: Duration) async throws -> [UInt8]?; func flushInput() async; func close() async }` — `write` payload excludes the report id (report id 0 is implicit).
  - `protocol HIDTransport: Sendable { func events() -> AsyncStream<HIDEvent>; func open(_ device: HIDDeviceInfo) async throws -> any HIDConnection }` — `events()` must emit `.added` for every matching device already present, then live changes.
  - `protocol Sleeper: Sendable { func sleep(for duration: Duration) async }`, `struct SystemSleeper: Sleeper`
  - `actor SimulatedHIDConnection: HIDConnection` (`writes`, `log`, `isClosed`, `enqueueReply(_:)`, `init(replyProvider:failingWrites:)`), `final class SimulatedHIDTransport: HIDTransport` (`plug(_:connection:)`, `unplug(id:)`, `setOpenFails(_:)`)
  - `actor MouseDevice { init(family:model:connection:encoder:sleeper:); func apply(_ key: String, _ value: SettingValue) async throws; func save() async throws; func readBattery() async throws -> BatteryReading?; func close() async; static let commandDelay: Duration; static let replyTimeout: Duration }`
  - Test doubles: `actor RecordingSleeper: Sleeper` (`sleeps: [Duration]`), `actor ManualSleeper: Sleeper` (`waiterCount`, `releaseAll()`), `func waitUntil(_:)`, `func makeDevice(familyID:productID:replyProvider:failingWrites:) throws -> (MouseDevice, SimulatedHIDConnection, RecordingSleeper)`

- [ ] **Step 1: Write the test doubles**

`Tests/MouseCoreTests/Support/TestDoubles.swift`:
```swift
import Foundation
import Testing
@testable import MouseCore

actor RecordingSleeper: Sleeper {
    private(set) var sleeps: [Duration] = []
    func sleep(for duration: Duration) async { sleeps.append(duration) }
}

/// A sleeper that blocks until the test calls `releaseAll()`.
actor ManualSleeper: Sleeper {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var waiterCount: Int { waiters.count }
    func sleep(for duration: Duration) async {
        await withCheckedContinuation { waiters.append($0) }
    }
    func releaseAll() {
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume() }
    }
}

/// Polls `condition` every 5 ms for up to 2 s.
func waitUntil(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<400 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

/// Battery replies a Prime Wireless would send: 64 bytes, level code in byte 1.
func batteryReplyProvider(raw: UInt8) -> SimulatedHIDConnection.ReplyProvider {
    { payload in
        guard let first = payload.first, first == 0x92 || first == 0xD2 else { return nil }
        return [0x00, raw] + [UInt8](repeating: 0, count: 62)
    }
}

func makeDevice(
    familyID: String,
    productID: Int,
    replyProvider: SimulatedHIDConnection.ReplyProvider? = nil,
    failingWrites: Int = 0
) throws -> (MouseDevice, SimulatedHIDConnection, RecordingSleeper) {
    let catalog = try ProfileCatalog.load()
    let match = try #require(catalog.match(vendorID: 0x1038, productID: productID))
    #expect(match.family.id == familyID)
    let connection = SimulatedHIDConnection(replyProvider: replyProvider, failingWrites: failingWrites)
    let sleeper = RecordingSleeper()
    let device = MouseDevice(
        family: match.family,
        model: match.model,
        connection: connection,
        encoder: SettingEncoder(layouts: try ButtonLayouts.load()),
        sleeper: sleeper
    )
    return (device, connection, sleeper)
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/MouseCoreTests/MouseDeviceTests.swift`:
```swift
import Testing
@testable import MouseCore

@Suite struct MouseDeviceTests {
    @Test func wiredWriteIsPacedAndHasNoReadback() async throws {
        let (device, connection, sleeper) = try makeDevice(familyID: "prime_wireless_wired", productID: 0x184A)
        try await device.apply("polling_rate", .choice("500"))
        #expect(await connection.writes == [[0x2B, 0x01]])
        #expect(await connection.log == ["write"])
        #expect(await sleeper.sleeps == [.milliseconds(50)])
    }

    @Test func dongleWriteReadsBackSixtyFourBytes() async throws {
        let (device, connection, _) = try makeDevice(familyID: "prime_wireless_wireless", productID: 0x1848)
        try await device.apply("polling_rate", .choice("500"))
        #expect(await connection.writes == [[0x6B, 0x01]])
        #expect(await connection.log == ["write", "read:64"])
    }

    @Test func aFailedWriteIsRetriedOnceAfterTheDelay() async throws {
        let (device, connection, sleeper) = try makeDevice(
            familyID: "prime_wireless_wired", productID: 0x184A, failingWrites: 1
        )
        try await device.apply("polling_rate", .choice("250"))
        #expect(await connection.writes == [[0x2B, 0x02]])
        #expect(await connection.log == ["write", "write"])
        #expect(await sleeper.sleeps.count == 2)
    }

    @Test func twoFailedWritesThrow() async throws {
        let (device, connection, _) = try makeDevice(
            familyID: "prime_wireless_wired", productID: 0x184A, failingWrites: 2
        )
        await #expect(throws: HIDError.self) {
            try await device.apply("polling_rate", .choice("250"))
        }
        #expect(await connection.writes.isEmpty)
    }

    @Test func invalidValueThrowsBeforeAnythingIsWritten() async throws {
        let (device, connection, _) = try makeDevice(familyID: "prime_wireless_wired", productID: 0x184A)
        await #expect(throws: MouseCoreError.self) {
            try await device.apply("sensitivity", .dpiPresets(presets: [], selected: nil))
        }
        #expect(await connection.log.isEmpty)
    }

    @Test func unknownSettingThrows() async throws {
        let (device, _, _) = try makeDevice(familyID: "prime_wireless_wired", productID: 0x184A)
        await #expect(throws: MouseCoreError.unknownSetting("nope")) {
            try await device.apply("nope", .int(1))
        }
    }

    @Test func saveUsesTheFamilySaveCommand() async throws {
        let (wired, wiredConn, _) = try makeDevice(familyID: "prime_wireless_wired", productID: 0x184A)
        try await wired.save()
        #expect(await wiredConn.writes == [[0x11, 0x00]])

        let (dongle, dongleConn, _) = try makeDevice(familyID: "prime_wireless_wireless", productID: 0x1848)
        try await dongle.save()
        #expect(await dongleConn.writes == [[0x51, 0x00]])
        #expect(await dongleConn.log == ["write", "read:64"])
    }

    @Test func batteryFlushesStaleInputThenQueriesThenDecodes() async throws {
        let (device, connection, _) = try makeDevice(
            familyID: "prime_wireless_wireless", productID: 0x1848,
            replyProvider: batteryReplyProvider(raw: 0x95)
        )
        await connection.enqueueReply([0x00, 0x0B])                 // stale report from before the query
        let reading = try await device.readBattery()
        #expect(reading == BatteryReading(level: 100, isCharging: true))
        #expect(await connection.writes == [[0xD2]])
        #expect(await connection.log == ["flush", "write", "read:2"])
    }

    @Test func batteryWiredUsesTheWiredQueryByte() async throws {
        let (device, connection, _) = try makeDevice(
            familyID: "prime_wireless_wired", productID: 0x184A,
            replyProvider: batteryReplyProvider(raw: 0x0B)
        )
        #expect(try await device.readBattery() == BatteryReading(level: 50, isCharging: false))
        #expect(await connection.writes == [[0x92]])
    }

    @Test func batteryIsNilWhenTheMouseDoesNotAnswer() async throws {
        let (device, _, _) = try makeDevice(familyID: "prime_wireless_wireless", productID: 0x1848)
        #expect(try await device.readBattery() == nil)
    }

    @Test func batteryIsNilForGarbageReply() async throws {
        let (device, _, _) = try makeDevice(
            familyID: "prime_wireless_wireless", productID: 0x1848,
            replyProvider: batteryReplyProvider(raw: 0x00)
        )
        #expect(try await device.readBattery() == nil)
    }

    @Test func closeClosesTheConnection() async throws {
        let (device, connection, _) = try makeDevice(familyID: "prime_wireless_wired", productID: 0x184A)
        await device.close()
        #expect(await connection.isClosed)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter MouseDeviceTests`
Expected: compile FAIL (`cannot find 'MouseDevice'`, `'Sleeper'`, `'SimulatedHIDConnection'`).

- [ ] **Step 4: Write `Sources/MouseCore/HID.swift`**

```swift
public struct HIDDeviceInfo: Sendable, Hashable {
    /// IORegistry entry id on macOS; unique per HID interface while it is plugged in.
    public var id: UInt64
    public var vendorID: Int
    public var productID: Int
    public var interfaceNumber: Int?
    public var usagePage: Int
    public var usage: Int
    public var product: String?

    public init(
        id: UInt64, vendorID: Int, productID: Int, interfaceNumber: Int?,
        usagePage: Int = 0, usage: Int = 0, product: String? = nil
    ) {
        self.id = id
        self.vendorID = vendorID
        self.productID = productID
        self.interfaceNumber = interfaceNumber
        self.usagePage = usagePage
        self.usage = usage
        self.product = product
    }
}

public enum HIDEvent: Sendable {
    case added(HIDDeviceInfo)
    case removed(UInt64)
}

public enum HIDError: Error, Equatable, Sendable {
    case openFailed(code: Int32)
    case writeFailed(code: Int32)
    case notOpen
    case simulated(String)
}

public protocol HIDConnection: Sendable {
    /// Sends one output report. The payload excludes the report id (report id 0 is implicit).
    func write(_ payload: [UInt8]) async throws
    /// Waits for one input report; `nil` on timeout. The report is truncated to `length`.
    func read(length: Int, timeout: Duration) async throws -> [UInt8]?
    /// Drops queued input reports so the next read sees only fresh data.
    func flushInput() async
    func close() async
}

public protocol HIDTransport: Sendable {
    /// Emits `.added` for every matching device already present, then live changes.
    func events() -> AsyncStream<HIDEvent>
    func open(_ device: HIDDeviceInfo) async throws -> any HIDConnection
}
```

- [ ] **Step 5: Write `Sources/MouseCore/Sleeper.swift`**

```swift
public protocol Sleeper: Sendable {
    func sleep(for duration: Duration) async
}

public struct SystemSleeper: Sleeper {
    public init() {}
    /// Returns early when the surrounding task is cancelled.
    public func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}
```

- [ ] **Step 6: Write `Sources/MouseCore/SimulatedHID.swift`**

```swift
import Foundation
import os

/// In-memory HID connection used by tests and by the app's `--demo` mode.
public actor SimulatedHIDConnection: HIDConnection {
    public typealias ReplyProvider = @Sendable ([UInt8]) -> [UInt8]?

    public private(set) var writes: [[UInt8]] = []
    /// Operation order: "write", "read:<length>", "flush".
    public private(set) var log: [String] = []
    public private(set) var isClosed = false
    private var replies: [[UInt8]] = []
    private var failingWrites: Int
    private let replyProvider: ReplyProvider?

    public init(replyProvider: ReplyProvider? = nil, failingWrites: Int = 0) {
        self.replyProvider = replyProvider
        self.failingWrites = failingWrites
    }

    public func enqueueReply(_ bytes: [UInt8]) {
        replies.append(bytes)
    }

    public func write(_ payload: [UInt8]) async throws {
        log.append("write")
        if failingWrites > 0 {
            failingWrites -= 1
            throw HIDError.simulated("write failed")
        }
        writes.append(payload)
        if let reply = replyProvider?(payload) {
            replies.append(reply)
        }
    }

    public func read(length: Int, timeout: Duration) async throws -> [UInt8]? {
        log.append("read:\(length)")
        guard !replies.isEmpty else { return nil }
        return Array(replies.removeFirst().prefix(length))
    }

    public func flushInput() async {
        log.append("flush")
        replies.removeAll()
    }

    public func close() async {
        isClosed = true
    }
}

public final class SimulatedHIDTransport: HIDTransport, Sendable {
    private let stream: AsyncStream<HIDEvent>
    private let continuation: AsyncStream<HIDEvent>.Continuation
    private let connections = OSAllocatedUnfairLock<[UInt64: SimulatedHIDConnection]>(initialState: [:])
    private let openFails = OSAllocatedUnfairLock<Bool>(initialState: false)

    public init() {
        let made = AsyncStream.makeStream(of: HIDEvent.self)
        stream = made.stream
        continuation = made.continuation
    }

    public func plug(_ info: HIDDeviceInfo, connection: SimulatedHIDConnection) {
        connections.withLock { $0[info.id] = connection }
        continuation.yield(.added(info))
    }

    public func unplug(id: UInt64) {
        _ = connections.withLock { $0.removeValue(forKey: id) }
        continuation.yield(.removed(id))
    }

    public func setOpenFails(_ fails: Bool) {
        openFails.withLock { $0 = fails }
    }

    public func events() -> AsyncStream<HIDEvent> {
        stream
    }

    public func open(_ device: HIDDeviceInfo) async throws -> any HIDConnection {
        if openFails.withLock({ $0 }) {
            throw HIDError.openFailed(code: -536870174)
        }
        guard let connection = connections.withLock({ $0[device.id] }) else {
            throw HIDError.notOpen
        }
        return connection
    }
}
```

- [ ] **Step 7: Write `Sources/MouseCore/MouseDevice.swift`**

```swift
/// One connected mouse. Serializes everything sent to it and keeps the 50 ms spacing rivalcfg uses.
public actor MouseDevice {
    public static let commandDelay: Duration = .milliseconds(50)
    public static let replyTimeout: Duration = .milliseconds(200)

    public let family: DeviceFamily
    public let model: DeviceModel
    private let connection: any HIDConnection
    private let encoder: SettingEncoder
    private let sleeper: any Sleeper

    public init(
        family: DeviceFamily,
        model: DeviceModel,
        connection: any HIDConnection,
        encoder: SettingEncoder,
        sleeper: any Sleeper
    ) {
        self.family = family
        self.model = model
        self.connection = connection
        self.encoder = encoder
        self.sleeper = sleeper
    }

    /// Encodes and sends one setting. Encoding errors are thrown before anything is written.
    public func apply(_ key: String, _ value: SettingValue) async throws {
        guard let spec = family.setting(key) else { throw MouseCoreError.unknownSetting(key) }
        let payload = try encoder.encode(spec, value: value)
        try await send(payload, readback: spec.readbackLength)
    }

    /// Persists the current configuration in the mouse's internal memory.
    public func save() async throws {
        guard let save = family.saveCommand else { return }
        try await send(Bytes.u8(save.command), readback: save.readbackLength)
    }

    /// `nil` means no usable answer (asleep, out of range, garbage); callers must not show 0%.
    public func readBattery() async throws -> BatteryReading? {
        guard let battery = family.battery else { return nil }
        await connection.flushInput()
        try await send(Bytes.u8(battery.command), readback: 0)
        guard let reply = try await connection.read(
            length: max(battery.responseLength, 2), timeout: Self.replyTimeout
        ) else { return nil }
        return BatteryDecoder.decode(decoder: battery.decoder, reply: reply)
    }

    public func close() async {
        await connection.close()
    }

    private func send(_ payload: [UInt8], readback: Int) async throws {
        do {
            try await connection.write(payload)
        } catch {
            await sleeper.sleep(for: Self.commandDelay)
            try await connection.write(payload)
        }
        await sleeper.sleep(for: Self.commandDelay)
        if readback > 0 {
            _ = try? await connection.read(length: readback, timeout: Self.replyTimeout)
        }
    }
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `swift test --filter MouseDeviceTests`
Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources Tests
git commit -m "feat(core): HID abstraction, simulated transport and paced MouseDevice" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: IOKit transport and `hidprobe` — Phase 0 spike (needs the mouse)

**Hardware gate:** Steps 1–3 need no hardware. Steps 4–7 need the Prime Mini Wireless (dongle plugged in and the mouse awake, and later the cable). If the mouse is not available when you reach this task, finish steps 1–3, **skip to Task 9, and come back before starting Task 12** (the app depends on what this spike learns). Do not guess the results.

**Files:**
- Delete: `Sources/MouseHID/Placeholder.swift`
- Create: `Sources/MouseHID/IOHIDTransport.swift`, `Sources/MouseHID/IOHIDConnection.swift`
- Replace: `Sources/hidprobe/main.swift`
- Create: `docs/superpowers/notes/2026-10-10-phase0-spike.md` (written from observed results in Step 7)

**Interfaces:**
- Consumes: `HIDTransport`, `HIDConnection`, `HIDDeviceInfo`, `HIDEvent`, `HIDError` (Task 7); `ProfileCatalog`, `MouseDevice`, `BatteryDecoder` (earlier tasks)
- Produces: `public final class IOHIDTransport: HIDTransport, @unchecked Sendable` with `init(vendorID: Int = 0x1038)`. `hidprobe` subcommands: `list`, `battery`, `dpi <index>`.

- [ ] **Step 1: Write `Sources/MouseHID/IOHIDConnection.swift`**

```swift
import Foundation
import IOKit
import IOKit.hid
import MouseCore

/// One opened HID interface. All mutable state is touched only on `queue`.
final class IOHIDConnection: HIDConnection, @unchecked Sendable {
    private struct Waiter {
        let token: UUID
        let length: Int
        let continuation: CheckedContinuation<[UInt8]?, Never>
    }

    private let device: IOHIDDevice
    private let queue = DispatchQueue(label: "mousebar.hid.connection")
    private var pending: [[UInt8]] = []
    private var waiter: Waiter?
    private let bufferSize: Int
    private let buffer: UnsafeMutablePointer<UInt8>
    private var closed = false

    init(device: IOHIDDevice) {
        self.device = device
        let reported = IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int
        bufferSize = max(reported ?? 64, 64)
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }

    deinit {
        buffer.deallocate()
    }

    func start() {
        let retained = Unmanaged.passRetained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, { context, _, _, _, _, report, length in
            guard let context else { return }
            let connection = Unmanaged<IOHIDConnection>.fromOpaque(context).takeUnretainedValue()
            connection.received(Array(UnsafeBufferPointer(start: report, count: length)))
        }, retained)
        IOHIDDeviceSetDispatchQueue(device, queue)
        IOHIDDeviceSetCancelHandler(device) {
            Unmanaged<IOHIDConnection>.fromOpaque(retained).release()
        }
        IOHIDDeviceActivate(device)
    }

    private func received(_ report: [UInt8]) {
        // Runs on `queue`.
        if let waiter {
            self.waiter = nil
            waiter.continuation.resume(returning: Array(report.prefix(waiter.length)))
        } else {
            pending.append(report)
            if pending.count > 64 { pending.removeFirst() }
        }
    }

    func write(_ payload: [UInt8]) async throws {
        guard !payload.isEmpty else { return }
        let result: IOReturn = await withCheckedContinuation { continuation in
            queue.async {
                guard !self.closed else {
                    continuation.resume(returning: kIOReturnNotOpen)
                    return
                }
                let status = payload.withUnsafeBufferPointer {
                    IOHIDDeviceSetReport(self.device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count)
                }
                continuation.resume(returning: status)
            }
        }
        guard result == kIOReturnSuccess else { throw HIDError.writeFailed(code: result) }
    }

    func read(length: Int, timeout: Duration) async throws -> [UInt8]? {
        let milliseconds = Int(timeout.components.seconds * 1000) + Int(timeout.components.attoseconds / 1_000_000_000_000_000)
        return await withCheckedContinuation { continuation in
            queue.async {
                if !self.pending.isEmpty {
                    continuation.resume(returning: Array(self.pending.removeFirst().prefix(length)))
                    return
                }
                let token = UUID()
                self.waiter = Waiter(token: token, length: length, continuation: continuation)
                self.queue.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                    if let waiter = self.waiter, waiter.token == token {
                        self.waiter = nil
                        waiter.continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    func flushInput() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.pending.removeAll()
                continuation.resume()
            }
        }
    }

    func close() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                guard !self.closed else {
                    continuation.resume()
                    return
                }
                self.closed = true
                if let waiter = self.waiter {
                    self.waiter = nil
                    waiter.continuation.resume(returning: nil)
                }
                IOHIDDeviceCancel(self.device)
                IOHIDDeviceClose(self.device, IOOptionBits(kIOHIDOptionsTypeNone))
                continuation.resume()
            }
        }
    }
}
```

- [ ] **Step 2: Write `Sources/MouseHID/IOHIDTransport.swift`**

```swift
import Foundation
import IOKit
import IOKit.hid
import MouseCore
import os

public final class IOHIDTransport: HIDTransport, @unchecked Sendable {
    private let vendorID: Int
    private let queue = DispatchQueue(label: "mousebar.hid.manager")
    private let devices = OSAllocatedUnfairLock<[UInt64: IOHIDDevice]>(initialState: [:])

    public init(vendorID: Int = 0x1038) {
        self.vendorID = vendorID
    }

    public func events() -> AsyncStream<HIDEvent> {
        AsyncStream { continuation in
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: vendorID] as CFDictionary)
            let context = CallbackContext(transport: self, continuation: continuation)
            let retained = Unmanaged.passRetained(context).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
                guard let ctx else { return }
                Unmanaged<CallbackContext>.fromOpaque(ctx).takeUnretainedValue().deviceAdded(device)
            }, retained)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
                guard let ctx else { return }
                Unmanaged<CallbackContext>.fromOpaque(ctx).takeUnretainedValue().deviceRemoved(device)
            }, retained)
            IOHIDManagerSetDispatchQueue(manager, queue)
            IOHIDManagerSetCancelHandler(manager) {
                Unmanaged<CallbackContext>.fromOpaque(retained).release()
            }
            IOHIDManagerActivate(manager)
            continuation.onTermination = { _ in IOHIDManagerCancel(manager) }
        }
    }

    public func open(_ info: HIDDeviceInfo) async throws -> any HIDConnection {
        guard let device = devices.withLock({ $0[info.id] }) else { throw HIDError.notOpen }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw HIDError.openFailed(code: result) }
        let connection = IOHIDConnection(device: device)
        connection.start()
        return connection
    }

    fileprivate func remember(_ device: IOHIDDevice, id: UInt64) {
        devices.withLock { $0[id] = device }
    }

    fileprivate func forget(id: UInt64) {
        _ = devices.withLock { $0.removeValue(forKey: id) }
    }
}

private final class CallbackContext: @unchecked Sendable {
    let transport: IOHIDTransport
    let continuation: AsyncStream<HIDEvent>.Continuation

    init(transport: IOHIDTransport, continuation: AsyncStream<HIDEvent>.Continuation) {
        self.transport = transport
        self.continuation = continuation
    }

    func deviceAdded(_ device: IOHIDDevice) {
        guard let id = registryID(device) else { return }
        transport.remember(device, id: id)
        continuation.yield(.added(HIDDeviceInfo(
            id: id,
            vendorID: intProperty(device, kIOHIDVendorIDKey) ?? 0,
            productID: intProperty(device, kIOHIDProductIDKey) ?? 0,
            interfaceNumber: interfaceNumber(device),
            usagePage: intProperty(device, kIOHIDPrimaryUsagePageKey) ?? 0,
            usage: intProperty(device, kIOHIDPrimaryUsageKey) ?? 0,
            product: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
        )))
    }

    func deviceRemoved(_ device: IOHIDDevice) {
        guard let id = registryID(device) else { return }
        transport.forget(id: id)
        continuation.yield(.removed(id))
    }
}

private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
    IOHIDDeviceGetProperty(device, key as CFString) as? Int
}

private func registryID(_ device: IOHIDDevice) -> UInt64? {
    let service = IOHIDDeviceGetService(device)
    guard service != MACH_PORT_NULL else { return nil }
    var id: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { return nil }
    return id
}

/// The USB interface number (rivalcfg's "endpoint"). Looked up on the HID device first, then on its
/// registry ancestors; the spike (Step 5) records which one answers on this macOS version.
private func interfaceNumber(_ device: IOHIDDevice) -> Int? {
    if let direct = intProperty(device, "bInterfaceNumber") { return direct }
    var entry = IOHIDDeviceGetService(device)
    guard entry != MACH_PORT_NULL else { return nil }
    IOObjectRetain(entry)
    defer { IOObjectRelease(entry) }
    for _ in 0..<6 {
        if let value = IORegistryEntryCreateCFProperty(
            entry, "bInterfaceNumber" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Int {
            return value
        }
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
        IOObjectRelease(entry)
        entry = parent
    }
    return nil
}
```
Delete `Sources/MouseHID/Placeholder.swift`.

- [ ] **Step 3: Write `Sources/hidprobe/main.swift` and build**

```swift
import Foundation
import MouseCore
import MouseHID

// hidprobe list            print every SteelSeries HID interface macOS shows for 3 seconds
// hidprobe battery         query the battery of the first supported mouse and print the raw reply
// hidprobe dpi <index>     send the default 5 presets with <index> selected (tests preset switching)

func describe(_ info: HIDDeviceInfo) -> String {
    String(format: "id=%llu vid=%04x pid=%04x iface=%@ usagePage=%04x usage=%04x product=%@",
           info.id, info.vendorID, info.productID,
           info.interfaceNumber.map(String.init) ?? "nil",
           info.usagePage, info.usage, info.product ?? "nil")
}

func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "list"
let transport = IOHIDTransport()
let catalog = try ProfileCatalog.load()

/// First supported interface that shows up within 3 seconds.
func findMouse() async -> (info: HIDDeviceInfo, match: MatchedProfile)? {
    await withTaskGroup(of: (HIDDeviceInfo, MatchedProfile)?.self) { group in
        group.addTask {
            for await event in transport.events() {
                if case .added(let info) = event,
                   let match = catalog.match(vendorID: info.vendorID, productID: info.productID),
                   info.interfaceNumber == match.model.endpoint {
                    return (info, match)
                }
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(3))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first.map { (info: $0.0, match: $0.1) }
    }
}

switch command {
case "list":
    let task = Task {
        for await event in transport.events() {
            switch event {
            case .added(let info): print("ADDED   \(describe(info))")
            case .removed(let id): print("REMOVED id=\(id)")
            }
        }
    }
    try await Task.sleep(for: .seconds(3))
    task.cancel()

case "battery":
    guard let (info, match) = await findMouse() else {
        print("No supported mouse with the expected interface found. Run `hidprobe list` and compare.")
        exit(1)
    }
    print("using \(match.model.name)  [\(describe(info))]")
    let connection = try await transport.open(info)
    guard let battery = match.family.battery else { exit(2) }
    await connection.flushInput()
    try await connection.write(battery.command.map { UInt8($0) })
    try await Task.sleep(for: .milliseconds(50))
    if let reply = try await connection.read(length: 64, timeout: .milliseconds(200)) {
        print("raw reply: \(hexString(reply))")
        if let reading = BatteryDecoder.decode(decoder: battery.decoder, reply: reply) {
            print("battery: \(reading.level)%\(reading.isCharging ? " (charging)" : "")")
        } else {
            print("reply is not a valid battery reading")
        }
    } else {
        print("no reply within 200 ms (is the mouse awake?)")
    }
    await connection.close()

case "dpi":
    guard arguments.count > 1, let index = Int(arguments[1]) else { print("usage: hidprobe dpi <0-4>"); exit(64) }
    guard let (info, match) = await findMouse() else { print("No supported mouse found."); exit(1) }
    let connection = try await transport.open(info)
    let device = MouseDevice(
        family: match.family, model: match.model, connection: connection,
        encoder: SettingEncoder(layouts: try ButtonLayouts.load()), sleeper: SystemSleeper()
    )
    try await device.apply(
        "sensitivity",
        .dpiPresets(presets: [400, 800, 1200, 2400, 3200], selected: index)
    )
    print("sent presets 400/800/1200/2400/3200 with preset \(index) selected (no save). Move the mouse and judge the speed.")
    await device.close()

default:
    print("usage: hidprobe list | battery | dpi <index>")
    exit(64)
}
```
Run: `swift build --arch arm64`
Expected: `Build complete!`. If Swift rejects a C-callback closure or a CF type crossing an isolation boundary, fix it inside `Sources/MouseHID` only (that target is Swift 5 mode on purpose); for example wrap the offending value in a `final class Box: @unchecked Sendable`.

- [ ] **Step 4: Plug in the mouse (dongle first) and list interfaces**

Run: `swift run hidprobe list`
Expected: several `ADDED` lines with `vid=1038`. At least one line with `pid=1848` and `iface=3`. Write down every line for the dongle (all interfaces, their `usagePage`/`usage`). If no `pid=1848` line appears, or `iface=nil` on all of them, the interface-number lookup needs fixing: inspect with `ioreg -r -c IOHIDDevice -l | grep -B2 -A30 "Prime"` and adapt `interfaceNumber(_:)` (property name or ancestor level), then rerun. If Input Monitoring is required, macOS shows a prompt or the list is empty: grant the terminal app in System Settings → Privacy & Security → Input Monitoring and rerun.

- [ ] **Step 5: Read the battery natively and compare with the CLI**

Run: `swift run hidprobe battery` then `~/rivalcfg/rivalcfg --battery-level`
Expected: hidprobe prints `raw reply: 00 xx ...` and `battery: NN%`; the CLI prints a percentage within 5 points of it. If the reply is empty, move the mouse to wake it and retry once. Record both results.

- [ ] **Step 6: Repeat on the cable and check preset switching**

Plug the USB cable (keep the dongle in for one run, then remove it for another). Run `swift run hidprobe list` and `swift run hidprobe battery` for `pid=184a`. Then run `swift run hidprobe dpi 0` and `swift run hidprobe dpi 4`.
Expected: wired battery works the same way; with preset 4 selected the pointer is visibly faster than with preset 0. If it does not change, preset selection through this command is **not** confirmed: Task 13 must then omit the "Active preset" picker.

- [ ] **Step 7: Write the spike note and decide**

Create `docs/superpowers/notes/2026-10-10-phase0-spike.md` containing, from what you observed (no guesses): the `list` output for dongle and cable, which property gave the interface number, whether Input Monitoring or any other permission prompt appeared, the raw battery replies and percentages from `hidprobe` and from `rivalcfg --battery-level`, whether `dpi` preset selection visibly worked, and a one-line decision: `GO` if hidprobe read a valid battery on both connections without extra permission problems, otherwise `NO-GO` with the failure.

If `NO-GO`: stop the plan here and tell the user; the fallback is the CLI backend from the spec, which needs a new plan.

- [ ] **Step 8: Commit**

```bash
git add Sources docs
git commit -m "feat(hid): IOKit transport and hidprobe diagnostic CLI (phase 0 spike)" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Device manager, battery state machine, presentation

**Files:**
- Create: `Sources/MouseCore/DeviceManager.swift`, `Sources/MouseCore/BatteryMonitor.swift`
- Test: `Tests/MouseCoreTests/DeviceManagerTests.swift`, `Tests/MouseCoreTests/BatteryTests.swift`

**Interfaces:**
- Consumes: `HIDTransport`, `SimulatedHIDTransport`, `MouseDevice`, `ProfileCatalog`, `SettingEncoder`, `Sleeper`, `BatteryReading` (Tasks 2–7)
- Produces:
  - `struct ConnectedMouse: Sendable { hidID: UInt64; family: DeviceFamily; model: DeviceModel; device: MouseDevice; public init(...) }`
  - `enum DeviceEvent: Sendable { case connected(ConnectedMouse), disconnected(hidID: UInt64), openFailed(HIDDeviceInfo, message: String) }`
  - `actor DeviceManager { nonisolated let events: AsyncStream<DeviceEvent>; init(transport:catalog:encoder:sleeper:); func start(); func stop() async }`
  - `enum ActiveMousePolicy { static func choose(from: [ConnectedMouse]) -> ConnectedMouse? }` (wired beats dongle; otherwise the earliest in the list)
  - `struct BatteryState: Equatable, Sendable { enum Freshness { fresh, stale, asleep, disconnected }; level: Int?; isCharging: Bool?; lastReadAt: Date?; consecutiveFailures: Int; freshness: Freshness; static let disconnected, static let connecting; func applying(_ reading: BatteryReading?, at: Date) -> BatteryState }`
  - `actor BatteryMonitor { init(device: MouseDevice, interval: Duration, sleeper: any Sleeper, now: @escaping @Sendable () -> Date); func pollOnce() async -> BatteryState; func run(_ onChange: @escaping @Sendable (BatteryState) async -> Void) async }`
  - `enum BatteryPresentation { static func symbolName(for: BatteryState) -> String; static func compactTitle(for: BatteryState) -> String?; static func detail(for: BatteryState, now: Date) -> String }`

- [ ] **Step 1: Write the failing tests**

`Tests/MouseCoreTests/DeviceManagerTests.swift`:
```swift
import Testing
@testable import MouseCore

@Suite struct DeviceManagerTests {
    func makeManager(_ transport: SimulatedHIDTransport) throws -> DeviceManager {
        DeviceManager(
            transport: transport,
            catalog: try ProfileCatalog.load(),
            encoder: SettingEncoder(layouts: try ButtonLayouts.load()),
            sleeper: RecordingSleeper()
        )
    }

    func info(id: UInt64, pid: Int, iface: Int?) -> HIDDeviceInfo {
        HIDDeviceInfo(id: id, vendorID: 0x1038, productID: pid, interfaceNumber: iface)
    }

    @Test(.timeLimit(.minutes(1)))
    func dongleInterfaceThreeBecomesAConnectedMouse() async throws {
        let transport = SimulatedHIDTransport()
        transport.plug(info(id: 1, pid: 0x1848, iface: 3), connection: SimulatedHIDConnection())
        let manager = try makeManager(transport)
        await manager.start()
        var events = manager.events.makeAsyncIterator()
        guard case .connected(let mouse)? = await events.next() else { Issue.record("expected connected"); return }
        #expect(mouse.hidID == 1)
        #expect(mouse.family.id == "prime_wireless_wireless")
        #expect(mouse.model.mouse == "prime_mini_wireless")
        await manager.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func otherInterfacesAndUnknownProductsAreIgnored() async throws {
        let transport = SimulatedHIDTransport()
        transport.plug(info(id: 1, pid: 0x1848, iface: 0), connection: SimulatedHIDConnection())   // wrong interface
        transport.plug(info(id: 2, pid: 0x1848, iface: nil), connection: SimulatedHIDConnection()) // unknown interface
        transport.plug(info(id: 3, pid: 0xFFFF, iface: 3), connection: SimulatedHIDConnection())   // unknown product
        transport.plug(info(id: 4, pid: 0x184A, iface: 3), connection: SimulatedHIDConnection())   // the one that counts
        let manager = try makeManager(transport)
        await manager.start()
        var events = manager.events.makeAsyncIterator()
        guard case .connected(let mouse)? = await events.next() else { Issue.record("expected connected"); return }
        #expect(mouse.hidID == 4)
        #expect(mouse.family.id == "prime_wireless_wired")
        await manager.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func unplugEmitsDisconnectedAndClosesTheConnection() async throws {
        let transport = SimulatedHIDTransport()
        let connection = SimulatedHIDConnection()
        transport.plug(info(id: 7, pid: 0x1848, iface: 3), connection: connection)
        let manager = try makeManager(transport)
        await manager.start()
        var events = manager.events.makeAsyncIterator()
        _ = await events.next()
        transport.unplug(id: 7)
        guard case .disconnected(let id)? = await events.next() else { Issue.record("expected disconnected"); return }
        #expect(id == 7)
        #expect(await connection.isClosed)
        await manager.stop()
    }

    @Test(.timeLimit(.minutes(1)))
    func openFailureIsReportedNotSwallowed() async throws {
        let transport = SimulatedHIDTransport()
        transport.setOpenFails(true)
        transport.plug(info(id: 9, pid: 0x1848, iface: 3), connection: SimulatedHIDConnection())
        let manager = try makeManager(transport)
        await manager.start()
        var events = manager.events.makeAsyncIterator()
        guard case .openFailed(let failed, _)? = await events.next() else { Issue.record("expected openFailed"); return }
        #expect(failed.id == 9)
        await manager.stop()
    }

    @Test func wiredBeatsDongleWhenBothArePresent() async throws {
        let catalog = try ProfileCatalog.load()
        func mouse(_ id: UInt64, _ pid: Int) throws -> ConnectedMouse {
            let match = try #require(catalog.match(vendorID: 0x1038, productID: pid))
            let device = MouseDevice(
                family: match.family, model: match.model, connection: SimulatedHIDConnection(),
                encoder: SettingEncoder(layouts: try ButtonLayouts.load()), sleeper: RecordingSleeper()
            )
            return ConnectedMouse(hidID: id, family: match.family, model: match.model, device: device)
        }
        let dongle = try mouse(1, 0x1848)
        let cable = try mouse(2, 0x184A)
        #expect(ActiveMousePolicy.choose(from: []) == nil)
        #expect(ActiveMousePolicy.choose(from: [dongle])?.hidID == 1)
        #expect(ActiveMousePolicy.choose(from: [dongle, cable])?.hidID == 2)
        #expect(ActiveMousePolicy.choose(from: [cable, dongle])?.hidID == 2)
        #expect(ActiveMousePolicy.choose(from: [cable])?.hidID == 2)
        // Cable pulled out: the caller passes only the dongle, and the dongle is chosen again.
        #expect(ActiveMousePolicy.choose(from: [dongle])?.hidID == 1)
    }
}
```

`Tests/MouseCoreTests/BatteryTests.swift`:
```swift
import Foundation
import Testing
@testable import MouseCore

@Suite struct BatteryTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func freshReadingReplacesEverything() {
        let state = BatteryState.connecting.applying(BatteryReading(level: 80, isCharging: false), at: t0)
        #expect(state.level == 80)
        #expect(state.isCharging == false)
        #expect(state.freshness == .fresh)
        #expect(state.lastReadAt == t0)
        #expect(state.consecutiveFailures == 0)
    }

    @Test func oneFailureIsStaleTwoIsAsleepAndBothKeepTheLastValue() {
        let fresh = BatteryState.connecting.applying(BatteryReading(level: 80, isCharging: false), at: t0)
        let stale = fresh.applying(nil, at: t0.addingTimeInterval(60))
        #expect(stale.freshness == .stale)
        #expect(stale.level == 80)
        let asleep = stale.applying(nil, at: t0.addingTimeInterval(120))
        #expect(asleep.freshness == .asleep)
        #expect(asleep.level == 80)
        #expect(asleep.lastReadAt == t0)
    }

    @Test func aSuccessfulReadAfterSleepingIsFreshAgain() {
        let asleep = BatteryState.connecting
            .applying(BatteryReading(level: 80, isCharging: false), at: t0)
            .applying(nil, at: t0).applying(nil, at: t0)
        let woke = asleep.applying(BatteryReading(level: 79, isCharging: false), at: t0.addingTimeInterval(300))
        #expect(woke.freshness == .fresh)
        #expect(woke.level == 79)
        #expect(woke.consecutiveFailures == 0)
    }

    @Test func neverReadStaysWithoutALevelNeverZero() {
        let state = BatteryState.connecting.applying(nil, at: t0).applying(nil, at: t0)
        #expect(state.level == nil)
        #expect(state.freshness == .asleep)
    }

    @Test func presentation() {
        let fresh = BatteryState.connecting.applying(BatteryReading(level: 87, isCharging: false), at: t0)
        #expect(BatteryPresentation.compactTitle(for: fresh) == "87%")
        #expect(BatteryPresentation.symbolName(for: fresh) == "battery.75percent")
        let charging = BatteryState.connecting.applying(BatteryReading(level: 40, isCharging: true), at: t0)
        #expect(BatteryPresentation.symbolName(for: charging) == "battery.100percent.bolt")
        let low = BatteryState.connecting.applying(BatteryReading(level: 5, isCharging: false), at: t0)
        #expect(BatteryPresentation.symbolName(for: low) == "battery.0percent")
        #expect(BatteryPresentation.compactTitle(for: .disconnected) == nil)
        #expect(BatteryPresentation.symbolName(for: .disconnected) == "computermouse")
        #expect(BatteryPresentation.compactTitle(for: .connecting) == "…")
    }

    @Test func detailMentionsSleepAndAge() {
        let asleep = BatteryState.connecting
            .applying(BatteryReading(level: 80, isCharging: false), at: t0)
            .applying(nil, at: t0).applying(nil, at: t0)
        let text = BatteryPresentation.detail(for: asleep, now: t0.addingTimeInterval(180))
        #expect(text.contains("80%"))
        #expect(text.contains("asleep"))
        #expect(text.contains("3 min"))
        #expect(BatteryPresentation.detail(for: .disconnected, now: t0) == "No mouse connected")
    }

    @Test func monitorPollOnceReadsTheDeviceAndTracksFailures() async throws {
        let catalog = try ProfileCatalog.load()
        let match = try #require(catalog.match(vendorID: 0x1038, productID: 0x1848))
        let connection = SimulatedHIDConnection(replyProvider: batteryReplyProvider(raw: 0x0B))
        let device = MouseDevice(
            family: match.family, model: match.model, connection: connection,
            encoder: SettingEncoder(layouts: try ButtonLayouts.load()), sleeper: RecordingSleeper()
        )
        let monitor = BatteryMonitor(device: device, interval: .seconds(60), sleeper: RecordingSleeper(), now: { Date(timeIntervalSince1970: 5) })
        let state = await monitor.pollOnce()
        #expect(state.level == 50)
        #expect(state.freshness == .fresh)
    }

    @Test func monitorMarksAsleepWhenTheMouseStaysSilent() async throws {
        let catalog = try ProfileCatalog.load()
        let match = try #require(catalog.match(vendorID: 0x1038, productID: 0x1848))
        let device = MouseDevice(
            family: match.family, model: match.model, connection: SimulatedHIDConnection(),
            encoder: SettingEncoder(layouts: try ButtonLayouts.load()), sleeper: RecordingSleeper()
        )
        let monitor = BatteryMonitor(device: device, interval: .seconds(60), sleeper: RecordingSleeper(), now: { Date() })
        _ = await monitor.pollOnce()
        let second = await monitor.pollOnce()
        #expect(second.freshness == .asleep)
        #expect(second.level == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "DeviceManagerTests|BatteryTests"`
Expected: compile FAIL (`cannot find 'DeviceManager'`, `'BatteryState'`).

- [ ] **Step 3: Write `Sources/MouseCore/DeviceManager.swift`**

```swift
public struct ConnectedMouse: Sendable {
    public let hidID: UInt64
    public let family: DeviceFamily
    public let model: DeviceModel
    public let device: MouseDevice

    public init(hidID: UInt64, family: DeviceFamily, model: DeviceModel, device: MouseDevice) {
        self.hidID = hidID
        self.family = family
        self.model = model
        self.device = device
    }
}

public enum DeviceEvent: Sendable {
    case connected(ConnectedMouse)
    case disconnected(hidID: UInt64)
    case openFailed(HIDDeviceInfo, message: String)
}

public enum ActiveMousePolicy {
    /// The cable beats the dongle (the mouse is charging and the path is direct); otherwise the earliest.
    public static func choose(from mice: [ConnectedMouse]) -> ConnectedMouse? {
        mice.first(where: { !$0.model.isWireless }) ?? mice.first
    }
}

public actor DeviceManager {
    public nonisolated let events: AsyncStream<DeviceEvent>
    private let continuation: AsyncStream<DeviceEvent>.Continuation
    private let transport: any HIDTransport
    private let catalog: ProfileCatalog
    private let encoder: SettingEncoder
    private let sleeper: any Sleeper
    private var active: [UInt64: ConnectedMouse] = [:]
    private var task: Task<Void, Never>?

    public init(
        transport: any HIDTransport,
        catalog: ProfileCatalog,
        encoder: SettingEncoder,
        sleeper: any Sleeper
    ) {
        self.transport = transport
        self.catalog = catalog
        self.encoder = encoder
        self.sleeper = sleeper
        let made = AsyncStream.makeStream(of: DeviceEvent.self)
        events = made.stream
        continuation = made.continuation
    }

    public func start() {
        guard task == nil else { return }
        let stream = transport.events()
        task = Task { [weak self] in
            for await event in stream {
                await self?.handle(event)
            }
        }
    }

    public func stop() async {
        task?.cancel()
        task = nil
        for mouse in active.values { await mouse.device.close() }
        active.removeAll()
        continuation.finish()
    }

    private func handle(_ event: HIDEvent) async {
        switch event {
        case .added(let info):
            await add(info)
        case .removed(let id):
            guard let mouse = active.removeValue(forKey: id) else { return }
            await mouse.device.close()
            continuation.yield(.disconnected(hidID: id))
        }
    }

    private func add(_ info: HIDDeviceInfo) async {
        guard active[info.id] == nil,
              let match = catalog.match(vendorID: info.vendorID, productID: info.productID),
              info.interfaceNumber == match.model.endpoint
        else { return }
        do {
            let connection = try await transport.open(info)
            let device = MouseDevice(
                family: match.family, model: match.model, connection: connection,
                encoder: encoder, sleeper: sleeper
            )
            let mouse = ConnectedMouse(hidID: info.id, family: match.family, model: match.model, device: device)
            active[info.id] = mouse
            continuation.yield(.connected(mouse))
        } catch {
            continuation.yield(.openFailed(info, message: String(describing: error)))
        }
    }
}
```

- [ ] **Step 4: Write `Sources/MouseCore/BatteryMonitor.swift`**

```swift
import Foundation

public struct BatteryState: Equatable, Sendable {
    public enum Freshness: Equatable, Sendable {
        case fresh, stale, asleep, disconnected
    }

    public var level: Int?
    public var isCharging: Bool?
    public var lastReadAt: Date?
    public var consecutiveFailures: Int
    public var freshness: Freshness

    public static let disconnected = BatteryState(
        level: nil, isCharging: nil, lastReadAt: nil, consecutiveFailures: 0, freshness: .disconnected
    )
    /// A mouse is connected but nothing has been read yet.
    public static let connecting = BatteryState(
        level: nil, isCharging: nil, lastReadAt: nil, consecutiveFailures: 0, freshness: .stale
    )

    /// One failed read keeps the last value as stale; two in a row mean asleep. The last value is kept.
    public func applying(_ reading: BatteryReading?, at date: Date) -> BatteryState {
        if let reading {
            return BatteryState(
                level: reading.level, isCharging: reading.isCharging,
                lastReadAt: date, consecutiveFailures: 0, freshness: .fresh
            )
        }
        var next = self
        next.consecutiveFailures += 1
        next.freshness = next.consecutiveFailures >= 2 ? .asleep : .stale
        return next
    }
}

public actor BatteryMonitor {
    private let device: MouseDevice
    private let interval: Duration
    private let sleeper: any Sleeper
    private let now: @Sendable () -> Date
    private var state = BatteryState.connecting

    public init(
        device: MouseDevice,
        interval: Duration,
        sleeper: any Sleeper,
        now: @escaping @Sendable () -> Date
    ) {
        self.device = device
        self.interval = interval
        self.sleeper = sleeper
        self.now = now
    }

    public func pollOnce() async -> BatteryState {
        let reading = try? await device.readBattery()
        state = state.applying(reading, at: now())
        return state
    }

    /// Polls until the task is cancelled.
    public func run(_ onChange: @escaping @Sendable (BatteryState) async -> Void) async {
        while !Task.isCancelled {
            await onChange(await pollOnce())
            await sleeper.sleep(for: interval)
        }
    }
}

public enum BatteryPresentation {
    public static func symbolName(for state: BatteryState) -> String {
        guard state.freshness != .disconnected, let level = state.level else { return "computermouse" }
        if state.isCharging == true { return "battery.100percent.bolt" }
        switch level {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    /// Text next to the menu bar icon. `nil` means show the icon only.
    public static func compactTitle(for state: BatteryState) -> String? {
        if state.freshness == .disconnected { return nil }
        guard let level = state.level else { return "…" }
        return "\(level)%"
    }

    public static func detail(for state: BatteryState, now: Date) -> String {
        if state.freshness == .disconnected { return "No mouse connected" }
        guard let level = state.level else { return "Reading battery…" }
        let charging = state.isCharging == true ? ", charging" : ""
        switch state.freshness {
        case .fresh:
            return "\(level)%\(charging)"
        case .stale:
            return "\(level)%\(charging) (updating…)"
        case .asleep:
            let minutes = state.lastReadAt.map { max(1, Int(now.timeIntervalSince($0) / 60)) }
            let age = minutes.map { ", last read \($0) min ago" } ?? ""
            return "\(level)% (mouse asleep\(age))"
        case .disconnected:
            return "No mouse connected"
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter "DeviceManagerTests|BatteryTests"`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat(core): device manager, battery state machine and presentation" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Settings store, default values, save debouncer

**Files:**
- Create: `Sources/MouseCore/SettingsStore.swift`, `Sources/MouseCore/SaveDebouncer.swift`
- Test: `Tests/MouseCoreTests/SettingsStoreTests.swift`, `Tests/MouseCoreTests/SaveDebouncerTests.swift`

**Interfaces:**
- Consumes: `SettingValue`, `SettingSpec`, `RGBColor`, `ButtonMapping`, `Sleeper`, `ManualSleeper`, `waitUntil` (earlier tasks)
- Produces:
  - `actor SettingsStore { init(directory: URL); static func defaultDirectory() -> URL; func values(for mouse: String) -> [String: SettingValue]; func set(_ value: SettingValue, key: String, mouse: String) throws; func clear(mouse: String) throws }` — corrupt or missing files read as empty
  - `enum DefaultSettings { static func value(for spec: SettingSpec) -> SettingValue? }`
  - `actor SaveDebouncer { init(delay: Duration, sleeper: any Sleeper, action: @escaping @Sendable () async -> Void); func schedule(); func flush() async }`

- [ ] **Step 1: Write the failing tests**

`Tests/MouseCoreTests/SettingsStoreTests.swift`:
```swift
import Foundation
import Testing
@testable import MouseCore

@Suite struct SettingsStoreTests {
    func makeStore() -> (SettingsStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mousebar-tests-\(UUID().uuidString)")
        return (SettingsStore(directory: dir), dir)
    }

    @Test func emptyWhenNothingStored() async {
        let (store, _) = makeStore()
        #expect(await store.values(for: "prime_mini_wireless").isEmpty)
    }

    @Test func valuesPersistAcrossStoreInstances() async throws {
        let (store, dir) = makeStore()
        try await store.set(.choice("500"), key: "polling_rate", mouse: "prime_mini_wireless")
        try await store.set(.color(RGBColor(r: 1, g: 2, b: 3)), key: "color", mouse: "prime_mini_wireless")
        let reopened = SettingsStore(directory: dir)
        let values = await reopened.values(for: "prime_mini_wireless")
        #expect(values["polling_rate"] == .choice("500"))
        #expect(values["color"] == .color(RGBColor(r: 1, g: 2, b: 3)))
    }

    @Test func miceDoNotShareValues() async throws {
        let (store, _) = makeStore()
        try await store.set(.int(7), key: "sleep_timer", mouse: "prime_mini_wireless")
        #expect(await store.values(for: "prime_wireless").isEmpty)
    }

    @Test func corruptFileReadsAsEmptyAndIsReplacedOnNextWrite() async throws {
        let (store, dir) = makeStore()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("prime_mini_wireless.json"))
        #expect(await store.values(for: "prime_mini_wireless").isEmpty)
        try await store.set(.int(3), key: "dim_timer", mouse: "prime_mini_wireless")
        let reopened = SettingsStore(directory: dir)
        #expect(await reopened.values(for: "prime_mini_wireless")["dim_timer"] == .int(3))
    }

    @Test func clearRemovesEverythingForOneMouse() async throws {
        let (store, _) = makeStore()
        try await store.set(.int(7), key: "sleep_timer", mouse: "prime_mini_wireless")
        try await store.clear(mouse: "prime_mini_wireless")
        #expect(await store.values(for: "prime_mini_wireless").isEmpty)
    }

    @Test func mouseNamesCannotEscapeTheDirectory() async throws {
        let (store, dir) = makeStore()
        try await store.set(.int(1), key: "k", mouse: "../evil")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.count == 1)
        #expect(!files[0].contains("/"))
    }

    @Test func defaultsForTheWiredFamily() throws {
        func value(_ key: String) throws -> SettingValue? { DefaultSettings.value(for: try spec("prime_wireless_wired", key)) }
        #expect(try value("polling_rate") == .choice("1000"))
        #expect(try value("default_lighting") == .choice("rainbow"))
        #expect(try value("sleep_timer") == .int(5))
        #expect(try value("dim_timer") == .int(30))
        #expect(try value("color") == .color(RGBColor(r: 255, g: 0, b: 0)))
        #expect(try value("sensitivity") == .dpiPresets(presets: [400, 800, 1200, 2400, 3200], selected: nil))
        #expect(try value("buttons_mapping") == .buttons(ButtonMapping()))
    }
}
```

`Tests/MouseCoreTests/SaveDebouncerTests.swift`:
```swift
import Testing
@testable import MouseCore

actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

@Suite struct SaveDebouncerTests {
    @Test func manySchedulesCollapseIntoOneAction() async {
        let sleeper = ManualSleeper()
        let counter = Counter()
        let debouncer = SaveDebouncer(delay: .seconds(2), sleeper: sleeper) { await counter.increment() }
        for _ in 0..<5 { await debouncer.schedule() }
        #expect(await waitUntil { await sleeper.waiterCount == 5 })
        await sleeper.releaseAll()
        #expect(await waitUntil { await counter.value == 1 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await counter.value == 1)
    }

    @Test func flushRunsNowAndCancelsTheTimer() async {
        let sleeper = ManualSleeper()
        let counter = Counter()
        let debouncer = SaveDebouncer(delay: .seconds(2), sleeper: sleeper) { await counter.increment() }
        await debouncer.schedule()
        #expect(await waitUntil { await sleeper.waiterCount == 1 })
        await debouncer.flush()
        #expect(await counter.value == 1)
        await sleeper.releaseAll()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await counter.value == 1)
    }

    @Test func flushWithNothingPendingDoesNothing() async {
        let counter = Counter()
        let debouncer = SaveDebouncer(delay: .seconds(2), sleeper: ManualSleeper()) { await counter.increment() }
        await debouncer.flush()
        #expect(await counter.value == 0)
    }

    @Test func scheduleAfterAFireStartsANewCycle() async {
        let sleeper = ManualSleeper()
        let counter = Counter()
        let debouncer = SaveDebouncer(delay: .seconds(2), sleeper: sleeper) { await counter.increment() }
        await debouncer.schedule()
        #expect(await waitUntil { await sleeper.waiterCount == 1 })
        await sleeper.releaseAll()
        #expect(await waitUntil { await counter.value == 1 })
        await debouncer.schedule()
        #expect(await waitUntil { await sleeper.waiterCount == 1 })
        await sleeper.releaseAll()
        #expect(await waitUntil { await counter.value == 2 })
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "SettingsStoreTests|SaveDebouncerTests"`
Expected: compile FAIL (`cannot find 'SettingsStore'`, `'SaveDebouncer'`, `'DefaultSettings'`).

- [ ] **Step 3: Write `Sources/MouseCore/SettingsStore.swift`**

```swift
import Foundation

/// The mouse is write-only, so we remember what the user chose and re-apply it on connect.
public actor SettingsStore {
    private struct File: Codable {
        var version = 1
        var values: [String: SettingValue] = [:]
    }

    private let directory: URL
    private var cache: [String: File] = [:]

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MouseBar", isDirectory: true)
    }

    public func values(for mouse: String) -> [String: SettingValue] {
        load(mouse).values
    }

    public func set(_ value: SettingValue, key: String, mouse: String) throws {
        var file = load(mouse)
        file.values[key] = value
        try write(file, mouse: mouse)
    }

    public func clear(mouse: String) throws {
        try write(File(), mouse: mouse)
    }

    private func url(for mouse: String) -> URL {
        let safe = String(mouse.unicodeScalars.map { scalar in
            (scalar.properties.isAlphabetic && scalar.isASCII) || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-"
                ? Character(scalar) : "_"
        })
        return directory.appendingPathComponent("\(safe).json")
    }

    private func load(_ mouse: String) -> File {
        if let cached = cache[mouse] { return cached }
        let file = (try? Data(contentsOf: url(for: mouse)))
            .flatMap { try? JSONDecoder().decode(File.self, from: $0) } ?? File()
        cache[mouse] = file
        return file
    }

    private func write(_ file: File, mouse: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url(for: mouse), options: .atomic)
        cache[mouse] = file
    }
}

public enum DefaultSettings {
    /// The factory value of a setting, as rivalcfg's `--reset` would apply it.
    public static func value(for spec: SettingSpec) -> SettingValue? {
        switch spec.valueType {
        case "choice":
            return .choice(spec.defaultText)
        case "range":
            return Int(spec.defaultText).map(SettingValue.int)
        case "rgbcolor":
            return RGBColor(parsing: spec.defaultText).map(SettingValue.color)
        case "multidpi_range_choice":
            let presets = spec.defaultText
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return presets.isEmpty ? nil : .dpiPresets(presets: presets, selected: nil)
        case "buttons":
            return .buttons(ButtonMapping())
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Write `Sources/MouseCore/SaveDebouncer.swift`**

```swift
/// Collapses bursts of edits into one device save (the mouse's memory has limited write cycles).
public actor SaveDebouncer {
    private let delay: Duration
    private let sleeper: any Sleeper
    private let action: @Sendable () async -> Void
    private var generation = 0
    private var pending = false

    public init(delay: Duration, sleeper: any Sleeper, action: @escaping @Sendable () async -> Void) {
        self.delay = delay
        self.sleeper = sleeper
        self.action = action
    }

    public func schedule() {
        generation += 1
        pending = true
        let mine = generation
        Task { [delay, sleeper] in
            await sleeper.sleep(for: delay)
            await self.fire(ifGeneration: mine)
        }
    }

    /// Runs the action now if a save is pending (used on quit).
    public func flush() async {
        guard pending else { return }
        pending = false
        generation += 1
        await action()
    }

    private func fire(ifGeneration value: Int) async {
        guard pending, value == generation else { return }
        pending = false
        await action()
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter "SettingsStoreTests|SaveDebouncerTests"`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat(core): settings store, factory defaults and debounced save" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 11: `MouseSession` and GG detector

**Files:**
- Create: `Sources/MouseCore/MouseSession.swift`, `Sources/MouseCore/GGDetector.swift`
- Test: `Tests/MouseCoreTests/MouseSessionTests.swift`, `Tests/MouseCoreTests/GGDetectorTests.swift`

**Interfaces:**
- Consumes: `ConnectedMouse`, `MouseDevice`, `SettingsStore`, `DefaultSettings`, `SaveDebouncer`, `BatteryMonitor`, `BatteryState`, `SettingEncoder` (earlier tasks)
- Produces:
  - `actor MouseSession { init(mouse: ConnectedMouse, store: SettingsStore, encoder: SettingEncoder, sleeper: any Sleeper, pollInterval: Duration = .seconds(60), saveDelay: Duration = .seconds(2), now: @escaping @Sendable () -> Date = { Date() }); func start(onBattery: @escaping @Sendable (BatteryState) async -> Void, onError: @escaping @Sendable (String) async -> Void) async -> [String]; func set(_ key: String, _ value: SettingValue) async throws; func submit(_ key: String, _ value: SettingValue); func waitUntilIdle() async; func resetAll() async throws; func flush() async; func stop() }`
  - `var currentValues: [String: SettingValue] { get }` (actor-isolated read of what the user chose)
  - `enum GGDetector { static func isEngineRunning(pgrep: @Sendable (String) -> Bool = livePgrep) -> Bool }`

- [ ] **Step 1: Write the failing tests**

`Tests/MouseCoreTests/MouseSessionTests.swift`:
```swift
import Foundation
import Testing
@testable import MouseCore

@Suite struct MouseSessionTests {
    struct Rig {
        let session: MouseSession
        let connection: SimulatedHIDConnection
        let store: SettingsStore
        let sleeper: ManualSleeper
    }

    func makeRig(productID: Int = 0x184A) async throws -> Rig {
        let catalog = try ProfileCatalog.load()
        let match = try #require(catalog.match(vendorID: 0x1038, productID: productID))
        let connection = SimulatedHIDConnection(replyProvider: batteryReplyProvider(raw: 0x0B))
        let encoder = SettingEncoder(layouts: try ButtonLayouts.load())
        let device = MouseDevice(
            family: match.family, model: match.model, connection: connection,
            encoder: encoder, sleeper: RecordingSleeper()
        )
        let store = SettingsStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("mousebar-\(UUID().uuidString)")
        )
        let sleeper = ManualSleeper()
        let session = MouseSession(
            mouse: ConnectedMouse(hidID: 1, family: match.family, model: match.model, device: device),
            store: store, encoder: encoder, sleeper: sleeper
        )
        return Rig(session: session, connection: connection, store: store, sleeper: sleeper)
    }

    @Test func startReappliesStoredValuesInProfileOrder() async throws {
        let rig = try await makeRig()
        // Stored out of profile order on purpose.
        try await rig.store.set(.int(10), key: "sleep_timer", mouse: "prime_mini_wireless")
        try await rig.store.set(.choice("500"), key: "polling_rate", mouse: "prime_mini_wireless")
        let errors = await rig.session.start(onBattery: { _ in }, onError: { _ in })
        #expect(errors.isEmpty)
        let writes = await rig.connection.writes.filter { $0.first != 0x92 }
        #expect(writes == [[0x2B, 0x01], [0x29, 0xC0, 0x27, 0x09]])   // polling_rate, then sleep_timer (10 min)
        await rig.session.stop()
    }

    @Test func startReportsBatteryThroughTheCallback() async throws {
        let rig = try await makeRig()
        let box = StateBox()
        _ = await rig.session.start(onBattery: { await box.set($0) }, onError: { _ in })
        #expect(await waitUntil { await box.value?.level == 50 })
        await rig.session.stop()
    }

    @Test func setWritesPersistsAndSchedulesExactlyOneSave() async throws {
        let rig = try await makeRig()
        try await rig.session.set("polling_rate", .choice("250"))
        try await rig.session.set("polling_rate", .choice("125"))
        #expect(await rig.connection.writes == [[0x2B, 0x02], [0x2B, 0x03]])
        #expect(await rig.store.values(for: "prime_mini_wireless")["polling_rate"] == .choice("125"))
        #expect(await waitUntil { await rig.sleeper.waiterCount == 2 })
        await rig.sleeper.releaseAll()
        #expect(await waitUntil { await rig.connection.writes.count == 3 })
        #expect(await rig.connection.writes.last == [0x11, 0x00])
    }

    @Test func colorIsAppliedButNeverScheduledForSaving() async throws {
        let rig = try await makeRig()
        try await rig.session.set("color", .color(RGBColor(r: 255, g: 128, b: 0)))
        #expect(await rig.connection.writes == [[0x21, 0x01, 0x00, 255, 128, 0]])
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await rig.sleeper.waiterCount == 0)
    }

    @Test func buttonMappingWithoutLeftClickIsRejectedBeforeAnyWrite() async throws {
        let rig = try await makeRig()
        await #expect(throws: MouseCoreError.noPrimaryClick) {
            try await rig.session.set("buttons_mapping", .buttons(ButtonMapping(assignments: ["button1": "disabled"])))
        }
        #expect(await rig.connection.writes.isEmpty)
        #expect(await rig.store.values(for: "prime_mini_wireless").isEmpty)
    }

    @Test func invalidValueIsNotPersisted() async throws {
        let rig = try await makeRig()
        await #expect(throws: MouseCoreError.self) {
            try await rig.session.set("sensitivity", .dpiPresets(presets: [], selected: nil))
        }
        #expect(await rig.store.values(for: "prime_mini_wireless").isEmpty)
    }

    @Test func flushSavesAPendingChangeImmediately() async throws {
        let rig = try await makeRig()
        try await rig.session.set("polling_rate", .choice("500"))
        await rig.session.flush()
        #expect(await rig.connection.writes.last == [0x11, 0x00])
    }

    @Test func submitCoalescesToTheLatestValue() async throws {
        let rig = try await makeRig()
        for g in stride(from: 0, through: 250, by: 25) {
            await rig.session.submit("color", .color(RGBColor(r: 0, g: UInt8(g), b: 0)))
        }
        await rig.session.waitUntilIdle()
        let writes = await rig.connection.writes
        #expect(writes.last == [0x21, 0x01, 0x00, 0, 250, 0])
        #expect(writes.count <= 11)
    }

    @Test func resetAllAppliesFactoryDefaultsClearsTheStoreAndSchedulesASave() async throws {
        let rig = try await makeRig()
        try await rig.session.set("polling_rate", .choice("125"))
        let before = await rig.connection.writes.count
        try await rig.session.resetAll()
        let writes = await rig.connection.writes
        #expect(writes.count - before == 7)                       // every setting of the family
        #expect(writes.contains([0x2B, 0x00]))                    // polling back to 1000 Hz
        #expect(await rig.store.values(for: "prime_mini_wireless").isEmpty)
        #expect(await waitUntil { await rig.sleeper.waiterCount >= 1 })
    }

    @Test func currentValuesReflectWhatTheUserChose() async throws {
        let rig = try await makeRig()
        try await rig.session.set("sleep_timer", .int(7))
        #expect(await rig.session.currentValues["sleep_timer"] == .int(7))
    }
}

actor StateBox {
    private(set) var value: BatteryState?
    func set(_ state: BatteryState) { value = state }
}
```

`Tests/MouseCoreTests/GGDetectorTests.swift`:
```swift
import Testing
@testable import MouseCore

@Suite struct GGDetectorTests {
    @Test func asksForTheEngineProcessByExactName() {
        let asked = Box<String?>(nil)
        let running = GGDetector.isEngineRunning(pgrep: { name in asked.value = name; return true })
        #expect(running)
        #expect(asked.value == "SteelSeriesEngine")
    }

    @Test func reportsNotRunningWhenPgrepFindsNothing() {
        #expect(!GGDetector.isEngineRunning(pgrep: { _ in false }))
    }
}

final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "MouseSessionTests|GGDetectorTests"`
Expected: compile FAIL (`cannot find 'MouseSession'`, `'GGDetector'`).

- [ ] **Step 3: Write `Sources/MouseCore/GGDetector.swift`**

```swift
import Foundation

public enum GGDetector {
    /// GG's device engine. We only warn when it runs; we never stop it.
    public static let engineProcessName = "SteelSeriesEngine"

    public static func isEngineRunning(pgrep: @Sendable (String) -> Bool = livePgrep) -> Bool {
        pgrep(engineProcessName)
    }

    @Sendable
    public static func livePgrep(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
```

- [ ] **Step 4: Write `Sources/MouseCore/MouseSession.swift`**

```swift
import Foundation

/// Everything the app does with one connected mouse: re-apply saved settings, edit them,
/// save to the device at a safe rate, and report the battery.
public actor MouseSession {
    public let mouse: ConnectedMouse
    private let store: SettingsStore
    private let encoder: SettingEncoder
    private let debouncer: SaveDebouncer
    private let monitor: BatteryMonitor
    private var values: [String: SettingValue] = [:]
    private var monitorTask: Task<Void, Never>?
    private var queued: [String: SettingValue] = [:]
    private var draining = false
    private var onError: (@Sendable (String) async -> Void)?

    public init(
        mouse: ConnectedMouse,
        store: SettingsStore,
        encoder: SettingEncoder,
        sleeper: any Sleeper,
        pollInterval: Duration = .seconds(60),
        saveDelay: Duration = .seconds(2),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.mouse = mouse
        self.store = store
        self.encoder = encoder
        let device = mouse.device
        self.debouncer = SaveDebouncer(delay: saveDelay, sleeper: sleeper) {
            try? await device.save()
        }
        self.monitor = BatteryMonitor(device: device, interval: pollInterval, sleeper: sleeper, now: now)
    }

    public var currentValues: [String: SettingValue] { values }

    /// Re-applies saved values (in profile order) and starts the battery loop.
    /// Returns human-readable errors for values that could not be applied.
    public func start(
        onBattery: @escaping @Sendable (BatteryState) async -> Void,
        onError: @escaping @Sendable (String) async -> Void
    ) async -> [String] {
        self.onError = onError
        values = await store.values(for: mouse.model.mouse)
        var errors: [String] = []
        for spec in mouse.family.settings {
            guard let value = values[spec.key] else { continue }
            do {
                try await mouse.device.apply(spec.key, value)
            } catch {
                errors.append("\(spec.label): \(error)")
            }
        }
        let monitor = self.monitor
        monitorTask = Task { await monitor.run(onBattery) }
        return errors
    }

    /// Validates, applies, remembers, and schedules one device save (unless the setting is not stored on the device).
    public func set(_ key: String, _ value: SettingValue) async throws {
        guard let spec = mouse.family.setting(key) else { throw MouseCoreError.unknownSetting(key) }
        if case .buttons(let mapping) = value {
            try encoder.validateButtons(mapping, spec: spec)
        }
        try await mouse.device.apply(key, value)
        values[key] = value
        try await store.set(value, key: key, mouse: mouse.model.mouse)
        if spec.persistsOnDevice {
            await debouncer.schedule()
        }
    }

    /// Fire-and-forget edit for sliders and color pickers: only the latest value per setting is written.
    public func submit(_ key: String, _ value: SettingValue) {
        queued[key] = value
        guard !draining else { return }
        draining = true
        Task { await self.drain() }
    }

    public func waitUntilIdle() async {
        while draining || !queued.isEmpty {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    /// Applies every factory default, forgets saved choices, and schedules one device save.
    public func resetAll() async throws {
        for spec in mouse.family.settings {
            guard let value = DefaultSettings.value(for: spec) else { continue }
            try await mouse.device.apply(spec.key, value)
        }
        values = [:]
        try await store.clear(mouse: mouse.model.mouse)
        await debouncer.schedule()
    }

    /// Sends a pending device save now (called when the app quits).
    public func flush() async {
        await debouncer.flush()
    }

    public func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func drain() async {
        while let (key, value) = queued.popFirst() {
            do {
                try await set(key, value)
            } catch {
                await onError?("\(key): \(error)")
            }
        }
        draining = false
    }
}
```
Note: `stop()` is actor-isolated; the first test calls `rig.session.stop()` without `await`. Change those two calls to `await rig.session.stop()`.

- [ ] **Step 5: Run the session and detector tests**

Run: `swift test --filter "MouseSessionTests|GGDetectorTests"`
Expected: all PASS.

- [ ] **Step 6: Run the whole suite**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat(core): MouseSession orchestration and GG process detector" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Menu bar app shell, demo mode, bundle script

**Hardware note:** Everything here can be built and checked with `--demo` (simulated Prime Mini Wireless at 50%). Real-hardware checks happen in Task 14.

**Files:**
- Delete: `Sources/MouseBar/main.swift`
- Create: `Sources/MouseBar/MouseBarApp.swift`, `AppModel.swift`, `AppDelegate.swift`, `DemoTransport.swift`, `Views/BatteryLabel.swift`, `Views/MenuContent.swift`
- Create: `Scripts/bundle.sh`
- Create (placeholder view replaced in Task 13): `Sources/MouseBar/Views/SettingsView.swift`

**Interfaces:**
- Consumes: everything in `MouseCore`, `IOHIDTransport` (Task 8), `SimulatedHIDTransport`
- Produces: `@MainActor @Observable final class AppModel` with `static let shared`, `battery: BatteryState`, `mouseName: String?`, `family: DeviceFamily?`, `values: [String: SettingValue]`, `problem: String?`, `ggWarning: Bool`, `layouts: ButtonLayouts`, `func start()`, `func submit(_ key: String, _ value: SettingValue)`, `func resetAll()`, `func flush() async`.

- [ ] **Step 1: Read the spike note**

Open `docs/superpowers/notes/2026-10-10-phase0-spike.md`. If it says Input Monitoring (or any other usage description) was required, add the matching `NS…UsageDescription` key with a one-sentence reason to the Info.plist in Step 7. If the spike was skipped because no mouse was available, stop here and run Task 8 Steps 4–8 first.

- [ ] **Step 2: Delete the placeholder and write `Sources/MouseBar/DemoTransport.swift`**

```swift
import MouseCore

/// `MouseBar --demo`: a simulated Prime Mini Wireless dongle at 50% battery, for UI work without hardware.
enum DemoTransport {
    static func make() -> SimulatedHIDTransport {
        let transport = SimulatedHIDTransport()
        let connection = SimulatedHIDConnection(replyProvider: { payload in
            guard payload.first == 0xD2 else { return nil }
            return [0x00, 0x0B] + [UInt8](repeating: 0, count: 62)
        })
        transport.plug(
            HIDDeviceInfo(id: 1, vendorID: 0x1038, productID: 0x1848, interfaceNumber: 3, product: "Demo Prime Mini Wireless"),
            connection: connection
        )
        return transport
    }
}
```

- [ ] **Step 3: Write `Sources/MouseBar/AppModel.swift`**

```swift
import Foundation
import MouseCore
import MouseHID
import Observation

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    var battery: BatteryState = .disconnected
    var mouseName: String?
    var family: DeviceFamily?
    var values: [String: SettingValue] = [:]
    var problem: String?
    var ggWarning = false
    let layouts: ButtonLayouts

    private let catalog: ProfileCatalog
    private let store = SettingsStore(directory: SettingsStore.defaultDirectory())
    private var manager: DeviceManager?
    private var session: MouseSession?
    private var activeID: UInt64?
    private var available: [ConnectedMouse] = []
    private var started = false

    private init() {
        // Generated and unit-tested data; failing to decode it is a programming error.
        catalog = try! ProfileCatalog.load()
        layouts = try! ButtonLayouts.load()
    }

    func start() {
        guard !started else { return }
        started = true
        ggWarning = GGDetector.isEngineRunning()
        let transport: any HIDTransport =
            CommandLine.arguments.contains("--demo") ? DemoTransport.make() : IOHIDTransport()
        let manager = DeviceManager(
            transport: transport, catalog: catalog,
            encoder: SettingEncoder(layouts: layouts), sleeper: SystemSleeper()
        )
        self.manager = manager
        Task {
            await manager.start()
            for await event in manager.events {
                await handle(event)
            }
        }
    }

    private func handle(_ event: DeviceEvent) async {
        switch event {
        case .connected(let mouse):
            available.append(mouse)
            await selectActive()
        case .disconnected(let id):
            available.removeAll { $0.hidID == id }
            await selectActive()
        case .openFailed(let info, let message):
            problem = "Could not open \(info.product ?? "the mouse"): \(message). "
                + "If macOS asked for Input Monitoring, allow MouseBar in System Settings → Privacy & Security."
        }
    }

    private func selectActive() async {
        let chosen = ActiveMousePolicy.choose(from: available)
        guard chosen?.hidID != activeID else { return }
        await session?.stop()
        session = nil
        activeID = chosen?.hidID
        values = [:]
        problem = nil
        guard let chosen else {
            battery = .disconnected
            mouseName = nil
            family = nil
            return
        }
        battery = .connecting
        mouseName = chosen.model.name
        family = chosen.family
        let session = MouseSession(
            mouse: chosen, store: store, encoder: SettingEncoder(layouts: layouts), sleeper: SystemSleeper()
        )
        self.session = session
        let errors = await session.start(
            onBattery: { [weak self] state in await self?.setBattery(state) },
            onError: { [weak self] message in await self?.setProblem(message) }
        )
        values = await session.currentValues
        if !errors.isEmpty { problem = errors.joined(separator: "\n") }
    }

    private func setBattery(_ state: BatteryState) { battery = state }
    private func setProblem(_ message: String) { problem = message }

    func submit(_ key: String, _ value: SettingValue) {
        values[key] = value
        guard let session else { return }
        Task { await session.submit(key, value) }
    }

    func resetAll() {
        guard let session else { return }
        Task {
            do {
                try await session.resetAll()
                values = await session.currentValues
            } catch {
                problem = "Reset failed: \(error)"
            }
        }
    }

    func flush() async {
        await session?.flush()
    }
}
```

- [ ] **Step 4: Write `AppDelegate.swift`, `MouseBarApp.swift`, and the two views**

`Sources/MouseBar/AppDelegate.swift`:
```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Send a pending device save before quitting.
        Task { @MainActor in
            await AppModel.shared.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
```

`Sources/MouseBar/MouseBarApp.swift`:
```swift
import SwiftUI
import MouseCore

@main
struct MouseBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    init() {
        AppModel.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            BatteryLabel(state: model.battery)
        }
        Window("Mouse Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
```

`Sources/MouseBar/Views/BatteryLabel.swift`:
```swift
import SwiftUI
import MouseCore

struct BatteryLabel: View {
    let state: BatteryState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: BatteryPresentation.symbolName(for: state))
            if let title = BatteryPresentation.compactTitle(for: state) {
                Text(title)
            }
        }
        .opacity(state.freshness == .asleep ? 0.55 : 1)
    }
}
```

`Sources/MouseBar/Views/MenuContent.swift`:
```swift
import SwiftUI
import MouseCore

struct MenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let name = model.mouseName {
            Text(name)
        }
        Text(BatteryPresentation.detail(for: model.battery, now: Date()))
        if model.ggWarning {
            Divider()
            Text("SteelSeries GG is running and may fight over the mouse.")
        }
        if let problem = model.problem {
            Divider()
            Text(problem)
        }
        Divider()
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Button("Quit MouseBar") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
```

`Sources/MouseBar/Views/SettingsView.swift` (placeholder, replaced in Task 13):
```swift
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    var body: some View {
        Text("Settings arrive in the next task.").padding(40)
    }
}
```
Then delete `Sources/MouseBar/main.swift`.

- [ ] **Step 5: Build**

Run: `swift build --arch arm64`
Expected: `Build complete!`. Fix any Swift 5-mode complaints locally in `Sources/MouseBar`.

- [ ] **Step 6: Write `Scripts/bundle.sh`**

```bash
#!/bin/bash
# Builds build/MouseBar.app (arm64 only, ad-hoc signed). Usage: Scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG" --arch arm64 --product MouseBar
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/MouseBar"

APP="build/MouseBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MouseBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MouseBar</string>
    <key>CFBundleDisplayName</key><string>MouseBar</string>
    <key>CFBundleIdentifier</key><string>dev.mousebar.MouseBar</string>
    <key>CFBundleExecutable</key><string>MouseBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "built $APP"
echo "archs: $(lipo -archs "$APP/Contents/MacOS/MouseBar")"
```
If Step 1 found a required usage-description key, add it to the plist above before the closing `</dict>`.

- [ ] **Step 7: Build the bundle and run it in demo mode**

```bash
chmod +x Scripts/bundle.sh
Scripts/bundle.sh debug
open build/MouseBar.app --args --demo
```
Expected: the script prints `archs: arm64`. A battery icon with `50%` appears at the top right of the menu bar; clicking it shows "Demo…" is not required, but shows `SteelSeries Prime Mini Wireless (2.4 GHz wireless mode)`, `50%`, `Settings…`, `Quit MouseBar`. There is no Dock icon. If SteelSeries GG's engine is running, the GG warning line shows. Quit with the menu item.

- [ ] **Step 8: Commit**

```bash
git add Sources Scripts
git commit -m "feat(app): menu bar battery item, demo mode and app bundle script" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Settings window (data-driven)

**Files:**
- Replace: `Sources/MouseBar/Views/SettingsView.swift`
- Create: `Sources/MouseBar/Views/SettingRows.swift`, `Sources/MouseBar/Views/RGBColor+SwiftUI.swift`

**Interfaces:**
- Consumes: `AppModel` (Task 12), `SettingSpec`, `ButtonSpec`, `SettingValue`, `ButtonLayouts`, `DefaultSettings`, `RGBColor`
- Produces: `SettingsView(model:)`, one row view per value type (`ChoiceRow`, `RangeRow`, `ColorRow`, `DPIRow`, `ButtonsRow`)

The pages are generated from `family.settings`, so no row knows about a specific mouse. The "Active preset" picker in `DPIRow` is included **only if** Task 8 Step 6 confirmed that preset selection visibly works; otherwise delete the marked lines.

- [ ] **Step 1: Write `Sources/MouseBar/Views/RGBColor+SwiftUI.swift`**

```swift
import AppKit
import MouseCore
import SwiftUI

extension RGBColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    init?(color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        self.init(r: byte(rgb.redComponent), g: byte(rgb.greenComponent), b: byte(rgb.blueComponent))
    }
}
```

- [ ] **Step 2: Write `Sources/MouseBar/Views/SettingsView.swift`**

```swift
import SwiftUI
import MouseCore

struct SettingsView: View {
    let model: AppModel
    @State private var confirmReset = false

    var body: some View {
        Form {
            if let family = model.family {
                ForEach(family.settings) { spec in
                    SettingRow(spec: spec, model: model)
                }
                Section {
                    if let problem = model.problem {
                        Text(problem).foregroundStyle(.red)
                    }
                    Button("Reset to factory defaults", role: .destructive) { confirmReset = true }
                }
            } else {
                Text("Connect a supported mouse to edit its settings.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .confirmationDialog("Reset every setting to the factory default?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.resetAll() }
        }
    }
}
```

- [ ] **Step 3: Write `Sources/MouseBar/Views/SettingRows.swift`**

```swift
import SwiftUI
import MouseCore

struct SettingRow: View {
    let spec: SettingSpec
    let model: AppModel

    var body: some View {
        Section {
            switch spec.valueType {
            case "choice": ChoiceRow(spec: spec, model: model)
            case "range": RangeRow(spec: spec, model: model)
            case "rgbcolor": ColorRow(spec: spec, model: model)
            case "multidpi_range_choice": DPIRow(spec: spec, model: model)
            case "buttons": ButtonsRow(spec: spec, model: model)
            default: EmptyView()
            }
            Text(spec.description).font(.caption).foregroundStyle(.secondary)
        } header: {
            Text(spec.label)
        }
    }
}

private func current(_ spec: SettingSpec, _ model: AppModel) -> SettingValue? {
    model.values[spec.key] ?? DefaultSettings.value(for: spec)
}

struct ChoiceRow: View {
    let spec: SettingSpec
    let model: AppModel

    var body: some View {
        Picker(spec.label, selection: Binding(
            get: {
                if case .choice(let c)? = current(spec, model) { return c }
                return spec.defaultText
            },
            set: { model.submit(spec.key, .choice($0)) }
        )) {
            ForEach(spec.choices ?? [], id: \.key) { choice in
                Text(choice.key).tag(choice.key)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

struct RangeRow: View {
    let spec: SettingSpec
    let model: AppModel
    @State private var draft: Double = 0

    var body: some View {
        let range = spec.inputRange ?? [0, 1, 1]
        HStack {
            Slider(value: $draft, in: Double(range[0])...Double(range[1]), step: Double(range[2])) { editing in
                if !editing { model.submit(spec.key, .int(Int(draft))) }
            }
            Text("\(Int(draft))").monospacedDigit().frame(width: 52, alignment: .trailing)
        }
        .onAppear {
            if case .int(let v)? = current(spec, model) { draft = Double(v) }
        }
        .onChange(of: model.values[spec.key]) { _, new in
            if case .int(let v)? = new { draft = Double(v) }
        }
    }
}

struct ColorRow: View {
    let spec: SettingSpec
    let model: AppModel

    var body: some View {
        ColorPicker(spec.label, selection: Binding(
            get: {
                if case .color(let c)? = current(spec, model) { return c.swiftUIColor }
                return .red
            },
            set: { new in
                if let rgb = RGBColor(color: new) { model.submit(spec.key, .color(rgb)) }
            }
        ), supportsOpacity: false)
        .labelsHidden()
    }
}

struct DPIRow: View {
    let spec: SettingSpec
    let model: AppModel

    private var presets: [Int] {
        if case .dpiPresets(let p, _)? = current(spec, model) { return p }
        return [800]
    }
    private var selected: Int {
        if case .dpiPresets(_, let s)? = current(spec, model) { return s ?? 0 }
        return 0
    }
    private var maxCount: Int { spec.maxPresetCount ?? 5 }
    private var range: ClosedRange<Int> {
        let r = spec.inputRange ?? [100, 18000, 100]
        return r[0]...r[1]
    }
    private var step: Int { (spec.inputRange ?? [100, 18000, 100])[2] }

    private func commit(_ new: [Int], selected: Int) {
        model.submit(spec.key, .dpiPresets(presets: new, selected: min(selected, new.count - 1)))
    }

    var body: some View {
        ForEach(presets.indices, id: \.self) { index in
            Stepper(value: Binding(
                get: { presets[index] },
                set: { value in
                    var next = presets
                    next[index] = value
                    commit(next, selected: selected)
                }
            ), in: range, step: step) {
                Text("Preset \(index + 1): \(presets[index]) DPI")
            }
        }
        HStack {
            Button("Add preset") {
                commit(presets + [min(presets.last ?? 800, range.upperBound)], selected: selected)
            }
            .disabled(presets.count >= maxCount)
            Button("Remove last") {
                commit(Array(presets.dropLast()), selected: selected)
            }
            .disabled(presets.count <= 1)
        }
        // Delete the next 5 lines if Task 8 Step 6 did not confirm that preset selection works.
        Picker("Active preset", selection: Binding(
            get: { selected },
            set: { commit(presets, selected: $0) }
        )) {
            ForEach(presets.indices, id: \.self) { Text("Preset \($0 + 1)").tag($0) }
        }
    }
}

struct ButtonsRow: View {
    let spec: SettingSpec
    let model: AppModel

    private var mapping: ButtonMapping {
        if case .buttons(let m)? = current(spec, model) { return m }
        return ButtonMapping()
    }

    private func actionBinding(_ button: ButtonSpec) -> Binding<String> {
        Binding(
            get: { mapping.assignments[button.name.lowercased()] ?? "default" },
            set: { token in
                var next = mapping.assignments
                next[button.name.lowercased()] = token
                model.submit(spec.key, .buttons(ButtonMapping(assignments: next)))
            }
        )
    }

    private var otherButtons: [String] { (spec.buttons ?? []).map { $0.name.lowercased() } }
    private var specials: [String] {
        var list: [String] = []
        if spec.buttonDisable != nil { list.append("disabled") }
        if spec.buttonDpiSwitch != nil { list.append("dpi") }
        if spec.buttonScrollUp != nil { list.append("scrollup") }
        if spec.buttonScrollDown != nil { list.append("scrolldown") }
        return list
    }

    var body: some View {
        ForEach(spec.buttons ?? [], id: \.name) { button in
            Picker(button.name, selection: actionBinding(button)) {
                Text("Default (\(button.defaultAction))").tag("default")
                Section("Mouse buttons and actions") {
                    ForEach(otherButtons + specials, id: \.self) { Text($0).tag($0) }
                }
                if spec.buttonMultimedia != nil {
                    Section("Media keys") {
                        ForEach(model.layouts.multimediaKeys, id: \.self) { Text($0).tag($0.lowercased()) }
                    }
                }
                if spec.buttonKeyboard != nil {
                    Section("Keyboard keys") {
                        ForEach(model.layouts.keyboardKeys, id: \.self) { Text($0).tag($0.lowercased()) }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Add the menu's quick DPI switch (only if Task 8 Step 6 confirmed preset selection)**

Append to `Sources/MouseBar/Views/SettingRows.swift`:
```swift
struct DPIQuickSwitch: View {
    let model: AppModel

    var body: some View {
        if let spec = model.family?.setting("sensitivity"),
           case .dpiPresets(let presets, let selected)? = model.values[spec.key] ?? DefaultSettings.value(for: spec) {
            Picker("DPI", selection: Binding(
                get: { selected ?? 0 },
                set: { model.submit(spec.key, .dpiPresets(presets: presets, selected: $0)) }
            )) {
                ForEach(presets.indices, id: \.self) { Text("\(presets[$0]) DPI").tag($0) }
            }
        }
    }
}
```
In `Sources/MouseBar/Views/MenuContent.swift`, insert `DPIQuickSwitch(model: model)` on the line after `Text(BatteryPresentation.detail(for: model.battery, now: Date()))`. If preset selection was not confirmed, skip this step and do not add the struct.

- [ ] **Step 5: Build and check in demo mode**

```bash
swift build --arch arm64
Scripts/bundle.sh debug
open build/MouseBar.app --args --demo
```
Open "Settings…" from the menu bar item.
Expected: a window with sections Sensitivity presets (5 steppers, add/remove, active preset if kept), Polling rate (segmented 125/250/500/1000), LED color (color well), Buttons mapping (8 pickers), Sleep timer and Dim timer (sliders), Default lighting (off/rainbow), and the Reset button. Changing a value must not crash; setting `Button 1` to `disabled` must show the red message "noPrimaryClick" style error in the window (the model's `problem`) and leave the previous mapping applied. The visible `problem` text is the check for rejected edits. If Step 4 was done, the menu also shows a DPI submenu with the five presets.

- [ ] **Step 6: Commit**

```bash
git add Sources
git commit -m "feat(app): data-driven settings window" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Final verification, README, hardware checklist

**Hardware:** Steps 4–6 need the Prime Mini Wireless. If it is not available, do Steps 1–3 and 7, tell the user the hardware steps are pending, and do not claim Phase 2 verified.

**Files:**
- Create: `README.md`, `docs/superpowers/notes/2026-10-10-hardware-verification.md`

- [ ] **Step 1: Full test run**

Run: `swift test`
Expected: all tests PASS, zero failures.

- [ ] **Step 2: Architecture check**

```bash
Scripts/bundle.sh release
lipo -archs build/MouseBar.app/Contents/MacOS/MouseBar
file build/MouseBar.app/Contents/MacOS/MouseBar
codesign --verify --verbose build/MouseBar.app
```
Expected: `arm64` only; `Mach-O 64-bit executable arm64`; `valid on disk`. If `x86_64` appears anywhere, fix the build flags before continuing. With the app running, Activity Monitor's "Kind" column must read "Apple" (not "Intel"); this stands in for the spec's `sysctl sysctl.proc_translated` check, which only reports on its own process.

- [ ] **Step 3: Write `README.md`**

```markdown
# MouseBar

A native Apple Silicon menu bar app for SteelSeries mice: battery level at the top right of the screen and the mouse's settings in a window. It does not use SteelSeries GG.

Status: v0.1. Verified on one mouse: **SteelSeries Prime Mini Wireless** (2.4 GHz dongle and USB cable). Other mice are not supported yet.

## Build and run

    Scripts/bundle.sh release
    open build/MouseBar.app

Requires macOS 14+, Xcode 27 or Swift 6.4, and an arm64 Mac. Add `--args --demo` to `open` to try the UI with a simulated mouse.

If SteelSeries GG is installed, quit it first and consider uninstalling it: both programs talk to the same device.

## Settings

DPI presets (up to 5), polling rate, LED color, button remapping, sleep and dim timers, startup lighting, factory reset. Settings are re-applied whenever the mouse connects, and saved to the mouse's own memory at most once, about 2 seconds after your last change.

## Tools

- `swift run hidprobe list | battery | dpi <index>`: diagnose what macOS shows and what the mouse answers.
- `Tools/gen_profiles.py`: regenerates `Sources/MouseCore/Generated/GeneratedProfiles.swift` and the test vectors from rivalcfg 4.17.0 (`python3 -m venv .venv && .venv/bin/pip install -r Tools/requirements.txt && .venv/bin/python -I Tools/gen_profiles.py`).

## Credits

The mouse protocol comes from [rivalcfg](https://github.com/flozz/rivalcfg) by Fabien LOISON (flozz), licensed WTFPL. This project is unofficial and not affiliated with SteelSeries.
```

- [ ] **Step 4: Run the hardware checklist on the real mouse**

Run `build/MouseBar.app` normally (no `--demo`), with the dongle plugged in and SteelSeries GG's engine **not** running (`pgrep -x SteelSeriesEngine` prints nothing).

| Action in MouseBar | Expected on the mouse / screen |
|---|---|
| Launch | Menu bar shows a battery icon and a percentage within about 5 seconds, within 5 points of `~/rivalcfg/rivalcfg --battery-level` |
| Settings → Polling rate 125, then 1000 | Command succeeds; no error text. (Judge with any mouse-rate test page if available) |
| Settings → LED color to blue, then green | Mouse LED changes immediately |
| Settings → Sensitivity preset 1 to 3200 and press the mouse's DPI button | Pointer speed changes between presets |
| Settings → Buttons: button 4 → PlayPause, button 5 → VolumeUp | Side buttons now control media / volume |
| Settings → Buttons: Button 1 → disabled | Window shows the rejection message; left click still works |
| Settings → Sleep timer 1 min, leave the mouse still 70 s, move it | After two missed polls the menu shows "mouse asleep"; after waking the label returns to a fresh percentage |
| Quit and relaunch | Chosen LED color and settings are applied again without opening Settings |
| Unplug the dongle | Menu bar icon switches to the plain mouse symbol and "No mouse connected"; replug restores it |
| Plug the USB cable (dongle also in) | Menu shows the "(wired mode)" model name; the battery shows charging (bolt icon) |
| Pull the cable out | App falls back to the dongle model without relaunch |

Record each row as pass/fail with the observed value in `docs/superpowers/notes/2026-10-10-hardware-verification.md`.

- [ ] **Step 5: Check the save really reached the mouse's memory**

rivalcfg's protocol cannot read settings back, so test it by behavior without MouseBar running:
1. In Settings set **Default lighting** to `off` and DPI preset 1 to 3200 (active preset 1). Wait 3 seconds so the debounced save fires. Quit MouseBar.
2. Power-cycle the mouse (switch it off and on, or unplug and replug the cable and dongle). Do **not** launch MouseBar.
3. Expected: the mouse starts with its LED off instead of the rainbow, and the pointer is fast at preset 1. Both come from the mouse's own memory.
4. Launch MouseBar again and set Default lighting back to `rainbow`.

Record both observations. If the LED comes back as a rainbow, the save command did not persist that setting on this model; note it in the verification file and tell the user.

- [ ] **Step 6: Run the GG coexistence check**

Start SteelSeries GG so `SteelSeriesEngine` runs, launch MouseBar.
Expected: the menu shows "SteelSeries GG is running and may fight over the mouse." MouseBar keeps working or shows an error, but does not crash, and does not kill GG.

- [ ] **Step 7: Commit**

```bash
git add README.md docs
git commit -m "docs: README and hardware verification notes" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Report**

Tell the user, in plain words: which checklist rows passed, which failed, which were skipped for lack of hardware, and whether preset selection worked. Do not say Phase 2 is verified unless Step 4 and Step 5 were run on real hardware.
