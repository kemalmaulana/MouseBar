# Hardware Check Wizard + UI Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an in-app Hardware Check wizard that verifies MouseBar's writes on the owner's real mouse and restores their settings, and refine the whole UI (menu bar panel, toolbar-tab Settings, friendly names, native theme, accessibility).

**Architecture:** `MouseCore` gains a few session/device APIs (transient writes, save-now with progress reporting, poll interval, raw battery query, HID logging) and pure hardware-check models (step ids, outcomes, report, polling-rate estimator, restore snapshot). `MouseBar` gains a design system (`Theme` + shared components), friendly-name tables, a `CheckRunner` that scripts each step against the live `MouseSession`, the wizard window, the `.window`-style menu bar panel, and a `Settings`-scene `TabView` whose pages are generated from the profile through an app-side layout table.

**Tech Stack:** Swift 6.4 / Xcode 27, SwiftPM only, SwiftUI (macOS 14+: `MenuBarExtra(.window)`, `Settings`, `TabView`, `Gauge`, `ContentUnavailableView`, `@Observable`/`@Bindable`), AppKit (`NSViewRepresentable` event capture), `os.Logger`.

**Specs:**
- `docs/superpowers/specs/2026-10-10-hardware-check-wizard-design.md`
- `docs/superpowers/specs/2026-10-10-ui-refinement-design.md`

## Global Constraints

- arm64-only, macOS 14+, SwiftPM. `MouseCore` stays Swift 6 language mode, strict-concurrency clean. Build must have **zero warnings**.
- **No new unit tests and no TDD** (owner's decision). Verification per task: `swift build --arch arm64` (0 warnings), the existing suite `swift test` still passes (106 tests), and for app tasks a `--demo` launch with no crash.
- Native identity: system accent color, system materials, light/dark follow macOS, SF Pro text styles only (no fixed font sizes for text), `.monospacedDigit()` for numbers, SF Mono for hex codes. Spacing 4/8/12/16/24, radius 10, window padding 20, hit targets ≥ 28 pt.
- Color is never the only signal: every status pairs color with an SF Symbol and a word.
- Every icon/control has an accessibility label; decorative symbols are hidden; default focus rings kept; Reduce Motion disables animations.
- The wizard uses the app's live `MouseSession`/`MouseDevice` only (no second connection). Test writes are transient (never stored). Button validation stays in force. Restore runs on finish, Cancel, window close, quit (5 s bound) and next launch.
- Commands to the mouse stay ≥ 50 ms apart (existing `MouseDevice` FIFO lock).
- **Safety while implementing:** a real mouse is attached and its owner may be running the real MouseBar. Never launch MouseBar without `--demo`. Never run `hidprobe` or rivalcfg. Never `pkill -x MouseBar` / `killall`: record `pgrep -x MouseBar` before launching a demo, kill only the new PID. Never touch `~/Library/Application Support/MouseBar`.
- Commit trailer on every commit: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Never commit `.DS_Store`, `build/`, `.superpowers/`.
- On this toolchain `if a < b, c > d` mis-parses as generics; use `&&`. In files that import AppKit, write `MouseCore.RGBColor` (AppKit has a QuickDraw `RGBColor`); new code always writes `MouseCore.RGBColor`.

## Review Focus

No tests are written, so reviewers must check these by reading the code:

1. **Quit, crash or window close in the middle of the check** → the owner's settings are restored (now, or at next launch when the mouse connects); the snapshot file is deleted only after a fully successful restore. [Tasks 5, 6]
2. **Connection switch during the check** (cable → dongle) → `AppModel` creates a new session; the runner always uses `model.activeSession` at the moment it acts and the new session gets the 5 s poll interval. [Tasks 3, 5]
3. **Owner never stored a value the check touches** → restore writes the factory default for it (and the owner's entered DPI presets/buttons), never leaves a test value (blue LED, 125 Hz, F18 on button 4, 400/3200 DPI, lighting off) on the mouse. [Tasks 2, 5]
4. **No or too little mouse movement in the capture box / no key press** → the step fails with a clear message; nothing hangs (key wait times out after 15 s, waits after 2 min). [Tasks 5, 6]
5. **Settings edited while the check runs** → Settings and the panel's quick controls are disabled while `isCheckRunning`. [Tasks 7, 8]

## File Structure

```
Sources/MouseCore/
  SaveState.swift                         # SaveState + SaveReporter (Task 1)
  MouseSession.swift                      # + setSaveObserver, applyTransient, saveNow, setPollInterval, rawBatteryQuery (Task 1)
  MouseDevice.swift                       # + rawBatteryQuery, os.Logger HID logging (Task 1)
  BatteryMonitor.swift                    # interval becomes settable (Task 1)
  HardwareCheck/CheckStep.swift           # CheckStepID, StepResult, StepOutcome, HexFormat (Task 2)
  HardwareCheck/CheckReport.swift         # CheckReport + markdown (Task 2)
  HardwareCheck/PollingRateEstimator.swift (Task 2)
  HardwareCheck/RestoreSnapshot.swift     # snapshot file + restore write list (Task 2)
Sources/MouseBar/
  Theme.swift                             # tokens, symbols, battery color (Task 3)
  Components/StatusBanner.swift, DefaultCapsule.swift, SaveStatusLine.swift (Task 3)
  AppModel.swift                          # + connection, saveState, notice, isCheckRunning, activePresetConfirmed... (Task 3, edited in 5)
  Names/SettingsLayout.swift              # tabs, key -> tab/order/label, ValueFormat (Task 4)
  Names/ButtonNames.swift                 # friendly button/action names (Task 4)
  Components/ButtonActionMenu.swift       # action menu + keyboard key popover (Task 4)
  HardwareCheck/CheckRunner.swift         # step scripts, restore, report (Task 5)
  AppDelegate.swift                       # quit restore (Task 5)
  HardwareCheck/EventCaptureBox.swift     # NSView capture of mouse moves / key (Task 6)
  HardwareCheck/CheckWindow.swift, CheckStepCard.swift, CheckPreflightView.swift, CheckResultsView.swift (Task 6)
  Components/LEDSwatches.swift            # (Task 7)
  Views/BatteryLabel.swift                # refined (Task 7)
  Views/MenuPanel.swift                   # replaces Views/MenuContent.swift (Task 7)
  Views/SettingsView.swift                # TabView pages (Task 8)
  Views/SettingEditors.swift              # SettingSection, SettingEditor, DPIEditor, ChoiceEditor, RangeEditor (Task 8)
  Views/DeviceTab.swift                   # (Task 8)
  Views/ButtonsEditor.swift, MouseDiagram.swift (Task 9)
  Views/ColorEditor.swift                 # (Task 10); Views/SettingRows.swift deleted (Task 10)
  MouseBarApp.swift                       # scenes (Tasks 6, 7, 8)
```

## Demo-launch procedure (used by app tasks)

```bash
cd /Users/maulana/XcodeProjects/Steelseries
Scripts/bundle.sh debug
BEFORE="$(pgrep -x MouseBar | sort)"
open -n build/MouseBar.app --args --demo
sleep 4
NEW="$(comm -13 <(echo "$BEFORE") <(pgrep -x MouseBar | sort))"
echo "demo pid: $NEW"
sleep 3
pgrep -x MouseBar | grep -q "^$NEW$" && echo "demo still running after 7 s"
ls -t ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i mousebar | head -3
kill "$NEW"
```
Expected: `archs: arm64`, one new pid, "demo still running after 7 s", no new MouseBar crash report. If `sleep` is unavailable in your shell, wait the same time with any other non-interactive method. Never kill a pid that was in `$BEFORE`.

---

### Task 1: MouseCore session and device APIs

**Files:**
- Create: `Sources/MouseCore/SaveState.swift`
- Modify: `Sources/MouseCore/MouseSession.swift`, `Sources/MouseCore/MouseDevice.swift`, `Sources/MouseCore/BatteryMonitor.swift`

**Interfaces:**
- Produces:
  - `public enum SaveState: Equatable, Sendable { case saving, saved, failed(String) }`
  - `MouseSession.setSaveObserver(_ observer: (@Sendable (SaveState) async -> Void)?) async`
  - `MouseSession.applyTransient(_ key: String, _ value: SettingValue) async throws` (validate + write; no store, no save)
  - `MouseSession.saveNow() async throws` (reports `.saving` → `.saved` / `.failed`, rethrows)
  - `MouseSession.setPollInterval(_ interval: Duration) async`
  - `MouseSession.rawBatteryQuery() async throws -> [UInt8]?` and `MouseDevice.rawBatteryQuery() async throws -> [UInt8]?`
  - `BatteryMonitor.setInterval(_ interval: Duration)`
  - debug log of every HID write/read: `Logger(subsystem: "dev.mousebar.MouseBar", category: "hid")`

- [ ] **Step 1: Create `Sources/MouseCore/SaveState.swift`**

```swift
/// Progress of a save to the mouse's own memory, reported to the app for feedback.
public enum SaveState: Equatable, Sendable {
    case saving
    case saved
    case failed(String)
}

/// Holds the app's save observer (set after the session is created) and runs saves through it.
actor SaveReporter {
    private var observer: (@Sendable (SaveState) async -> Void)?

    func setObserver(_ observer: (@Sendable (SaveState) async -> Void)?) {
        self.observer = observer
    }

    /// Runs one save, reporting `.saving` then `.saved` or `.failed`, and rethrows the failure.
    func run(_ save: @Sendable () async throws -> Void) async throws {
        await observer?(.saving)
        do {
            try await save()
            await observer?(.saved)
        } catch {
            await observer?(.failed(String(describing: error)))
            throw error
        }
    }
}
```

- [ ] **Step 2: Make the battery poll interval settable in `Sources/MouseCore/BatteryMonitor.swift`**

In `public actor BatteryMonitor`, change `private let interval: Duration` to `private var interval: Duration` and add this method right after `init`:

```swift
    /// Takes effect at the next sleep of the polling loop.
    public func setInterval(_ interval: Duration) {
        self.interval = interval
    }
```
`run` already reads `interval` on every loop iteration; leave it as is.

- [ ] **Step 3: Add the raw query and HID logging to `Sources/MouseCore/MouseDevice.swift`**

At the top of the file add:
```swift
import Foundation
import os
```
Inside `public actor MouseDevice`, after `public static let replyTimeout`, add:
```swift
    private static let log = Logger(subsystem: "dev.mousebar.MouseBar", category: "hid")

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
```
In `readBattery()`, right after the `guard let reply = try await connection.read(...) else { return nil }` line, add:
```swift
                Self.log.debug("read \(Self.hex(reply), privacy: .public)")
```
Add this method after `readBattery()`:
```swift
    /// The first report answering a battery query, raw: no decoding, no echo filter (hardware check diagnostics).
    public func rawBatteryQuery() async throws -> [UInt8]? {
        try await exclusive {
            guard let battery = family.battery else { return nil }
            await connection.flushInput()
            try await send(Bytes.u8(battery.command), readback: 0)
            let reply = try await connection.read(length: 64, timeout: Self.replyTimeout)
            if let reply { Self.log.debug("raw battery reply \(Self.hex(reply), privacy: .public)") }
            return reply
        }
    }
```
Replace the body of `send(_:readback:)` with:
```swift
        do {
            try await connection.write(payload)
        } catch {
            Self.log.debug("write failed, retrying \(Self.hex(payload), privacy: .public)")
            await sleeper.sleep(for: Self.commandDelay)
            try await connection.write(payload)
        }
        Self.log.debug("write \(Self.hex(payload), privacy: .public)")
        await sleeper.sleep(for: Self.commandDelay)
        if readback > 0, let reply = try? await connection.read(length: readback, timeout: Self.replyTimeout) {
            Self.log.debug("readback \(Self.hex(reply), privacy: .public)")
        }
```

- [ ] **Step 4: Add the session APIs to `Sources/MouseCore/MouseSession.swift`**

1. Add stored properties after `private var onError: ...`:
```swift
    private let saveReporter: SaveReporter
    private var batteryWatcher: (@Sendable (BatteryState) async -> Void)?
```
2. In `init`, replace
```swift
        let device = mouse.device
        self.debouncer = SaveDebouncer(delay: saveDelay, sleeper: sleeper) {
            try? await device.save()
        }
```
with
```swift
        let device = mouse.device
        let reporter = SaveReporter()
        self.saveReporter = reporter
        self.debouncer = SaveDebouncer(delay: saveDelay, sleeper: sleeper) {
            try? await reporter.run { try await device.save() }
        }
```
3. In `start`, replace `monitorTask = Task { await monitor.run(watched) }` with:
```swift
        batteryWatcher = watched
        monitorTask = Task { await monitor.run(watched) }
```
4. In `stop()`, add `batteryWatcher = nil` after `monitorTask = nil`.
5. Add these public methods after `flush()`:
```swift
    /// Receives `.saving` / `.saved` / `.failed` for every save to the mouse (debounced or `saveNow`).
    public func setSaveObserver(_ observer: (@Sendable (SaveState) async -> Void)?) async {
        await saveReporter.setObserver(observer)
    }

    /// Validates and writes one value to the mouse without remembering it or scheduling a save.
    /// Used by the hardware check for test writes that are undone afterwards.
    public func applyTransient(_ key: String, _ value: SettingValue) async throws {
        guard let spec = mouse.family.setting(key) else { throw MouseCoreError.unknownSetting(key) }
        try validate(spec, value)
        try await mouse.device.apply(key, value)
    }

    /// Saves the mouse's current configuration to its memory now, reporting progress like the debounced save.
    public func saveNow() async throws {
        let device = mouse.device
        try await saveReporter.run { try await device.save() }
    }

    /// Changes how often the battery is polled; restarts the loop so the new interval applies at once.
    public func setPollInterval(_ interval: Duration) async {
        await monitor.setInterval(interval)
        guard let watched = batteryWatcher, monitorTask != nil else { return }
        monitorTask?.cancel()
        let monitor = self.monitor
        monitorTask = Task { await monitor.run(watched) }
    }

    /// The raw battery reply (hardware check diagnostics).
    public func rawBatteryQuery() async throws -> [UInt8]? {
        try await mouse.device.rawBatteryQuery()
    }
```

- [ ] **Step 5: Build and run the existing suite**

Run: `swift build --arch arm64 2>&1 | grep -E "warning|error" ; swift test 2>&1 | tail -3`
Expected: no `warning`/`error` lines; `Test run with 106 tests in 13 suites passed`.

- [ ] **Step 6: Commit**

```bash
git add Sources/MouseCore
git commit -m "feat(core): save progress, transient writes, poll interval, raw battery query, HID logging" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Hardware check models (MouseCore)

**Files:**
- Create: `Sources/MouseCore/HardwareCheck/CheckStep.swift`, `CheckReport.swift`, `PollingRateEstimator.swift`, `RestoreSnapshot.swift`

**Interfaces:**
- Consumes: `SettingValue`, `ButtonMapping`, `DeviceFamily`, `DefaultSettings` (existing)
- Produces:
  - `public enum CheckStepID: String, CaseIterable, Codable, Sendable { case preflight, batteryCable, batteryDongle, ledColor, pollingRate, buttons, dpiPreset, savePersistence, wakeReapply }` with `public var title: String`
  - `public enum StepResult: String, Codable, Sendable { case pass, fail, skipped }` with `public var word: String`
  - `public struct StepOutcome: Codable, Sendable, Equatable { step, result, detail, rawHex: String?, measurements: [String: Double] }` + `init(step:result:detail:rawHex:measurements:)` (last two default `nil` / `[:]`)
  - `public enum HexFormat { static func string(_ bytes: [UInt8]) -> String }`
  - `public struct CheckReport { date, appVersion, mouseModel, outcomes; func markdown() -> String }`
  - `public enum PollingRateEstimator { static func rate(timestamps: [Double]) -> Double? }`
  - `public struct RestoreSnapshot: Codable, Sendable, Equatable { mouse, stored, dpiPresets, buttons; static fileURL(in:); write(to:) throws; static read(from:) -> RestoreSnapshot?; restoreWrites(family:) -> [(key: String, value: SettingValue)] }`

- [ ] **Step 1: Create `Sources/MouseCore/HardwareCheck/CheckStep.swift`**

```swift
import Foundation

/// The hardware check's steps, in the order they run.
public enum CheckStepID: String, CaseIterable, Codable, Sendable {
    case preflight, batteryCable, batteryDongle, ledColor, pollingRate, buttons, dpiPreset, savePersistence, wakeReapply

    public var title: String {
        switch self {
        case .preflight: "Before you start"
        case .batteryCable: "Battery over the cable"
        case .batteryDongle: "Battery over the dongle"
        case .ledColor: "LED color"
        case .pollingRate: "Polling rate"
        case .buttons: "Button remapping"
        case .dpiPreset: "DPI and active preset"
        case .savePersistence: "Saving to the mouse"
        case .wakeReapply: "LED color after wake"
        }
    }
}

public enum StepResult: String, Codable, Sendable {
    case pass, fail, skipped

    public var word: String {
        switch self {
        case .pass: "Passed"
        case .fail: "Failed"
        case .skipped: "Skipped"
        }
    }
}

public struct StepOutcome: Codable, Sendable, Equatable {
    public var step: CheckStepID
    public var result: StepResult
    public var detail: String
    public var rawHex: String?
    public var measurements: [String: Double]

    public init(
        step: CheckStepID, result: StepResult, detail: String,
        rawHex: String? = nil, measurements: [String: Double] = [:]
    ) {
        self.step = step
        self.result = result
        self.detail = detail
        self.rawHex = rawHex
        self.measurements = measurements
    }
}

public enum HexFormat {
    /// `[0x92, 0x94]` -> `"92 94"`.
    public static func string(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
```

- [ ] **Step 2: Create `Sources/MouseCore/HardwareCheck/CheckReport.swift`**

```swift
import Foundation

public struct CheckReport: Codable, Sendable {
    public var date: Date
    public var appVersion: String
    public var mouseModel: String
    public var outcomes: [StepOutcome]

    public init(date: Date, appVersion: String, mouseModel: String, outcomes: [StepOutcome]) {
        self.date = date
        self.appVersion = appVersion
        self.mouseModel = mouseModel
        self.outcomes = outcomes
    }

    /// The report as Markdown, ready to commit to docs/superpowers/notes/.
    public func markdown() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        var lines = [
            "# MouseBar hardware check",
            "",
            "- Date: \(formatter.string(from: date))",
            "- App version: \(appVersion)",
            "- Mouse: \(mouseModel)",
            "",
            "| Step | Result | Detail |",
            "|---|---|---|",
        ]
        for outcome in outcomes {
            let detail = outcome.detail.replacingOccurrences(of: "|", with: "/")
            lines.append("| \(outcome.step.title) | \(outcome.result.word) | \(detail) |")
        }
        let raw = outcomes.filter { $0.rawHex != nil }
        if !raw.isEmpty {
            lines += ["", "## Raw replies", ""]
            for outcome in raw {
                lines.append("- \(outcome.step.title): `\(outcome.rawHex ?? "")`")
            }
        }
        let measured = outcomes.filter { !$0.measurements.isEmpty }
        if !measured.isEmpty {
            lines += ["", "## Measurements", ""]
            for outcome in measured {
                let parts = outcome.measurements
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key) = \(String(format: "%.1f", $0.value))" }
                lines.append("- \(outcome.step.title): \(parts.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
```

- [ ] **Step 3: Create `Sources/MouseCore/HardwareCheck/PollingRateEstimator.swift`**

```swift
public enum PollingRateEstimator {
    /// Events per second from event timestamps in seconds: 1 / the median interval between consecutive events,
    /// ignoring zero intervals and gaps longer than 100 ms (the mouse paused). `nil` with fewer than 10 usable intervals.
    public static func rate(timestamps: [Double]) -> Double? {
        let sorted = timestamps.sorted()
        let intervals = zip(sorted.dropFirst(), sorted)
            .map { $0 - $1 }
            .filter { $0 > 0 && $0 <= 0.1 }
        guard intervals.count >= 10 else { return nil }
        let median = intervals.sorted()[intervals.count / 2]
        return 1 / median
    }
}
```

- [ ] **Step 4: Create `Sources/MouseCore/HardwareCheck/RestoreSnapshot.swift`**

```swift
import Foundation

/// What the hardware check puts back: the settings MouseBar stored before the check, plus the DPI presets and
/// button remaps the owner entered (the mouse cannot report them). Written to disk before the first test write.
public struct RestoreSnapshot: Codable, Sendable, Equatable {
    /// The mouse group id (`DeviceModel.mouse`), so a snapshot is only restored to the same physical mouse.
    public var mouse: String
    public var stored: [String: SettingValue]
    public var dpiPresets: [Int]
    public var buttons: ButtonMapping

    public init(mouse: String, stored: [String: SettingValue], dpiPresets: [Int], buttons: ButtonMapping) {
        self.mouse = mouse
        self.stored = stored
        self.dpiPresets = dpiPresets
        self.buttons = buttons
    }

    public static let fileName = "check-restore.json"

    public static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// `nil` when the file is missing or unreadable.
    public static func read(from url: URL) -> RestoreSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RestoreSnapshot.self, from: data)
    }

    /// The writes that put the mouse back, in this order: the owner's buttons, the owner's DPI presets, then every
    /// other setting the check touches (the stored value, or the factory default when MouseBar never stored one).
    public func restoreWrites(family: DeviceFamily) -> [(key: String, value: SettingValue)] {
        var writes: [(key: String, value: SettingValue)] = []
        if family.setting("buttons_mapping") != nil {
            writes.append((key: "buttons_mapping", value: .buttons(buttons)))
        }
        if family.setting("sensitivity") != nil, !dpiPresets.isEmpty {
            writes.append((key: "sensitivity", value: .dpiPresets(presets: dpiPresets, selected: nil)))
        }
        for key in ["polling_rate", "color", "default_lighting"] {
            guard let spec = family.setting(key) else { continue }
            if let value = stored[key] ?? DefaultSettings.value(for: spec) {
                writes.append((key: key, value: value))
            }
        }
        return writes
    }
}
```

- [ ] **Step 5: Build and run the existing suite**

Run: `swift build --arch arm64 2>&1 | grep -E "warning|error" ; swift test 2>&1 | tail -3`
Expected: no warnings/errors; 106 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/MouseCore/HardwareCheck
git commit -m "feat(core): hardware check steps, report, polling estimator, restore snapshot" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Theme, shared components, AppModel state

**Files:**
- Create: `Sources/MouseBar/Theme.swift`, `Sources/MouseBar/Components/StatusBanner.swift`, `Sources/MouseBar/Components/DefaultCapsule.swift`, `Sources/MouseBar/Components/SaveStatusLine.swift`
- Replace: `Sources/MouseBar/AppModel.swift`

**Interfaces:**
- Consumes: `SaveState`, `MouseSession.setSaveObserver` (Task 1)
- Produces:
  - `enum Theme` (`Space.xs/s/m/l/xl`, `radius`, `windowPadding`, `minHitTarget`, `animation`, `batteryColor(level:)`, `Symbol.*`) and `View.themedAnimation(_:reduceMotion:)`
  - `StatusBanner(style: .info | .warning | .error, message:, actionTitle:, action:, onDismiss:)`, `DefaultCapsule()`, `SaveStatusLine(state: SaveState?)`
  - `AppModel`: `static isDemo`, `ConnectionKind` (`.cable`/`.dongle`, `title`, `symbol`), `connection`, `saveState`, `notice`, `isCheckRunning`, `activePresetConfirmed` + `setActivePresetConfirmed(_:)`, `settingsDirectory`, `displayName`, `rivalcfgVersion`, `activeSession`, `refreshValues()`, `static shortName(_:)`

- [ ] **Step 1: Create `Sources/MouseBar/Theme.swift`**

```swift
import SwiftUI
import MouseCore

/// Design tokens (docs/superpowers/specs/2026-10-10-ui-refinement-design.md, section 2).
enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    static let radius: CGFloat = 10
    static let windowPadding: CGFloat = 20
    static let minHitTarget: CGFloat = 28
    static let animation: Animation = .easeInOut(duration: 0.22)

    /// Battery level tint. Never the only signal: always shown with a symbol and the percentage or a word.
    static func batteryColor(level: Int?) -> Color {
        guard let level else { return .secondary }
        if level < 15 { return .red }
        if level <= 40 { return .orange }
        return .green
    }

    enum Symbol {
        static let charging = "bolt.fill"
        static let cable = "cable.connector"
        static let dongle = "antenna.radiowaves.left.and.right"
        static let asleep = "moon.zzz.fill"
        static let low = "battery.0percent"
        static let warning = "exclamationmark.triangle.fill"
        static let error = "xmark.octagon.fill"
        static let info = "info.circle.fill"
        static let pass = "checkmark.circle.fill"
        static let fail = "xmark.circle.fill"
        static let skipped = "minus.circle"
        static let notRun = "circle.dashed"
        static let mouse = "computermouse"
    }
}

extension View {
    /// The theme's transition animation, or none when Reduce Motion is on.
    func themedAnimation<V: Equatable>(_ value: V, reduceMotion: Bool) -> some View {
        animation(reduceMotion ? nil : Theme.animation, value: value)
    }
}
```

- [ ] **Step 2: Create `Sources/MouseBar/Components/StatusBanner.swift`**

```swift
import SwiftUI

/// An inline message with an icon, a word-bearing accessibility label, an optional action and dismiss.
struct StatusBanner: View {
    enum Style { case info, warning, error }

    let style: Style
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    private var symbol: String {
        switch style {
        case .info: Theme.Symbol.info
        case .warning: Theme.Symbol.warning
        case .error: Theme.Symbol.error
        }
    }

    private var tint: Color {
        switch style {
        case .info: .accentColor
        case .warning: .orange
        case .error: .red
        }
    }

    private var word: String {
        switch style {
        case .info: "Note"
        case .warning: "Warning"
        case .error: "Error"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityLabel(word)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(Theme.Space.m)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radius))
        .accessibilityElement(children: .contain)
    }
}
```

- [ ] **Step 3: Create `Sources/MouseBar/Components/DefaultCapsule.swift`**

```swift
import SwiftUI

/// Marks a setting MouseBar has never set: the mouse can't report its value, so the UI shows the factory default.
struct DefaultCapsule: View {
    var body: some View {
        Text("Default")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .help("The mouse can't report its settings. This shows the factory default; changing it writes it to the mouse.")
            .accessibilityLabel("Factory default, not set by MouseBar")
    }
}
```

- [ ] **Step 4: Create `Sources/MouseBar/Components/SaveStatusLine.swift`**

```swift
import SwiftUI
import MouseCore

/// "Saving to mouse…" while a save runs, "Saved to mouse" briefly afterwards, nothing otherwise.
/// A failed save is shown by AppModel as an error banner instead.
struct SaveStatusLine: View {
    let state: SaveState?

    var body: some View {
        Group {
            switch state {
            case .saving?:
                HStack(spacing: Theme.Space.xs) {
                    ProgressView().controlSize(.mini)
                    Text("Saving to mouse…")
                }
            case .saved?:
                Label("Saved to mouse", systemImage: Theme.Symbol.pass)
                    .foregroundStyle(.green)
            default:
                EmptyView()
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 5: Replace `Sources/MouseBar/AppModel.swift`**

```swift
import Foundation
import MouseCore
import MouseHID
import Observation

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    static let isDemo = CommandLine.arguments.contains("--demo")
    private static let activePresetKey = "activePresetConfirmed"

    enum ConnectionKind: Equatable {
        case cable, dongle

        var title: String { self == .cable ? "Cable" : "2.4 GHz" }
        var symbol: String { self == .cable ? Theme.Symbol.cable : Theme.Symbol.dongle }
    }

    var battery: BatteryState = .disconnected
    var mouseName: String?
    var family: DeviceFamily?
    var values: [String: SettingValue] = [:]
    var problem: String?
    var notice: String?
    var ggWarning = false
    var connection: ConnectionKind?
    var saveState: SaveState?
    /// True while the hardware check runs; Settings and the panel's quick controls are disabled.
    var isCheckRunning = false
    /// Set by the hardware check when switching the active DPI preset was confirmed on the mouse.
    private(set) var activePresetConfirmed: Bool
    let layouts: ButtonLayouts
    let settingsDirectory: URL

    private let catalog: ProfileCatalog
    private let store: SettingsStore
    private var manager: DeviceManager?
    private var session: MouseSession?
    private var activeID: UInt64?
    private var available: [ConnectedMouse] = []
    private var started = false
    /// The latest resync per setting key; a newer edit of the same key cancels the older waiter.
    private var resyncTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var saveClearTask: Task<Void, Never>?

    private init() {
        // Generated and unit-tested data; failing to decode it is a programming error.
        catalog = try! ProfileCatalog.load()
        layouts = try! ButtonLayouts.load()
        // Demo edits must never reach the real store: the demo device shares the real mouse's group id,
        // so they would be re-applied to the real mouse on the next normal launch.
        let directory = Self.isDemo
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("mousebar-demo-\(UUID().uuidString)", isDirectory: true)
            : SettingsStore.defaultDirectory()
        settingsDirectory = directory
        store = SettingsStore(directory: directory)
        activePresetConfirmed = Self.isDemo ? false : UserDefaults.standard.bool(forKey: Self.activePresetKey)
    }

    /// "SteelSeries Prime Mini Wireless (2.4 GHz wireless mode)" -> "Prime Mini Wireless".
    var displayName: String? { mouseName.map(Self.shortName) }
    var rivalcfgVersion: String { catalog.rivalcfgVersion }
    /// The session of the active mouse (the hardware check drives it directly).
    var activeSession: MouseSession? { session }

    static func shortName(_ name: String) -> String {
        var result = name
        if let paren = result.firstIndex(of: "(") {
            result = String(result[..<paren]).trimmingCharacters(in: .whitespaces)
        }
        if result.hasPrefix("SteelSeries ") {
            result.removeFirst("SteelSeries ".count)
        }
        return result
    }

    func setActivePresetConfirmed(_ confirmed: Bool) {
        activePresetConfirmed = confirmed
        // A demo run must not unlock the DPI picker for the real mouse.
        if !Self.isDemo { UserDefaults.standard.set(confirmed, forKey: Self.activePresetKey) }
    }

    func refreshValues() async {
        values = await session?.currentValues ?? [:]
    }

    func start() {
        guard !started else { return }
        started = true
        ggWarning = GGDetector.isEngineRunning()
        let transport: any HIDTransport = Self.isDemo ? DemoTransport.make() : IOHIDTransport()
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
        for task in resyncTasks.values { task.cancel() }
        resyncTasks = [:]
        await session?.stop()
        session = nil
        activeID = chosen?.hidID
        values = [:]
        problem = nil
        saveState = nil
        guard let chosen else {
            battery = .disconnected
            mouseName = nil
            family = nil
            connection = nil
            return
        }
        battery = .connecting
        mouseName = chosen.model.name
        family = chosen.family
        connection = chosen.model.isWireless ? .dongle : .cable
        let session = MouseSession(
            mouse: chosen, store: store, encoder: SettingEncoder(layouts: layouts), sleeper: SystemSleeper()
        )
        self.session = session
        let id = chosen.hidID
        await session.setSaveObserver { [weak self] state in await self?.setSaveState(state, from: id) }
        let errors = await session.start(
            onBattery: { [weak self] state in await self?.setBattery(state, from: id) },
            onError: { [weak self] message in await self?.setProblem(message, from: id) }
        )
        values = await session.currentValues
        if !errors.isEmpty { problem = errors.joined(separator: "\n") }
    }

    // A stopped session can still deliver an already-queued callback; only the active mouse may update the UI.
    private func setBattery(_ state: BatteryState, from id: UInt64) {
        guard id == activeID else { return }
        battery = state
    }

    private func setProblem(_ message: String, from id: UInt64) {
        guard id == activeID else { return }
        problem = message
    }

    private func setSaveState(_ state: SaveState, from id: UInt64) {
        guard id == activeID else { return }
        saveClearTask?.cancel()
        switch state {
        case .saving:
            saveState = .saving
        case .saved:
            saveState = .saved
            saveClearTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.saveState = nil
            }
        case .failed(let message):
            saveState = nil
            problem = "Could not save to the mouse: \(message)"
        }
    }

    func submit(_ key: String, _ value: SettingValue) {
        // Clicking the selected segment or a slider without moving it must not write to the mouse or schedule a save.
        if values[key] != nil && values[key] == value { return }
        problem = nil
        // Optimistic, so controls respond at once; resynced below if the session rejects the edit.
        values[key] = value
        guard let session, let id = activeID else { return }
        resyncTasks[key]?.cancel()
        resyncTasks[key] = Task {
            await session.submit(key, value)
            await session.waitUntilIdle()
            guard !Task.isCancelled else { return }       // a newer edit of this key owns the resync now
            let accepted = await session.currentValues[key]
            // Only this key, only if the mouse is still the active one and no newer optimistic edit landed.
            guard id == activeID && values[key] == value else { return }
            values[key] = accepted
        }
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

- [ ] **Step 6: Build, run the suite, demo launch**

Run: `swift build --arch arm64 2>&1 | grep -E "warning|error" ; swift test 2>&1 | tail -3`, then the **Demo-launch procedure**.
Expected: no warnings/errors; 106 pass; demo runs 7 s with no crash.

- [ ] **Step 7: Commit**

```bash
git add Sources/MouseBar
git commit -m "feat(app): theme tokens, banner/capsule/save-status components, app model state for check and panel" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Friendly names, settings layout, button action menu

**Files:**
- Create: `Sources/MouseBar/Names/SettingsLayout.swift`, `Sources/MouseBar/Names/ButtonNames.swift`, `Sources/MouseBar/Components/ButtonActionMenu.swift`

**Interfaces:**
- Consumes: `SettingSpec`, `ButtonSpec`, `DeviceFamily`, `ButtonLayouts`, `Theme` (Task 3)
- Produces:
  - `enum SettingsTab: String, CaseIterable, Identifiable { case performance, buttons, lighting, power, device }` with `title`, `symbol`
  - `enum SettingsLayout { static func settings(for: SettingsTab, in: DeviceFamily) -> [SettingSpec]; static func otherSettings(in:) -> [SettingSpec]; static func label(for: SettingSpec) -> String }`
  - `enum ValueFormat { static func dpi(_:) ; static func choice(key:_:) ; static func range(key:value:) ; static func seconds(_:) }`
  - `enum ButtonNames { static func name(_ button: String) -> String; static func actionName(_ token: String) -> String; static func mouseActions(for spec: SettingSpec) -> [String] }`
  - `ButtonActionMenu(spec:button:token:layouts:onChange:)` and `KeyPickerPopover(keys:onPick:)`

- [ ] **Step 1: Create `Sources/MouseBar/Names/SettingsLayout.swift`**

```swift
import SwiftUI
import MouseCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case performance, buttons, lighting, power, device

    var id: String { rawValue }

    var title: String {
        switch self {
        case .performance: "Performance"
        case .buttons: "Buttons"
        case .lighting: "Lighting"
        case .power: "Power"
        case .device: "Device"
        }
    }

    var symbol: String {
        switch self {
        case .performance: "speedometer"
        case .buttons: "computermouse"
        case .lighting: "lightbulb"
        case .power: "powersleep"
        case .device: "info.circle"
        }
    }
}

/// App-side presentation of profile settings: which tab, which order, which friendly label.
/// Settings the table doesn't know appear in the Device tab's "Other" section, so the UI stays data-driven.
enum SettingsLayout {
    struct Entry {
        let tab: SettingsTab
        let order: Int
        let label: String
    }

    static let entries: [String: Entry] = [
        "sensitivity": Entry(tab: .performance, order: 0, label: "DPI presets"),
        "polling_rate": Entry(tab: .performance, order: 1, label: "Polling rate"),
        "buttons_mapping": Entry(tab: .buttons, order: 0, label: "Buttons"),
        "color": Entry(tab: .lighting, order: 0, label: "LED color"),
        "default_lighting": Entry(tab: .lighting, order: 1, label: "Startup lighting"),
        "dim_timer": Entry(tab: .lighting, order: 2, label: "Dim LED after"),
        "sleep_timer": Entry(tab: .power, order: 0, label: "Sleep after"),
    ]

    static func settings(for tab: SettingsTab, in family: DeviceFamily) -> [SettingSpec] {
        family.settings
            .filter { entries[$0.key]?.tab == tab }
            .sorted { (entries[$0.key]?.order ?? 0) < (entries[$1.key]?.order ?? 0) }
    }

    static func otherSettings(in family: DeviceFamily) -> [SettingSpec] {
        family.settings.filter { entries[$0.key] == nil }
    }

    static func label(for spec: SettingSpec) -> String {
        entries[spec.key]?.label ?? spec.label
    }
}

/// Values with units, as shown next to controls.
enum ValueFormat {
    static func dpi(_ value: Int) -> String { "\(value) DPI" }

    /// Segment labels: "1000 Hz" for the polling rate, "Off" / "Rainbow" for the rest.
    static func choice(key: String, _ choice: String) -> String {
        key == "polling_rate" ? "\(choice) Hz" : choice.capitalized
    }

    /// "Off", "30 s", "1 min", "1 min 30 s".
    static func seconds(_ value: Int) -> String {
        if value == 0 { return "Off" }
        if value < 60 { return "\(value) s" }
        let minutes = value / 60
        let rest = value % 60
        return rest == 0 ? "\(minutes) min" : "\(minutes) min \(rest) s"
    }

    static func range(key: String, value: Int) -> String {
        switch key {
        case "sleep_timer": value == 0 ? "Never" : "\(value) min"
        case "dim_timer": seconds(value)
        default: "\(value)"
        }
    }
}
```

- [ ] **Step 2: Create `Sources/MouseBar/Names/ButtonNames.swift`**

```swift
import MouseCore

/// Friendly names for the profile's button names and action tokens (all lowercased in mappings).
enum ButtonNames {
    static let buttons: [String: String] = [
        "button1": "Left click",
        "button2": "Right click",
        "button3": "Middle click",
        "button4": "Side back",
        "button5": "Side forward",
        "button6": "DPI button",
        "scrollup": "Scroll up",
        "scrolldown": "Scroll down",
    ]

    static let media: [String: String] = [
        "playpause": "Play/Pause",
        "next": "Next track",
        "previous": "Previous track",
        "volumeup": "Volume up",
        "volumedown": "Volume down",
        "mute": "Mute",
    ]

    static func name(_ button: String) -> String {
        buttons[button.lowercased()] ?? button
    }

    static func actionName(_ token: String) -> String {
        let key = token.lowercased()
        switch key {
        case "default": return "Default"
        case "disabled", "disable": return "Disabled"
        case "dpi": return "Cycle DPI"
        default:
            if let name = buttons[key] { return name }
            if let name = media[key] { return name }
            return "Key \(token.uppercased())"
        }
    }

    /// The "Mouse" section of the action menu: other buttons (not the DPI button itself), Cycle DPI, Disabled.
    static func mouseActions(for spec: SettingSpec) -> [String] {
        var actions = (spec.buttons ?? []).map { $0.name.lowercased() }.filter { $0 != "button6" }
        if spec.buttonDpiSwitch != nil { actions.append("dpi") }
        if spec.buttonDisable != nil { actions.append("disabled") }
        return actions
    }
}
```

- [ ] **Step 3: Create `Sources/MouseBar/Components/ButtonActionMenu.swift`**

```swift
import SwiftUI
import MouseCore

/// The action menu for one button: Default, Mouse, Media, and "Keyboard key…" (a searchable popover).
struct ButtonActionMenu: View {
    let spec: SettingSpec
    let button: ButtonSpec
    /// Current token for this button, "default" when unset.
    let token: String
    let layouts: ButtonLayouts
    let onChange: (String) -> Void
    @State private var showKeys = false

    private var defaultTitle: String { "Default (\(ButtonNames.actionName(button.defaultAction)))" }
    private var currentTitle: String { token == "default" ? defaultTitle : ButtonNames.actionName(token) }

    var body: some View {
        Menu {
            Button(defaultTitle) { onChange("default") }
            Section("Mouse") {
                ForEach(ButtonNames.mouseActions(for: spec), id: \.self) { action in
                    Button(ButtonNames.actionName(action)) { onChange(action) }
                }
            }
            if spec.buttonMultimedia != nil {
                Section("Media") {
                    ForEach(layouts.multimediaKeys, id: \.self) { key in
                        Button(ButtonNames.actionName(key.lowercased())) { onChange(key.lowercased()) }
                    }
                }
            }
            if spec.buttonKeyboard != nil {
                Divider()
                Button("Keyboard key…") { showKeys = true }
            }
        } label: {
            Text(currentTitle)
        }
        .fixedSize()
        .popover(isPresented: $showKeys, arrowEdge: .trailing) {
            KeyPickerPopover(keys: layouts.keyboardKeys) { key in
                onChange(key.lowercased())
                showKeys = false
            }
        }
        .accessibilityLabel("\(ButtonNames.name(button.name)) action")
        .accessibilityValue(currentTitle)
    }
}

struct KeyPickerPopover: View {
    let keys: [String]
    let onPick: (String) -> Void
    @State private var query = ""

    private var filtered: [String] {
        query.isEmpty ? keys : keys.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            TextField("Search keys", text: $query)
                .textFieldStyle(.roundedBorder)
            List(filtered, id: \.self) { key in
                Button(key) { onPick(key) }
                    .buttonStyle(.plain)
            }
            .frame(height: 220)
        }
        .padding(Theme.Space.m)
        .frame(width: 220)
    }
}
```

- [ ] **Step 4: Build and run the suite**

Run: `swift build --arch arm64 2>&1 | grep -E "warning|error" ; swift test 2>&1 | tail -3`
Expected: no warnings/errors; 106 pass. (Nothing uses these types yet; they are wired in Tasks 6, 8, 9.)

- [ ] **Step 5: Commit**

```bash
git add Sources/MouseBar/Names Sources/MouseBar/Components/ButtonActionMenu.swift
git commit -m "feat(app): settings layout table, friendly names, button action menu" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: CheckRunner (wizard engine) and restore paths

**Files:**
- Create: `Sources/MouseBar/HardwareCheck/CheckRunner.swift`
- Modify: `Sources/MouseBar/AppModel.swift` (end of `selectActive`), replace `Sources/MouseBar/AppDelegate.swift`

**Interfaces:**
- Consumes: Task 1 session APIs; Task 2 models; Task 3 `AppModel` (`activeSession`, `connection`, `battery`, `isCheckRunning`, `setActivePresetConfirmed`, `settingsDirectory`, `displayName`, `refreshValues`, `notice`, `problem`, `values`)
- Produces (used by Task 6): `@MainActor @Observable final class CheckRunner` with `static let shared`, `enum Phase` (`idle, preflight, instructions(String, actionTitle: String), working(String), question(String), measure(String, seconds: Double), keyPress(String), waiting(String, until: Date), restoring, results`), properties `phase`, `phaseToken`, `stepIndex`, `outcomes: [CheckStepID: StepOutcome]`, `reportURL`, `reportMarkdown`, `isRunning`, `needsRestore`, `enteredPresets: [Int]`, `enteredButtons: ButtonMapping`, `useFactoryDefaults: Bool`; methods `start()`, `beginTests()`, `proceed()`, `answer(_ yes: Bool)`, `submit(timestamps:)`, `keyPressed()`, `skip()`, `cancel()`, `rerun(_:)`, `restoreIfInterrupted() async`, `restoreForQuit() async`. Constant `CheckRunner.f18KeyCode: UInt16 = 79`.

- [ ] **Step 1: Create `Sources/MouseBar/HardwareCheck/CheckRunner.swift`**

```swift
import AppKit
import MouseCore
import Observation

/// Drives the hardware check against the live session: each step is a small script that writes to the mouse,
/// waits for the owner (answers, mouse moves, a key press, a connection or battery change), and records an outcome.
/// Test writes are transient; the owner's settings are put back after every step and fully restored at the end.
@MainActor @Observable
final class CheckRunner {
    static let shared = CheckRunner(model: AppModel.shared)
    /// macOS virtual key code of F18 (side button 4 is remapped to it in the buttons step).
    static let f18KeyCode: UInt16 = 79

    enum Phase: Equatable {
        case idle
        case preflight
        case instructions(String, actionTitle: String)
        case working(String)
        case question(String)
        case measure(String, seconds: Double)
        case keyPress(String)
        case waiting(String, until: Date)
        case restoring
        case results
    }

    enum Input: Equatable {
        case proceed, yes, no, key, timeout
        case timestamps([Double])
    }

    struct Skipped: Error {}
    struct Cancelled: Error {}
    struct StepFailure: Error { let message: String }

    private(set) var phase: Phase = .idle
    /// Changes on every phase change; views use it as an identity so each capture box starts fresh.
    private(set) var phaseToken = 0
    private(set) var stepIndex = 0
    private(set) var outcomes: [CheckStepID: StepOutcome] = [:]
    private(set) var reportURL: URL?
    private(set) var reportMarkdown: String?
    var enteredPresets: [Int] = [400, 800, 1200, 2400, 3200]
    var enteredButtons = ButtonMapping()
    var useFactoryDefaults = false

    private let model: AppModel
    @ObservationIgnored private var input: CheckedContinuation<Input, Error>?
    @ObservationIgnored private var interrupt: Error?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var snapshot: RestoreSnapshot?
    @ObservationIgnored private var lastSnapshot: RestoreSnapshot?

    init(model: AppModel) {
        self.model = model
    }

    var isRunning: Bool { runTask != nil }
    var needsRestore: Bool { snapshot != nil }
    private var snapshotURL: URL { RestoreSnapshot.fileURL(in: model.settingsDirectory) }

    // MARK: Owner actions

    /// Welcome -> preflight. Prefills the owner's DPI presets and button remaps when MouseBar already stores them.
    func start() {
        guard runTask == nil else { return }
        outcomes = [:]
        reportURL = nil
        reportMarkdown = nil
        stepIndex = 0
        Task {
            if let values = await model.activeSession?.currentValues {
                if case .dpiPresets(let presets, _)? = values["sensitivity"] { enteredPresets = presets }
                if case .buttons(let mapping)? = values["buttons_mapping"] { enteredButtons = mapping }
            }
            setPhase(.preflight)
        }
    }

    /// Preflight -> writes the restore snapshot, then runs every step.
    func beginTests() {
        guard runTask == nil, let session = model.activeSession else { return }
        let family = session.mouse.family
        var presets = enteredPresets
        var buttons = enteredButtons
        if useFactoryDefaults {
            if let spec = family.setting("sensitivity"),
               case .dpiPresets(let factory, _)? = DefaultSettings.value(for: spec) {
                presets = factory
            }
            buttons = ButtonMapping()
        }
        runTask = Task {
            let stored = await session.currentValues
            let snap = RestoreSnapshot(
                mouse: session.mouse.model.mouse, stored: stored, dpiPresets: presets, buttons: buttons
            )
            do {
                try snap.write(to: snapshotURL)
            } catch {
                model.problem = "Could not save the restore snapshot: \(error)"
                setPhase(.idle)
                runTask = nil
                return
            }
            snapshot = snap
            lastSnapshot = snap
            outcomes = [.preflight: StepOutcome(step: .preflight, result: .pass, detail: "Settings snapshot saved")]
            model.isCheckRunning = true
            await session.setPollInterval(.seconds(5))
            await runSteps(Array(CheckStepID.allCases.dropFirst()))
        }
    }

    /// Runs one step again (from the results screen), with the same snapshot and a full restore afterwards.
    func rerun(_ step: CheckStepID) {
        guard runTask == nil, step != .preflight, let snap = lastSnapshot, let session = model.activeSession else { return }
        runTask = Task {
            do {
                try snap.write(to: snapshotURL)
            } catch {
                model.problem = "Could not save the restore snapshot: \(error)"
                runTask = nil
                return
            }
            snapshot = snap
            model.isCheckRunning = true
            await session.setPollInterval(.seconds(5))
            await runSteps([step])
        }
    }

    func proceed() { resume(.success(.proceed)) }
    func answer(_ yes: Bool) { resume(.success(yes ? .yes : .no)) }
    func submit(timestamps: [Double]) { resume(.success(.timestamps(timestamps))) }
    func keyPressed() { resume(.success(.key)) }

    func skip() {
        if input != nil {
            resume(.failure(Skipped()))
        } else if runTask != nil {
            interrupt = Skipped()
        }
    }

    /// Stops the run (remaining steps are not run) and restores; before the run it just returns to the welcome card.
    func cancel() {
        if input != nil {
            resume(.failure(Cancelled()))
        } else if runTask != nil {
            interrupt = Cancelled()
        } else if phase == .preflight {
            setPhase(.idle)
        }
    }

    // MARK: Restore entry points

    /// At launch / connect: a snapshot left by an interrupted check (crash, force quit) is restored once.
    func restoreIfInterrupted() async {
        guard runTask == nil, snapshot == nil, let snap = RestoreSnapshot.read(from: snapshotURL) else { return }
        snapshot = snap
        await restoreAll()
        if snapshot == nil {
            model.notice = "Restored your settings after an interrupted hardware check."
        }
        if phase == .restoring { setPhase(.idle) }
    }

    /// From the app delegate when quitting.
    func restoreForQuit() async {
        if input != nil { resume(.failure(Cancelled())) }
        await restoreAll()
    }

    // MARK: Step sequencing

    private func runSteps(_ steps: [CheckStepID]) async {
        for step in steps {
            stepIndex = CheckStepID.allCases.firstIndex(of: step) ?? 0
            interrupt = nil
            var stop = false
            do {
                outcomes[step] = try await run(step)
            } catch is Skipped {
                outcomes[step] = StepOutcome(step: step, result: .skipped, detail: "Skipped")
            } catch is Cancelled {
                outcomes[step] = StepOutcome(step: step, result: .skipped, detail: "Cancelled")
                stop = true
            } catch let failure as StepFailure {
                outcomes[step] = StepOutcome(step: step, result: .fail, detail: failure.message)
            } catch {
                outcomes[step] = StepOutcome(step: step, result: .fail, detail: String(describing: error))
            }
            // Put this step's test values back even when it failed half-way.
            await undoTestWrites(of: step)
            if stop { break }
        }
        await restoreAll()
        writeReport()
        model.isCheckRunning = false
        runTask = nil
        setPhase(.results)
    }

    private func run(_ step: CheckStepID) async throws -> StepOutcome {
        switch step {
        case .preflight: StepOutcome(step: .preflight, result: .pass, detail: "Settings snapshot saved")
        case .batteryCable: try await batteryStep(.batteryCable, wanted: .cable)
        case .batteryDongle: try await batteryStep(.batteryDongle, wanted: .dongle)
        case .ledColor: try await ledStep()
        case .pollingRate: try await pollingStep()
        case .buttons: try await buttonsStep()
        case .dpiPreset: try await dpiStep()
        case .savePersistence: try await saveStep()
        case .wakeReapply: try await wakeStep()
        }
    }

    // MARK: Steps

    private func batteryStep(_ id: CheckStepID, wanted: AppModel.ConnectionKind) async throws -> StepOutcome {
        let instruction = wanted == .cable
            ? "Connect the mouse with the USB cable."
            : "Plug in the 2.4 GHz dongle, then unplug the USB cable."
        guard try await waitFor(instruction, timeout: 120, { self.model.connection == wanted }) else {
            throw StepFailure(message: "The \(wanted.title) connection did not appear within 2 minutes.")
        }
        setPhase(.working("Reading the battery…"))
        try await Task.sleep(for: .seconds(1))   // let a freshly switched session finish re-applying settings
        let session = try activeSession()
        guard let battery = session.mouse.family.battery, let command = battery.command.first.map(UInt8.init) else {
            throw StepFailure(message: "This mouse profile has no battery query.")
        }
        guard let reply = try await session.rawBatteryQuery() else {
            throw StepFailure(message: "No reply within 200 ms. Move the mouse to wake it, then run this step again.")
        }
        let hex = HexFormat.string(reply)
        let first = reply.first.map { String(format: "0x%02X", $0) } ?? "none"
        let echoes = reply.first == command
        let echoText = echoes
            ? "byte 0 = \(first) (echoes the command)"
            : "byte 0 = \(first), command was \(String(format: "0x%02X", command))"
        guard let reading = BatteryDecoder.decode(decoder: battery.decoder, reply: reply) else {
            return StepOutcome(step: id, result: .fail, detail: "Not a valid battery reading; \(echoText)", rawHex: hex)
        }
        let level = "\(reading.level)%\(reading.isCharging ? ", charging" : "")"
        // The cable must echo (verified behavior); the dongle's echo is recorded to decide the dongle filter later.
        let pass = wanted == .cable ? echoes : true
        return StepOutcome(step: id, result: pass ? .pass : .fail, detail: "\(level); \(echoText)", rawHex: hex)
    }

    private func ledStep() async throws -> StepOutcome {
        try await waitForProceed("The check turns the LED blue, then green.", actionTitle: "Turn LED blue")
        let session = try activeSession()
        try await session.applyTransient("color", .color(MouseCore.RGBColor(r: 0, g: 0, b: 255)))
        let blue = try await ask("Is the mouse LED blue?")
        try await session.applyTransient("color", .color(MouseCore.RGBColor(r: 0, g: 255, b: 0)))
        let green = try await ask("Is the mouse LED green now?")
        return StepOutcome(
            step: .ledColor, result: blue && green ? .pass : .fail,
            detail: "Blue: \(yesNo(blue)); green: \(yesNo(green))"
        )
    }

    private func pollingStep() async throws -> StepOutcome {
        let session = try activeSession()
        try await session.applyTransient("polling_rate", .choice("125"))
        let slow = try await measure("Polling rate is 125 Hz. Move the mouse in circles inside the box for 3 seconds.")
        try await session.applyTransient("polling_rate", .choice("1000"))
        let fast = try await measure("Polling rate is 1000 Hz. Move the mouse in circles inside the box again.")
        guard let slow, let fast else {
            throw StepFailure(message: "Not enough mouse movement was captured. Run this step again and keep moving the mouse.")
        }
        return StepOutcome(
            step: .pollingRate, result: fast >= slow * 3 ? .pass : .fail,
            detail: String(format: "125 Hz: %.0f events/s; 1000 Hz: %.0f events/s", slow, fast),
            measurements: ["rate125": slow, "rate1000": fast]
        )
    }

    private func buttonsStep() async throws -> StepOutcome {
        let session = try activeSession()
        guard let snap = snapshot else { throw StepFailure(message: "No restore snapshot.") }
        var assignments = snap.buttons.assignments
        assignments["button4"] = "f18"
        try await session.applyTransient("buttons_mapping", .buttons(ButtonMapping(assignments: assignments)))
        let pressed = try await waitKey(
            "Side button 4 now types F18. Keep the pointer inside the box and press side button 4.", timeout: 15
        )
        // Back to the owner's map before the rejection test.
        try await session.applyTransient("buttons_mapping", .buttons(snap.buttons))
        // Validation must refuse a map without a left click before anything is written.
        var rejected = false
        do {
            try await session.applyTransient(
                "buttons_mapping", .buttons(ButtonMapping(assignments: ["button1": "disabled"]))
            )
        } catch MouseCoreError.noPrimaryClick {
            rejected = true
        }
        if !rejected {
            // The write went through: undo it at once.
            try await session.applyTransient("buttons_mapping", .buttons(snap.buttons))
        }
        try await waitForProceed(
            "Click Continue with the left mouse button to confirm left click still works.", actionTitle: "Continue"
        )
        return StepOutcome(
            step: .buttons, result: pressed && rejected ? .pass : .fail,
            detail: "F18 from side button 4: \(yesNo(pressed)); map without a left click refused: \(yesNo(rejected))"
        )
    }

    private func dpiStep() async throws -> StepOutcome {
        try await waitForProceed(
            "The check writes two DPI presets, 400 and 3200, and switches between them.", actionTitle: "Write presets"
        )
        let session = try activeSession()
        try await session.applyTransient("sensitivity", .dpiPresets(presets: [400, 3200], selected: 0))
        let slow = try await ask("Preset 1 (400 DPI) is active. Move the mouse: is the pointer slow?")
        try await session.applyTransient("sensitivity", .dpiPresets(presets: [400, 3200], selected: 1))
        let fast = try await ask("Preset 2 (3200 DPI) is active. Is the pointer much faster now?")
        let pass = slow && fast
        model.setActivePresetConfirmed(pass)
        return StepOutcome(
            step: .dpiPreset, result: pass ? .pass : .fail,
            detail: "Slow at preset 1: \(yesNo(slow)); fast at preset 2: \(yesNo(fast))"
        )
    }

    private func saveStep() async throws -> StepOutcome {
        try await waitForProceed(
            "The check turns the startup lighting off and saves it to the mouse.", actionTitle: "Save to mouse"
        )
        let session = try activeSession()
        try await session.applyTransient("default_lighting", .choice("off"))
        try await session.saveNow()
        let stayedOff = try await ask(
            "Unplug the USB cable if it is connected, switch the mouse off and on, and watch the LED as it starts. "
                + "Did the LED stay off at startup?"
        )
        return StepOutcome(
            step: .savePersistence, result: stayedOff ? .pass : .fail,
            detail: "LED stayed off after the power cycle: \(yesNo(stayedOff))"
        )
    }

    private func wakeStep() async throws -> StepOutcome {
        guard try await waitFor(
            "This step needs the dongle: unplug the USB cable and use the 2.4 GHz dongle.",
            timeout: 120, { self.model.connection == .dongle }
        ) else {
            throw StepFailure(message: "The dongle connection did not appear within 2 minutes.")
        }
        guard model.values["color"] != nil else {
            return StepOutcome(
                step: .wakeReapply, result: .skipped,
                detail: "No LED color is stored. Pick one in Settings → Lighting, then run this step again."
            )
        }
        guard try await waitFor(
            "Switch the mouse off and wait until this changes.", timeout: 120,
            { self.model.battery.freshness == .asleep }
        ) else {
            throw StepFailure(message: "The mouse was not seen asleep within 2 minutes.")
        }
        guard try await waitFor(
            "The mouse is asleep. Now switch it on and move it.", timeout: 120,
            { self.model.battery.freshness == .fresh }
        ) else {
            throw StepFailure(message: "The mouse did not answer again within 2 minutes.")
        }
        let back = try await ask("Is your LED color back?")
        return StepOutcome(step: .wakeReapply, result: back ? .pass : .fail, detail: "Color came back: \(yesNo(back))")
    }

    // MARK: Undo and restore

    private static let stepKeys: [CheckStepID: [String]] = [
        .ledColor: ["color"],
        .pollingRate: ["polling_rate"],
        .buttons: ["buttons_mapping"],
        .dpiPreset: ["sensitivity"],
        .savePersistence: ["default_lighting"],
    ]

    /// Best effort: re-sends the owner's value for every key the step tested (not stored, not saved).
    private func undoTestWrites(of step: CheckStepID) async {
        guard let keys = Self.stepKeys[step], let snap = snapshot, let session = model.activeSession else { return }
        let writes = snap.restoreWrites(family: session.mouse.family).filter { keys.contains($0.key) }
        for write in writes {
            try? await session.applyTransient(write.key, write.value)
        }
    }

    /// Writes (and stores) every restore value, saves to the mouse, resets the poll interval, then deletes the
    /// snapshot. Keeps the snapshot when anything failed or the mouse is gone, so a later connect retries.
    private func restoreAll() async {
        guard let snap = snapshot else { return }
        setPhase(.restoring)
        guard let session = model.activeSession, session.mouse.model.mouse == snap.mouse else {
            model.notice = "Your settings will be restored when the mouse reconnects."
            return
        }
        var failures: [String] = []
        for write in snap.restoreWrites(family: session.mouse.family) {
            do {
                try await session.set(write.key, write.value)
            } catch {
                failures.append("\(write.key): \(error)")
            }
        }
        do {
            try await session.saveNow()
        } catch {
            failures.append("save: \(error)")
        }
        await session.setPollInterval(.seconds(60))
        await model.refreshValues()
        if failures.isEmpty {
            try? FileManager.default.removeItem(at: snapshotURL)
            snapshot = nil
        } else {
            model.problem = "Some settings could not be restored: \(failures.joined(separator: "; "))"
        }
    }

    private func writeReport() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let report = CheckReport(
            date: Date(), appVersion: version, mouseModel: model.displayName ?? "unknown",
            outcomes: CheckStepID.allCases.compactMap { outcomes[$0] }
        )
        let markdown = report.markdown()
        reportMarkdown = markdown
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let directory = model.settingsDirectory.appendingPathComponent("reports", isDirectory: true)
        let url = directory.appendingPathComponent("hardware-check-\(formatter.string(from: Date())).md")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            reportURL = url
        } catch {
            model.problem = "Could not write the report: \(error)"
        }
    }

    // MARK: Waiting primitives

    private func setPhase(_ phase: Phase) {
        self.phase = phase
        phaseToken += 1
    }

    private func activeSession() throws -> MouseSession {
        guard let session = model.activeSession else { throw StepFailure(message: "No mouse connected.") }
        return session
    }

    private func resume(_ result: Result<Input, Error>) {
        let pending = input
        input = nil
        pending?.resume(with: result)
    }

    private func waitForInput(_ phase: Phase) async throws -> Input {
        if let pending = interrupt {
            interrupt = nil
            throw pending
        }
        setPhase(phase)
        return try await withCheckedThrowingContinuation { input = $0 }
    }

    private func waitForProceed(_ text: String, actionTitle: String) async throws {
        _ = try await waitForInput(.instructions(text, actionTitle: actionTitle))
    }

    private func ask(_ question: String) async throws -> Bool {
        try await waitForInput(.question(question)) == .yes
    }

    private func measure(_ text: String) async throws -> Double? {
        guard case .timestamps(let timestamps) = try await waitForInput(.measure(text, seconds: 3)) else { return nil }
        return PollingRateEstimator.rate(timestamps: timestamps)
    }

    private func waitKey(_ text: String, timeout: Double) async throws -> Bool {
        let token = phaseToken + 1   // the token setPhase assigns for this wait
        let timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self, !Task.isCancelled, self.phaseToken == token else { return }
            self.resume(.success(.timeout))
        }
        defer { timer.cancel() }
        return try await waitForInput(.keyPress(text)) == .key
    }

    /// Polls `condition` every 0.5 s until it holds (true) or the timeout passes (false). Skip/Cancel interrupt it.
    private func waitFor(_ text: String, timeout: TimeInterval, _ condition: () -> Bool) async throws -> Bool {
        if condition() { return true }
        let deadline = Date().addingTimeInterval(timeout)
        setPhase(.waiting(text, until: deadline))
        while Date() < deadline {
            if let pending = interrupt {
                interrupt = nil
                throw pending
            }
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return false
    }

    private func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }
}
```

- [ ] **Step 2: Hook restore-on-connect and the check's poll interval into `AppModel.selectActive`**

In `Sources/MouseBar/AppModel.swift`, at the end of `selectActive()`, after the line `if !errors.isEmpty { problem = errors.joined(separator: "\n") }`, add:

```swift
        if isCheckRunning {
            // The check switched connections (cable <-> dongle): keep its fast battery polling on the new session.
            await session.setPollInterval(.seconds(5))
        } else {
            // A check interrupted by a crash or force quit left a snapshot: put the owner's settings back once.
            await CheckRunner.shared.restoreIfInterrupted()
        }
```

- [ ] **Step 3: Replace `Sources/MouseBar/AppDelegate.swift`**

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let flushTimeout: Duration = .seconds(3)
    private static let restoreTimeout: Duration = .seconds(5)
    private var terminationPending = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        let runner = CheckRunner.shared
        let restoring = runner.needsRestore
        // Restore the owner's settings if a hardware check is mid-way, then send a pending device save,
        // but never hang on a stuck device: whichever finishes first replies, exactly once.
        var replied = false
        let reply = {
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        let timeout = Task {
            try? await Task.sleep(for: restoring ? Self.restoreTimeout : Self.flushTimeout)
            reply()
        }
        Task {
            if restoring { await runner.restoreForQuit() }
            await AppModel.shared.flush()
            timeout.cancel()
            reply()
        }
        return .terminateLater
    }
}
```

- [ ] **Step 4: Build, suite, demo launch**

Run: `swift build --arch arm64 2>&1 | grep -E "warning|error" ; swift test 2>&1 | tail -3`, then the **Demo-launch procedure**.
Expected: no warnings/errors; 106 pass; demo runs 7 s with no crash. (The wizard window arrives in Task 6.)

- [ ] **Step 5: Commit**

```bash
git add Sources/MouseBar/HardwareCheck/CheckRunner.swift Sources/MouseBar/AppModel.swift Sources/MouseBar/AppDelegate.swift
git commit -m "feat(app): hardware check runner with restore on finish, cancel, quit and next launch" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Wizard window (assistant card)

**Files:**
- Create: `Sources/MouseBar/HardwareCheck/EventCaptureBox.swift`, `CheckWindow.swift`, `CheckStepCard.swift`, `CheckPreflightView.swift`, `CheckResultsView.swift`
- Modify: `Sources/MouseBar/MouseBarApp.swift` (add the window scene), `Sources/MouseBar/Views/MenuContent.swift` (add a "Hardware Check…" item), `Sources/MouseBar/Views/SettingsView.swift` (add a "Hardware Check…" button)

**Interfaces:**
- Consumes: `CheckRunner` (Task 5), `Theme`, `StatusBanner` (Task 3), `ButtonActionMenu`, `ButtonNames` (Task 4)
- Produces: window scene id `"hardware-check"`; `extension CheckStepID { var symbol: String }`

- [ ] **Step 1: Create `Sources/MouseBar/HardwareCheck/EventCaptureBox.swift`**

```swift
import AppKit
import SwiftUI
import MouseCore

/// Captures mouse-move timestamps (event coalescing off) or one key press while the pointer is inside it.
struct EventCaptureBox: NSViewRepresentable {
    enum Mode: Equatable {
        case measure(seconds: Double)
        case key(keyCode: UInt16)
    }

    let mode: Mode
    let onTimestamps: ([Double]) -> Void
    let onKey: () -> Void
    let onLive: (Double?) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        update(view)
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        update(view)
    }

    private func update(_ view: CaptureView) {
        view.mode = mode
        view.onTimestamps = onTimestamps
        view.onKey = onKey
        view.onLive = onLive
    }
}

final class CaptureView: NSView {
    var mode: EventCaptureBox.Mode = .measure(seconds: 3)
    var onTimestamps: (([Double]) -> Void)?
    var onKey: (() -> Void)?
    var onLive: ((Double?) -> Void)?
    private var timestamps: [Double] = []
    private var startedAt: TimeInterval?
    private var finished = false
    private var savedCoalescing: Bool?
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            // Coalescing merges mouse moves; it must be off to count the mouse's real report rate.
            savedCoalescing = NSEvent.isMouseCoalescingEnabled
            NSEvent.isMouseCoalescingEnabled = false
            window.acceptsMouseMovedEvents = true
            window.makeFirstResponder(self)
        } else if let saved = savedCoalescing {
            NSEvent.isMouseCoalescingEnabled = saved
            savedCoalescing = nil
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard case .measure(let seconds) = mode, !finished else { return }
        if startedAt == nil { startedAt = event.timestamp }
        timestamps.append(event.timestamp)
        if timestamps.count % 20 == 0 {
            onLive?(PollingRateEstimator.rate(timestamps: Array(timestamps.suffix(80))))
        }
        if let startedAt, event.timestamp - startedAt >= seconds {
            finished = true
            onTimestamps?(timestamps)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard case .key(let code) = mode, !finished, event.keyCode == code else {
            super.keyDown(with: event)
            return
        }
        finished = true
        onKey?()
    }
}
```

- [ ] **Step 2: Create `Sources/MouseBar/HardwareCheck/CheckStepCard.swift`**

```swift
import SwiftUI
import MouseCore

extension CheckStepID {
    var symbol: String {
        switch self {
        case .preflight: "checklist"
        case .batteryCable: "cable.connector"
        case .batteryDongle: "antenna.radiowaves.left.and.right"
        case .ledColor: "lightbulb.fill"
        case .pollingRate: "speedometer"
        case .buttons: "computermouse.fill"
        case .dpiPreset: "cursorarrow.motionlines"
        case .savePersistence: "memorychip"
        case .wakeReapply: "power"
        }
    }
}

/// The current step: symbol, title, and the phase's interaction area.
struct CheckStepCard: View {
    let runner: CheckRunner

    private var step: CheckStepID {
        let all = CheckStepID.allCases
        return all[min(runner.stepIndex, all.count - 1)]
    }

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: step.symbol)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(step.title)
                .font(.title3.weight(.semibold))
            phaseBody
                .frame(maxWidth: .infinity)
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder private var phaseBody: some View {
        switch runner.phase {
        case .instructions(let text, _):
            Text(text).font(.callout)
        case .working(let text):
            ProgressView(text)
        case .question(let text):
            VStack(spacing: Theme.Space.l) {
                Text(text).font(.callout)
                HStack(spacing: Theme.Space.m) {
                    Button("No") { runner.answer(false) }
                        .controlSize(.large)
                    Button("Yes") { runner.answer(true) }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                }
            }
        case .measure(let text, let seconds):
            VStack(spacing: Theme.Space.m) {
                Text(text).font(.callout)
                CaptureArea(mode: .measure(seconds: seconds), runner: runner)
                    .id(runner.phaseToken)
            }
        case .keyPress(let text):
            VStack(spacing: Theme.Space.m) {
                Text(text).font(.callout)
                CaptureArea(mode: .key(keyCode: CheckRunner.f18KeyCode), runner: runner)
                    .id(runner.phaseToken)
            }
        case .waiting(let text, let until):
            VStack(spacing: Theme.Space.m) {
                Text(text).font(.callout)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: Theme.Space.s) {
                        ProgressView().controlSize(.small)
                        Text("\(max(0, Int(until.timeIntervalSince(context.date)))) s left")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        default:
            EmptyView()
        }
    }
}

/// A dashed box with the capture view inside and a live readout.
struct CaptureArea: View {
    let mode: EventCaptureBox.Mode
    let runner: CheckRunner
    @State private var live: Double?

    private var isMeasure: Bool {
        if case .measure = mode { return true }
        return false
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.radius).fill(.quaternary)
            RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            EventCaptureBox(
                mode: mode,
                onTimestamps: { runner.submit(timestamps: $0) },
                onKey: { runner.keyPressed() },
                onLive: { live = $0 }
            )
            VStack(spacing: Theme.Space.xs) {
                Image(systemName: isMeasure ? "arrow.triangle.2.circlepath" : "keyboard")
                    .font(.title2)
                Text(isMeasure ? (live.map { String(format: "%.0f events/s", $0) } ?? "Move the mouse here")
                               : "Press side button 4 here")
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
        }
        .frame(height: 160)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isMeasure ? "Capture area. Move the mouse in circles here." : "Capture area. Press side button 4 here.")
    }
}
```

- [ ] **Step 3: Create `Sources/MouseBar/HardwareCheck/CheckPreflightView.swift`**

```swift
import SwiftUI
import MouseCore

/// Collects the owner's DPI presets and button remaps, which the mouse cannot report, so they can be restored.
struct CheckPreflightView: View {
    @Bindable var runner: CheckRunner
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Before you start")
                    .font(.title3.weight(.semibold))
                Text("The mouse can't report its DPI presets or button remaps. Enter them so the check can put them back afterwards. Start with the USB cable connected and keep the dongle nearby.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("I don't know them — restore factory defaults", isOn: $runner.useFactoryDefaults)
                if !runner.useFactoryDefaults {
                    GroupBox("DPI presets") { presetsEditor }
                    if let spec = model.family?.setting("buttons_mapping") {
                        GroupBox("Button remaps") { buttonsEditor(spec) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var presetsEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(runner.enteredPresets.indices, id: \.self) { index in
                HStack {
                    Stepper(value: Binding(
                        get: { runner.enteredPresets.indices.contains(index) ? runner.enteredPresets[index] : 100 },
                        set: { value in
                            guard runner.enteredPresets.indices.contains(index) else { return }
                            runner.enteredPresets[index] = value
                        }
                    ), in: 100...18000, step: 100) {
                        Text("Preset \(index + 1): \(ValueFormat.dpi(runner.enteredPresets.indices.contains(index) ? runner.enteredPresets[index] : 100))")
                            .monospacedDigit()
                    }
                    Button {
                        guard runner.enteredPresets.indices.contains(index) else { return }
                        runner.enteredPresets.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(runner.enteredPresets.count <= 1)
                    .accessibilityLabel("Remove preset \(index + 1)")
                }
            }
            Button {
                runner.enteredPresets.append(min(runner.enteredPresets.last ?? 800, 18000))
            } label: {
                Label("Add preset", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(runner.enteredPresets.count >= 5)
        }
        .padding(Theme.Space.s)
    }

    private func buttonsEditor(_ spec: SettingSpec) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(spec.buttons ?? [], id: \.name) { button in
                HStack {
                    Text(ButtonNames.name(button.name))
                    Spacer()
                    ButtonActionMenu(
                        spec: spec, button: button,
                        token: runner.enteredButtons.assignments[button.name.lowercased()] ?? "default",
                        layouts: model.layouts
                    ) { token in
                        var assignments = runner.enteredButtons.assignments
                        assignments[button.name.lowercased()] = token
                        runner.enteredButtons = ButtonMapping(assignments: assignments)
                    }
                }
            }
        }
        .padding(Theme.Space.s)
    }
}
```

- [ ] **Step 4: Create `Sources/MouseBar/HardwareCheck/CheckResultsView.swift`**

```swift
import AppKit
import SwiftUI
import MouseCore

struct CheckResultsView: View {
    let runner: CheckRunner
    @State private var expanded: Set<CheckStepID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Results")
                .font(.title3.weight(.semibold))
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    ForEach(CheckStepID.allCases, id: \.self) { step in
                        row(step)
                    }
                }
            }
            HStack {
                Button("Copy report") {
                    guard let markdown = runner.reportMarkdown else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                }
                .disabled(runner.reportMarkdown == nil)
                Button("Reveal in Finder") {
                    if let url = runner.reportURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                .disabled(runner.reportURL == nil)
            }
        }
    }

    private func row(_ step: CheckStepID) -> some View {
        let outcome = runner.outcomes[step]
        return DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(step) },
            set: { open in
                if open { expanded.insert(step) } else { expanded.remove(step) }
            }
        )) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(outcome?.detail ?? "Not run").font(.callout)
                if let raw = outcome?.rawHex {
                    Text(raw).font(.caption).monospaced().textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                resultLabel(outcome?.result)
                Text(step.title)
                Spacer()
                if step != .preflight {
                    Button("Run again") { runner.rerun(step) }
                        .controlSize(.small)
                        .disabled(runner.isRunning)
                }
            }
        }
    }

    @ViewBuilder private func resultLabel(_ result: StepResult?) -> some View {
        switch result {
        case .pass?:
            Label("Passed", systemImage: Theme.Symbol.pass).foregroundStyle(.green).labelStyle(.titleAndIcon)
        case .fail?:
            Label("Failed", systemImage: Theme.Symbol.fail).foregroundStyle(.red).labelStyle(.titleAndIcon)
        case .skipped?:
            Label("Skipped", systemImage: Theme.Symbol.skipped).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
        case nil:
            Label("Not run", systemImage: Theme.Symbol.notRun).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
        }
    }
}
```

- [ ] **Step 5: Create `Sources/MouseBar/HardwareCheck/CheckWindow.swift`**

```swift
import SwiftUI
import MouseCore

/// The Hardware Check assistant: progress header, one card per step, Skip / Cancel / Continue footer.
struct CheckWindow: View {
    let runner: CheckRunner
    let model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsProgress: Bool {
        switch runner.phase {
        case .idle, .results: false
        default: true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsProgress {
                header
                Divider()
            }
            content
                .padding(Theme.windowPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .themedAnimation(runner.phaseToken, reduceMotion: reduceMotion)
            Divider()
            footer
                .padding(Theme.Space.l)
        }
        .frame(width: 560, height: 520)
        .overlay {
            if runner.phase == .restoring {
                ZStack {
                    Rectangle().fill(.regularMaterial)
                    ProgressView("Restoring your settings…")
                }
            }
        }
        .onDisappear { runner.cancel() }
    }

    private var header: some View {
        let total = CheckStepID.allCases.count
        return HStack(spacing: Theme.Space.xs) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index <= runner.stepIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
            Spacer()
            Text("Step \(runner.stepIndex + 1) of \(total)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.windowPadding)
        .padding(.vertical, Theme.Space.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(runner.stepIndex + 1) of \(total)")
    }

    @ViewBuilder private var content: some View {
        switch runner.phase {
        case .idle:
            welcome
        case .preflight:
            CheckPreflightView(runner: runner, model: model)
        case .results:
            CheckResultsView(runner: runner)
        default:
            CheckStepCard(runner: runner)
        }
    }

    private var welcome: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: "checkmark.seal")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Hardware Check")
                .font(.title3.weight(.semibold))
            Text("Checks that MouseBar's changes really reach your mouse: battery over the cable and the dongle, LED color, polling rate, buttons, DPI, saving, and wake. Takes about 5 minutes. Your settings are put back at the end.")
                .font(.callout)
                .multilineTextAlignment(.center)
            if model.ggWarning {
                StatusBanner(style: .warning, message: "SteelSeries GG is running and can interfere with the results. Quit it first if you can.")
            }
            if model.family == nil {
                StatusBanner(style: .info, message: "Connect your mouse with the USB cable to start.")
            }
        }
    }

    private var footer: some View {
        HStack {
            if runner.isRunning, runner.phase != .restoring {
                Button("Skip") { runner.skip() }
            }
            Spacer()
            if runner.phase != .results {
                Button("Cancel") {
                    if runner.isRunning {
                        runner.cancel()
                    } else {
                        dismissWindow(id: "hardware-check")
                    }
                }
                .keyboardShortcut(.cancelAction)
                .disabled(runner.phase == .restoring)
            }
            primaryButton
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch runner.phase {
        case .idle:
            Button("Get started") { runner.start() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.family == nil)
        case .preflight:
            Button("Start check") { runner.beginTests() }
                .keyboardShortcut(.defaultAction)
        case .instructions(_, let title):
            Button(title) { runner.proceed() }
                .keyboardShortcut(.defaultAction)
        case .results:
            Button("Done") { dismissWindow(id: "hardware-check") }
                .keyboardShortcut(.defaultAction)
        default:
            EmptyView()
        }
    }
}
```

- [ ] **Step 6: Add the window scene to `Sources/MouseBar/MouseBarApp.swift`**

Replace the file with:

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
        Window("Hardware Check", id: "hardware-check") {
            CheckWindow(runner: CheckRunner.shared, model: model)
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 7: Add temporary entry points (replaced by Tasks 7 and 8)**

In `Sources/MouseBar/Views/MenuContent.swift`, insert before the `Button("Settings…")` block:
```swift
        Button("Hardware Check…") {
            openWindow(id: "hardware-check")
            NSApp.activate(ignoringOtherApps: true)
        }
```
In `Sources/MouseBar/Views/SettingsView.swift`, add `@Environment(\.openWindow) private var openWindow` to the struct and, inside the `if let family = model.family { ... }` branch right after the "Reset to factory defaults" `Section`, add:
```swift
                Section {
                    Button("Hardware Check…") {
                        openWindow(id: "hardware-check")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
```

- [ ] **Step 8: Build, suite, demo launch**

Run: `swift build --arch arm64 2>&1 | grep -E "warning|error" ; swift test 2>&1 | tail -3`, then the **Demo-launch procedure**.
Expected: no warnings/errors; 106 pass; demo runs 7 s with no crash.

- [ ] **Step 9: Commit**

```bash
git add Sources/MouseBar
git commit -m "feat(app): hardware check assistant window with capture box, preflight and results" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Menu bar label and dropdown panel

**Files:**
- Create: `Sources/MouseBar/Components/LEDSwatches.swift`, `Sources/MouseBar/Views/MenuPanel.swift`
- Replace: `Sources/MouseBar/Views/BatteryLabel.swift`, `Sources/MouseBar/MouseBarApp.swift`
- Delete: `Sources/MouseBar/Views/MenuContent.swift`

**Interfaces:**
- Consumes: Task 3 (`Theme`, `StatusBanner`, `SaveStatusLine`, `AppModel` state), Task 4 (`ValueFormat`)
- Produces: `LEDSwatches(selected: MouseCore.RGBColor?, onPick:)` (also used in Task 10), `MenuPanel(model:)`, UserDefaults key `showPercentage`

- [ ] **Step 1: Create `Sources/MouseBar/Components/LEDSwatches.swift`**

```swift
import SwiftUI
import MouseCore

/// Six preset LED colors as round, labelled swatch buttons.
struct LEDSwatches: View {
    static let presets: [(name: String, color: MouseCore.RGBColor)] = [
        ("Red", MouseCore.RGBColor(r: 255, g: 0, b: 0)),
        ("Orange", MouseCore.RGBColor(r: 255, g: 128, b: 0)),
        ("Green", MouseCore.RGBColor(r: 0, g: 255, b: 0)),
        ("Cyan", MouseCore.RGBColor(r: 0, g: 229, b: 255)),
        ("Blue", MouseCore.RGBColor(r: 0, g: 64, b: 255)),
        ("White", MouseCore.RGBColor(r: 255, g: 255, b: 255)),
    ]

    let selected: MouseCore.RGBColor?
    let onPick: (MouseCore.RGBColor) -> Void

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(Self.presets, id: \.name) { preset in
                let isSelected = selected == preset.color
                Button {
                    onPick(preset.color)
                } label: {
                    Circle()
                        .fill(preset.color.swiftUIColor)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().strokeBorder(.primary.opacity(isSelected ? 0.9 : 0.25), lineWidth: isSelected ? 2 : 1)
                        )
                        .frame(width: Theme.minHitTarget, height: Theme.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(preset.name)
                .accessibilityLabel(isSelected ? "\(preset.name), selected" : preset.name)
            }
        }
    }
}
```

- [ ] **Step 2: Replace `Sources/MouseBar/Views/BatteryLabel.swift`**

```swift
import SwiftUI
import MouseCore

/// The menu bar item: battery symbol, optional percentage, moon when asleep, red tint when low.
struct BatteryLabel: View {
    let state: BatteryState
    @AppStorage("showPercentage") private var showPercentage = true

    private var isLow: Bool {
        state.freshness != .disconnected && (state.level ?? 100) < 15 && state.isCharging != true
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: BatteryPresentation.symbolName(for: state))
            if state.freshness == .asleep {
                Image(systemName: Theme.Symbol.asleep)
            }
            if showPercentage, let title = BatteryPresentation.compactTitle(for: state) {
                Text(title).monospacedDigit()
            }
        }
        .foregroundStyle(isLow ? Color.red : Color.primary)
        .opacity(state.freshness == .asleep ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BatteryPresentation.detail(for: state, now: Date()))
    }
}
```

- [ ] **Step 3: Create `Sources/MouseBar/Views/MenuPanel.swift`**

```swift
import SwiftUI
import MouseCore

/// The menu bar dropdown: mouse and connection, battery gauge, quick controls, banners, save feedback, actions.
struct MenuPanel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showColors = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if let family = model.family {
                header
                battery
                Divider()
                quickControls(family)
                    .disabled(model.isCheckRunning)
            } else {
                emptyState
            }
            banners
            SaveStatusLine(state: model.saveState)
            Divider()
            footer
        }
        .padding(Theme.Space.l)
        .frame(width: 300)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: "computermouse.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(model.displayName ?? "Mouse")
                .font(.headline)
            Spacer()
            if let connection = model.connection {
                Label(connection.title, systemImage: connection.symbol)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                    .accessibilityLabel("Connected by \(connection.title)")
            }
        }
    }

    private var battery: some View {
        let state = model.battery
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                Gauge(value: Double(state.level ?? 0), in: 0...100) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(Theme.batteryColor(level: state.level))
                    .themedAnimation(state.level, reduceMotion: reduceMotion)
                Text(state.level.map { "\($0)%" } ?? "—")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(spacing: Theme.Space.xs) {
                    if state.isCharging == true {
                        Image(systemName: Theme.Symbol.charging).accessibilityHidden(true)
                    } else if state.freshness == .asleep {
                        Image(systemName: Theme.Symbol.asleep).accessibilityHidden(true)
                    }
                    Text(Self.statusLine(state, now: context.date))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery: \(BatteryPresentation.detail(for: state, now: Date()))")
    }

    @ViewBuilder private func quickControls(_ family: DeviceFamily) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if model.activePresetConfirmed, family.setting("sensitivity") != nil,
               case .dpiPresets(let presets, let selected)? = model.values["sensitivity"] {
                LabeledContent("DPI") {
                    Picker("DPI", selection: Binding(
                        get: { selected ?? 0 },
                        set: { model.submit("sensitivity", .dpiPresets(presets: presets, selected: $0)) }
                    )) {
                        ForEach(presets.indices, id: \.self) { index in
                            Text("\(presets[index])").tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            if let spec = family.setting("polling_rate") {
                LabeledContent("Polling") {
                    Picker("Polling rate", selection: Binding(
                        get: {
                            if case .choice(let c)? = model.values[spec.key] ?? DefaultSettings.value(for: spec) { return c }
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
            if let spec = family.setting("color") {
                LabeledContent("LED") {
                    let current: MouseCore.RGBColor? = {
                        if case .color(let c)? = model.values[spec.key] { return c }
                        return nil
                    }()
                    Button {
                        showColors.toggle()
                    } label: {
                        HStack(spacing: Theme.Space.s) {
                            Circle()
                                .fill(current?.swiftUIColor ?? .clear)
                                .overlay(Circle().strokeBorder(.secondary, lineWidth: 1))
                                .frame(width: 16, height: 16)
                            Text(current.map { "#" + $0.hexString.uppercased() } ?? "Not set")
                                .font(.callout)
                                .monospaced()
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("LED color \(current.map { "#" + $0.hexString.uppercased() } ?? "not set")")
                    .popover(isPresented: $showColors, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            LEDSwatches(selected: current) { model.submit(spec.key, .color($0)) }
                            ColorPicker("Custom color", selection: Binding(
                                get: { current?.swiftUIColor ?? .red },
                                set: { if let rgb = MouseCore.RGBColor(color: $0) { model.submit(spec.key, .color(rgb)) } }
                            ), supportsOpacity: false)
                        }
                        .padding(Theme.Space.m)
                    }
                }
            }
        }
    }

    @ViewBuilder private var banners: some View {
        if model.ggWarning {
            StatusBanner(
                style: .warning,
                message: "SteelSeries GG is running and can interfere. Quit it, or uninstall it with “SteelSeries GG Uninstaller”."
            )
        }
        if let problem = model.problem {
            StatusBanner(style: .error, message: problem, onDismiss: { model.problem = nil })
        }
        if let notice = model.notice {
            StatusBanner(style: .info, message: notice, onDismiss: { model.notice = nil })
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: Theme.Symbol.mouse)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Connect your mouse")
                .font(.headline)
            Text("Plug in the USB cable or the 2.4 GHz dongle.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.s)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Button("Hardware Check…") {
                    openWindow(id: "hardware-check")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Settings…") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",")
            }
            Button("Quit MouseBar") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
    }

    // MARK: Text

    /// "Charging · read just now", "Low · read 3 min ago", "Asleep · last 80%", "Reading battery…".
    static func statusLine(_ state: BatteryState, now: Date) -> String {
        switch state.freshness {
        case .disconnected:
            return "No mouse connected"
        case .asleep:
            return state.level.map { "Asleep · last \($0)%" } ?? "Asleep or out of range"
        case .fresh, .stale:
            guard let level = state.level else { return "Reading battery…" }
            var parts: [String] = []
            if state.isCharging == true { parts.append("Charging") }
            if level < 15 && state.isCharging != true { parts.append("Low") }
            if let read = state.lastReadAt {
                let minutes = Int(now.timeIntervalSince(read) / 60)
                parts.append(minutes < 1 ? "read just now" : "read \(minutes) min ago")
            }
            return parts.joined(separator: " · ")
        }
    }
}
```

- [ ] **Step 4: Replace `Sources/MouseBar/MouseBarApp.swift`**

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
            MenuPanel(model: model)
        } label: {
            BatteryLabel(state: model.battery)
        }
        .menuBarExtraStyle(.window)
        Window("Mouse Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
        Window("Hardware Check", id: "hardware-check") {
            CheckWindow(runner: CheckRunner.shared, model: model)
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 5: Delete the old menu**

Run: `git rm Sources/MouseBar/Views/MenuContent.swift`

- [ ] **Step 6: Build, suite, demo launch**

Run: `swift build --arch arm64 2>&1 | grep -E "warning|error" ; swift test 2>&1 | tail -3`, then the **Demo-launch procedure**.
Expected: no warnings/errors; 106 pass; demo runs 7 s with no crash (the demo mouse is a dongle at 50%: the menu bar shows 50%).

- [ ] **Step 7: Commit**

```bash
git add Sources/MouseBar
git commit -m "feat(app): menu bar panel with battery gauge, quick controls, banners and save feedback" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Settings in toolbar tabs — shell, Performance, Device

**Files:**
- Create: `Sources/MouseBar/Views/SettingEditors.swift`, `Sources/MouseBar/Views/DeviceTab.swift`
- Replace: `Sources/MouseBar/Views/SettingsView.swift`, `Sources/MouseBar/MouseBarApp.swift`
- Modify: `Sources/MouseBar/Views/MenuPanel.swift` (Settings button opens the Settings scene)

**Interfaces:**
- Consumes: Tasks 3, 4 (`SettingsTab`, `SettingsLayout`, `ValueFormat`, `DefaultCapsule`, `StatusBanner`, `SaveStatusLine`), existing `ColorRow`/`ButtonsRow` (until Tasks 9/10)
- Produces: `@MainActor func currentValue(_:_:) -> SettingValue?`, `SettingSection(title:isDefault:content:)`, `SettingEditor(model:spec:)`, `DPIEditor`, `ChoiceEditor`, `RangeEditor`, `DeviceTab(model:family:)`, `SettingsView(model:)` as a `Settings` scene

- [ ] **Step 1: Create `Sources/MouseBar/Views/SettingEditors.swift`**

```swift
import SwiftUI
import MouseCore

/// The value the UI shows: what MouseBar stored, or the factory default (the mouse can't be read).
@MainActor func currentValue(_ spec: SettingSpec, _ model: AppModel) -> SettingValue? {
    model.values[spec.key] ?? DefaultSettings.value(for: spec)
}

/// A form section titled with the friendly label and a Default capsule when MouseBar never set the value.
struct SettingSection<Content: View>: View {
    let title: String
    let isDefault: Bool
    @ViewBuilder let content: Content

    var body: some View {
        Section {
            content
        } header: {
            HStack(spacing: Theme.Space.s) {
                Text(title)
                if isDefault { DefaultCapsule() }
            }
        }
    }
}

/// Picks the editor for a setting's value type.
struct SettingEditor: View {
    let model: AppModel
    let spec: SettingSpec

    var body: some View {
        switch spec.valueType {
        case "multidpi_range_choice": DPIEditor(model: model, spec: spec)
        case "choice": ChoiceEditor(model: model, spec: spec)
        case "range": RangeEditor(model: model, spec: spec)
        case "rgbcolor": ColorRow(spec: spec, model: model)        // replaced by ColorEditor in Task 10
        case "buttons": ButtonsRow(spec: spec, model: model)       // replaced by ButtonsEditor in Task 9
        default:
            Text("This setting type (\(spec.valueType)) has no editor yet.")
                .foregroundStyle(.secondary)
        }
    }
}

struct ChoiceEditor: View {
    let model: AppModel
    let spec: SettingSpec

    var body: some View {
        Picker(SettingsLayout.label(for: spec), selection: Binding(
            get: {
                if case .choice(let c)? = currentValue(spec, model) { return c }
                return spec.defaultText
            },
            set: { model.submit(spec.key, .choice($0)) }
        )) {
            ForEach(spec.choices ?? [], id: \.key) { choice in
                Text(ValueFormat.choice(key: spec.key, choice.key)).tag(choice.key)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(SettingsLayout.label(for: spec))
    }
}

/// Slider that writes when dragging ends, with the value and its unit next to it.
struct RangeEditor: View {
    let model: AppModel
    let spec: SettingSpec
    @State private var draft: Double = 0

    var body: some View {
        let range = spec.inputRange ?? [0, 1, 1]
        HStack(spacing: Theme.Space.m) {
            Slider(value: $draft, in: Double(range[0])...Double(range[1]), step: Double(range[2])) { editing in
                if !editing { model.submit(spec.key, .int(Int(draft))) }
            }
            .accessibilityLabel(SettingsLayout.label(for: spec))
            .accessibilityValue(ValueFormat.range(key: spec.key, value: Int(draft)))
            Text(ValueFormat.range(key: spec.key, value: Int(draft)))
                .monospacedDigit()
                .frame(width: 84, alignment: .trailing)
        }
        .onAppear { sync() }
        .onChange(of: model.values[spec.key]) { _, _ in sync() }
    }

    private func sync() {
        if case .int(let value)? = currentValue(spec, model) { draft = Double(value) }
    }
}

/// One row per DPI preset: number badge, slider, value, stepper, active star (once confirmed), remove.
struct DPIEditor: View {
    let model: AppModel
    let spec: SettingSpec
    @State private var drafts: [Double] = []

    private var presets: [Int] {
        if case .dpiPresets(let p, _)? = currentValue(spec, model) { return p }
        return [800]
    }
    private var selected: Int {
        if case .dpiPresets(_, let s)? = currentValue(spec, model) { return s ?? 0 }
        return 0
    }
    private var maxCount: Int { spec.maxPresetCount ?? 5 }
    private var bounds: [Int] { spec.inputRange ?? [100, 18000, 100] }

    private func commit(_ next: [Int], selected: Int) {
        guard !next.isEmpty else { return }
        model.submit(spec.key, .dpiPresets(presets: next, selected: min(max(selected, 0), next.count - 1)))
    }

    private func value(at index: Int) -> Int {
        presets.indices.contains(index) ? presets[index] : bounds[0]
    }

    var body: some View {
        ForEach(presets.indices, id: \.self) { index in
            HStack(spacing: Theme.Space.m) {
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(.quaternary))
                    .accessibilityHidden(true)
                Slider(value: Binding(
                    get: { drafts.indices.contains(index) ? drafts[index] : Double(value(at: index)) },
                    set: { new in
                        if !drafts.indices.contains(index) { drafts = presets.map(Double.init) }
                        if drafts.indices.contains(index) { drafts[index] = new }
                    }
                ), in: Double(bounds[0])...Double(bounds[1]), step: Double(bounds[2])) { editing in
                    guard !editing, drafts.count == presets.count else { return }
                    commit(drafts.map { Int($0) }, selected: selected)
                }
                .accessibilityLabel("Preset \(index + 1)")
                .accessibilityValue(ValueFormat.dpi(value(at: index)))
                Text(ValueFormat.dpi(drafts.indices.contains(index) ? Int(drafts[index]) : value(at: index)))
                    .monospacedDigit()
                    .frame(width: 84, alignment: .trailing)
                Stepper("Preset \(index + 1)", value: Binding(
                    get: { value(at: index) },
                    set: { new in
                        guard presets.indices.contains(index) else { return }
                        var next = presets
                        next[index] = new
                        commit(next, selected: selected)
                    }
                ), in: bounds[0]...bounds[1], step: bounds[2])
                .labelsHidden()
                if model.activePresetConfirmed {
                    Button {
                        commit(presets, selected: index)
                    } label: {
                        Image(systemName: index == selected ? "star.fill" : "star")
                    }
                    .buttonStyle(.borderless)
                    .help("Make preset \(index + 1) the active preset")
                    .accessibilityLabel(index == selected ? "Preset \(index + 1), active" : "Make preset \(index + 1) active")
                }
                Button {
                    guard presets.indices.contains(index) else { return }
                    var next = presets
                    next.remove(at: index)
                    commit(next, selected: selected > index ? selected - 1 : selected)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(presets.count <= 1)
                .accessibilityLabel("Remove preset \(index + 1)")
            }
        }
        .onAppear { drafts = presets.map(Double.init) }
        .onChange(of: model.values[spec.key]) { _, _ in drafts = presets.map(Double.init) }
        Button {
            commit(presets + [min(presets.last ?? 800, bounds[1])], selected: selected)
        } label: {
            Label("Add preset", systemImage: "plus.circle")
        }
        .buttonStyle(.borderless)
        .disabled(presets.count >= maxCount)
    }
}
```

- [ ] **Step 2: Create `Sources/MouseBar/Views/DeviceTab.swift`**

```swift
import SwiftUI
import MouseCore

struct DeviceTab: View {
    let model: AppModel
    let family: DeviceFamily
    @AppStorage("showPercentage") private var showPercentage = true
    @State private var confirmReset = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Section("Mouse") {
            LabeledContent("Model", value: model.displayName ?? "—")
            LabeledContent("Connection") {
                if let connection = model.connection {
                    Label(connection.title, systemImage: connection.symbol)
                } else {
                    Text("—")
                }
            }
            LabeledContent("Battery", value: BatteryPresentation.detail(for: model.battery, now: Date()))
            LabeledContent("Profile", value: "rivalcfg \(model.rivalcfgVersion)")
        }
        Section("Menu bar") {
            Toggle("Show battery percentage", isOn: $showPercentage)
        }
        let others = SettingsLayout.otherSettings(in: family)
        if !others.isEmpty {
            ForEach(others) { spec in
                SettingSection(title: SettingsLayout.label(for: spec), isDefault: model.values[spec.key] == nil) {
                    SettingEditor(model: model, spec: spec)
                }
            }
        }
        Section("Diagnostics") {
            Button("Hardware Check…") {
                openWindow(id: "hardware-check")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        Section {
            Button("Reset to factory defaults…", role: .destructive) { confirmReset = true }
                .confirmationDialog("Reset every setting to the factory default?", isPresented: $confirmReset) {
                    Button("Reset", role: .destructive) { model.resetAll() }
                } message: {
                    Text("Rewrites every setting on the mouse and saves it. Your MouseBar settings are cleared.")
                }
        }
    }
}
```

- [ ] **Step 3: Replace `Sources/MouseBar/Views/SettingsView.swift`**

```swift
import SwiftUI
import MouseCore

/// Settings in toolbar tabs (a `Settings` scene renders `TabView` as toolbar tabs).
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            ForEach(SettingsTab.allCases) { tab in
                SettingsTabPage(model: model, tab: tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .frame(width: 560)
    }
}

struct SettingsTabPage: View {
    let model: AppModel
    let tab: SettingsTab

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let problem = model.problem {
                    Section {
                        StatusBanner(style: .error, message: problem, onDismiss: { model.problem = nil })
                    }
                }
                if let family = model.family {
                    if tab == .device {
                        DeviceTab(model: model, family: family)
                    } else {
                        ForEach(SettingsLayout.settings(for: tab, in: family)) { spec in
                            SettingSection(
                                title: SettingsLayout.label(for: spec), isDefault: model.values[spec.key] == nil
                            ) {
                                SettingEditor(model: model, spec: spec)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No mouse connected", systemImage: Theme.Symbol.mouse,
                        description: Text("Plug in the USB cable or the 2.4 GHz dongle.")
                    )
                }
            }
            .formStyle(.grouped)
            .disabled(model.isCheckRunning)
            HStack {
                SaveStatusLine(state: model.saveState)
                Spacer()
                if model.isCheckRunning {
                    Text("Hardware check in progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.windowPadding)
            .padding(.vertical, Theme.Space.s)
        }
        .frame(minHeight: 380)
    }
}
```

- [ ] **Step 4: Use the `Settings` scene in `Sources/MouseBar/MouseBarApp.swift`**

Replace the file with:
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
            MenuPanel(model: model)
        } label: {
            BatteryLabel(state: model.battery)
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView(model: model)
        }
        Window("Hardware Check", id: "hardware-check") {
            CheckWindow(runner: CheckRunner.shared, model: model)
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 5: Open the Settings scene from the panel**

In `Sources/MouseBar/Views/MenuPanel.swift`:
1. Add `@Environment(\.openSettings) private var openSettings` next to `openWindow`.
2. Replace the `Button("Settings…") { ... }` action body with:
```swift
                    // A menu bar app must activate first, or the Settings window opens behind other apps.
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
```

- [ ] **Step 6: Build, suite, demo launch**

Run: `swift build --arch arm64 2>&1 | grep -E "warning|error" ; swift test 2>&1 | tail -3`, then the **Demo-launch procedure**.
Expected: no warnings/errors; 106 pass; demo runs 7 s with no crash.

- [ ] **Step 7: Commit**

```bash
git add Sources/MouseBar
git commit -m "feat(app): settings in toolbar tabs with performance and device pages" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Buttons tab — diagram and list

**Files:**
- Create: `Sources/MouseBar/Views/MouseDiagram.swift`, `Sources/MouseBar/Views/ButtonsEditor.swift`
- Modify: `Sources/MouseBar/Views/SettingEditors.swift` (`case "buttons"` uses `ButtonsEditor`)

**Interfaces:**
- Consumes: `ButtonActionMenu`, `ButtonNames` (Task 4), `currentValue` (Task 8)
- Produces: `MouseDiagram(buttons: [ButtonSpec], mapping: ButtonMapping, selected: Binding<String?>)`, `ButtonsEditor(model:spec:)`

- [ ] **Step 1: Create `Sources/MouseBar/Views/MouseDiagram.swift`**

```swift
import SwiftUI
import MouseCore

/// A top-down mouse outline with a numbered marker on each button. Clicking a marker selects its row.
struct MouseDiagram: View {
    let buttons: [ButtonSpec]
    let mapping: ButtonMapping
    @Binding var selected: String?

    /// Marker positions in unit coordinates of the diagram (x right, y down).
    private static let positions: [String: CGPoint] = [
        "button1": CGPoint(x: 0.30, y: 0.20),
        "button2": CGPoint(x: 0.70, y: 0.20),
        "button3": CGPoint(x: 0.50, y: 0.21),
        "scrollup": CGPoint(x: 0.50, y: 0.08),
        "scrolldown": CGPoint(x: 0.50, y: 0.34),
        "button6": CGPoint(x: 0.50, y: 0.46),
        "button5": CGPoint(x: 0.07, y: 0.40),
        "button4": CGPoint(x: 0.07, y: 0.55),
    ]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                outline(in: size)
                ForEach(Array(buttons.enumerated()), id: \.element.name) { index, button in
                    let key = button.name.lowercased()
                    if let point = Self.positions[key] {
                        marker(number: index + 1, key: key, button: button)
                            .position(x: point.x * size.width, y: point.y * size.height)
                    }
                }
            }
        }
        .aspectRatio(0.62, contentMode: .fit)
    }

    private func outline(in size: CGSize) -> some View {
        let body = CGRect(x: size.width * 0.12, y: 0, width: size.width * 0.76, height: size.height)
        return ZStack {
            RoundedRectangle(cornerRadius: body.width * 0.48)
                .strokeBorder(.secondary, lineWidth: 1.5)
                .frame(width: body.width, height: body.height)
                .position(x: body.midX, y: body.midY)
            Path { path in
                path.move(to: CGPoint(x: body.midX, y: 0))
                path.addLine(to: CGPoint(x: body.midX, y: size.height * 0.40))
                path.move(to: CGPoint(x: body.minX + 6, y: size.height * 0.40))
                path.addLine(to: CGPoint(x: body.maxX - 6, y: size.height * 0.40))
            }
            .stroke(.secondary.opacity(0.6), lineWidth: 1)
            Capsule()
                .fill(.quaternary)
                .frame(width: size.width * 0.09, height: size.height * 0.16)
                .position(x: body.midX, y: size.height * 0.21)
            RoundedRectangle(cornerRadius: 3)
                .fill(.quaternary)
                .frame(width: size.width * 0.06, height: size.height * 0.10)
                .position(x: body.minX + 2, y: size.height * 0.40)
            RoundedRectangle(cornerRadius: 3)
                .fill(.quaternary)
                .frame(width: size.width * 0.06, height: size.height * 0.10)
                .position(x: body.minX + 2, y: size.height * 0.55)
        }
        .accessibilityHidden(true)
    }

    private func marker(number: Int, key: String, button: ButtonSpec) -> some View {
        let isSelected = selected == key
        let action = mapping.assignments[key] ?? "default"
        let actionText = action == "default"
            ? "default, \(ButtonNames.actionName(button.defaultAction))"
            : ButtonNames.actionName(action)
        return Button {
            selected = key
        } label: {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 18, height: 18)
                .background(Circle().fill(isSelected ? Color.accentColor : Color(nsColor: .windowBackgroundColor)))
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1.5))
                .frame(width: Theme.minHitTarget, height: Theme.minHitTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Button \(number), \(ButtonNames.name(button.name)), mapped to \(actionText)")
    }
}
```

- [ ] **Step 2: Create `Sources/MouseBar/Views/ButtonsEditor.swift`**

```swift
import SwiftUI
import MouseCore

/// The Buttons tab: diagram on the left, numbered list with friendly names and action menus on the right.
struct ButtonsEditor: View {
    let model: AppModel
    let spec: SettingSpec
    @State private var selected: String?

    private var mapping: ButtonMapping {
        if case .buttons(let m)? = currentValue(spec, model) { return m }
        return ButtonMapping()
    }

    private var buttons: [ButtonSpec] { spec.buttons ?? [] }

    private func set(_ button: ButtonSpec, to token: String) {
        var assignments = mapping.assignments
        assignments[button.name.lowercased()] = token
        model.submit(spec.key, .buttons(ButtonMapping(assignments: assignments)))
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.xl) {
            MouseDiagram(buttons: buttons, mapping: mapping, selected: $selected)
                .frame(width: 130)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(Array(buttons.enumerated()), id: \.element.name) { index, button in
                    let key = button.name.lowercased()
                    HStack(spacing: Theme.Space.s) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(selected == key ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15)))
                            .accessibilityHidden(true)
                        Text(ButtonNames.name(button.name))
                        Spacer()
                        ButtonActionMenu(
                            spec: spec, button: button,
                            token: mapping.assignments[key] ?? "default",
                            layouts: model.layouts
                        ) { set(button, to: $0) }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, Theme.Space.xs)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected == key ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selected = key }
                }
                Button("Restore defaults") {
                    model.submit(spec.key, .buttons(ButtonMapping()))
                }
                .padding(.top, Theme.Space.s)
            }
        }
    }
}
```

- [ ] **Step 3: Use it in `Sources/MouseBar/Views/SettingEditors.swift`**

Replace the line
```swift
        case "buttons": ButtonsRow(spec: spec, model: model)       // replaced by ButtonsEditor in Task 9
```
with
```swift
        case "buttons": ButtonsEditor(model: model, spec: spec)
```

- [ ] **Step 4: Build, suite, demo launch**

Run: `swift build --arch arm64 2>&1 | grep -E "warning|error" ; swift test 2>&1 | tail -3`, then the **Demo-launch procedure**.
Expected: no warnings/errors; 106 pass; demo runs 7 s with no crash.

- [ ] **Step 5: Commit**

```bash
git add Sources/MouseBar/Views
git commit -m "feat(app): buttons tab with mouse diagram, friendly names and action menus" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Lighting editor, cleanup, README

**Files:**
- Create: `Sources/MouseBar/Views/ColorEditor.swift`
- Modify: `Sources/MouseBar/Views/SettingEditors.swift` (`case "rgbcolor"` uses `ColorEditor`), `README.md`
- Delete: `Sources/MouseBar/Views/SettingRows.swift`

**Interfaces:**
- Consumes: `LEDSwatches` (Task 7), `currentValue` (Task 8)
- Produces: `ColorEditor(model:spec:)`

- [ ] **Step 1: Create `Sources/MouseBar/Views/ColorEditor.swift`**

```swift
import SwiftUI
import MouseCore

/// LED color: system color well, six preset swatches, and the hex code.
struct ColorEditor: View {
    let model: AppModel
    let spec: SettingSpec

    private var color: MouseCore.RGBColor {
        if case .color(let c)? = currentValue(spec, model) { return c }
        return MouseCore.RGBColor(r: 255, g: 0, b: 0)
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ColorPicker("LED color", selection: Binding(
                get: { color.swiftUIColor },
                set: { if let rgb = MouseCore.RGBColor(color: $0) { model.submit(spec.key, .color(rgb)) } }
            ), supportsOpacity: false)
            .labelsHidden()
            LEDSwatches(selected: color) { model.submit(spec.key, .color($0)) }
            Spacer()
            Text("#" + color.hexString.uppercased())
                .font(.callout)
                .monospaced()
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .accessibilityLabel("Hex code \(color.hexString.uppercased())")
        }
    }
}
```

- [ ] **Step 2: Use it and remove the old rows**

In `Sources/MouseBar/Views/SettingEditors.swift` replace
```swift
        case "rgbcolor": ColorRow(spec: spec, model: model)        // replaced by ColorEditor in Task 10
```
with
```swift
        case "rgbcolor": ColorEditor(model: model, spec: spec)
```
Then run `git rm Sources/MouseBar/Views/SettingRows.swift`. Build: if anything still references `SettingRow`, `ChoiceRow`, `RangeRow`, `ColorRow`, `DPIRow`, `ButtonsRow` or the old private `current(_:_:)`, switch it to the Task 8 editors / `currentValue(_:_:)`.

- [ ] **Step 3: Update `README.md`**

Add a section after the existing "Settings" section:
```markdown
## Interface

- **Menu bar:** battery symbol and percentage (hide the percentage in Settings → Device). It turns red when low and shows a moon while the mouse sleeps.
- **Panel:** click the menu bar item for the mouse, its connection (Cable or 2.4 GHz), a battery gauge, quick polling-rate and LED controls, warnings, and "Saving to mouse… / Saved to mouse" feedback. A DPI switch appears once the hardware check has confirmed that the mouse accepts an active-preset change.
- **Settings (⌘,):** tabs for Performance (DPI presets, polling rate), Buttons (diagram plus per-button actions, including media and keyboard keys), Lighting, Power, and Device (info, Hardware Check, reset). A "Default" tag marks values MouseBar has never set.
- **Hardware Check:** from the panel or Settings → Device. It walks you through 9 short steps on your real mouse (battery over cable and dongle, LED, polling rate, buttons, DPI, saving, wake) and writes a Markdown report to `~/Library/Application Support/MouseBar/reports/`. Your settings are restored when it finishes, when you cancel or quit, or at the next launch after a crash.
```

- [ ] **Step 4: Build, suite, demo launch**

Run: `swift build --arch arm64 2>&1 | grep -E "warning|error" ; swift test 2>&1 | tail -3`, then the **Demo-launch procedure**.
Expected: no warnings/errors; 106 pass; demo runs 7 s with no crash.

- [ ] **Step 5: Commit**

```bash
git add -A Sources/MouseBar README.md
git commit -m "feat(app): lighting editor with swatches; remove old setting rows; README interface section" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## After the plan (owner, not part of this execution)

The spec's section 6 follow-ups depend on the owner running the wizard on the real mouse: enable the dongle echo filter with the observed byte, confirm save persistence in the README, re-apply color last if it is hidden by the rainbow, and copy the report into `docs/superpowers/notes/`. The active-preset picker and quick DPI switch are already gated on the wizard's result (`activePresetConfirmed`).
