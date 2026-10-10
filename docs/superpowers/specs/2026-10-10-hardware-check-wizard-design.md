# Hardware Check wizard and active DPI preset

Date: 2026-10-10
Status: draft, awaiting owner review
Branch: `feat/hardware-check-wizard` (from `feat/mousebar-phase0-2` at `ccd9fe3`)

## 1. Purpose and success criteria

MouseBar works on the owner's SteelSeries Prime Mini Wireless, but only the read-only path is proven on hardware (cable: enumeration, open, battery). Settings writes, the 2.4 GHz dongle, persistence in the mouse's memory and active DPI preset selection are unverified, and every write row in `docs/superpowers/notes/2026-10-10-hardware-verification.md` says `NOT RUN`.

This sub-project adds an in-app **Hardware Check** wizard that walks the owner through those checks on the real mouse, using the app's own live session, records the results in a report, and restores the owner's settings afterwards. The results then drive three small code follow-ups (section 6).

Success means:

1. The wizard runs every check in section 3 on the real mouse and writes a report.
2. After the wizard (finished, cancelled, window closed, app quit or crashed), the mouse is back to the owner's settings: the values MouseBar stores plus the DPI presets and button remaps the owner entered.
3. Every `NOT RUN` row in the hardware note gets a real result from the report.
4. If the report confirms it: the dongle battery reply is echo-filtered like the cable's, and the app has an "Active preset" picker and a quick DPI switch in the menu.
5. HID traffic can be inspected with Console.app (debug-level log of every report sent and received).

Non-goals: support for other mice, launch at login, profiles, notarization, a battery-history feature. No new unit tests are written for this sub-project (owner's decision); see section 7.

## 2. Constraints

- arm64-only, macOS 14+, SwiftPM, Swift 6.4. `MouseCore` stays Swift 6 language mode, strict-concurrency clean, zero warnings.
- The wizard uses the app's live `MouseSession` / `MouseDevice` (no second connection to the mouse).
- Commands to the mouse stay spaced at least 50 ms apart (the existing `MouseDevice` FIFO lock).
- Wizard test writes are transient: never stored in the settings file, never saved to the mouse except in the save-persistence check, which restores and saves afterwards.
- Button validation (`validateButtons`: a mapping must keep a primary click) stays in force for every write.
- The wizard never runs a step that writes to the mouse without the owner pressing a button for that step.

## 3. The checks

Steps run in this order. Each ends as `pass`, `fail` or `skipped`, with a short detail text and, where relevant, raw bytes in hex. Every step has Skip; the whole check has Cancel.

| # | Step | What the wizard does | How the result is decided |
|---|---|---|---|
| 0 | Preflight | Requires a connected supported mouse. Warns (continue allowed) if `SteelSeriesEngine` is running. Asks for the owner's current DPI presets (1 to 5 values, 100 to 18000, step 100) and button remaps (per button: factory default or an action, same choices as the Settings window), with an "I don't know, use factory defaults" option. Writes the restore snapshot (section 5) before anything else. | Pass when the snapshot file is written. |
| 1 | Battery, cable | Requires the cable. Sends the battery query and captures the raw 64-byte reply. | Pass when byte 0 is `0x92` and the decoded level is in 0...100. Raw hex kept. |
| 2 | Battery, dongle | Asks the owner to plug in the dongle and unplug the cable; waits (up to 2 minutes) until the active connection is the wireless model; captures the raw `0xD2` reply. | Records byte 0 and the decoded level. Pass when the decoded level is in 0...100. The report states whether byte 0 equals `0xD2`, `0x92` or neither. |
| 3 | LED color | Sets blue (`0000ff`), asks "Is the LED blue?"; sets green (`00ff00`), asks "Is the LED green?". | Owner's Yes/No answers. |
| 4 | Polling rate | Sets 125 Hz; owner moves the mouse in circles inside a capture box for 3 s while the wizard counts mouse-move events with event coalescing turned off; then the same at 1000 Hz. | Pass when the 1000 Hz rate is at least 3 times the 125 Hz rate. Both measured rates are recorded. |
| 5 | Buttons | Maps side button 4 to keyboard key F18 (layout code `0x6D`); asks the owner to press side button 4 inside the capture box. Then tries `button1 = disabled` through the normal validation path. | Pass when the F18 key event arrives within 15 s, and the `button1 = disabled` attempt is rejected with nothing written (owner clicks Continue with the left button). |
| 6 | DPI and active preset | Writes presets `[400, 3200]` with preset 1 active; asks "Is the pointer slow?"; then the same presets with preset 2 active; asks "Is the pointer fast now?". | Pass when both answers are Yes. This result decides whether the Active preset picker ships (section 6). |
| 7 | Save persistence | Sets startup lighting `off` and saves to the mouse. Asks the owner to switch the mouse off and on, then "Did the LED stay off at startup?". | Owner's answer. |
| 8 | Wake re-apply (dongle) | Requires the dongle. Battery polling is 5 s while the wizard is open. Asks the owner to switch the mouse off, wait until the wizard shows "mouse asleep", then switch it on. | Pass when the wizard sees the asleep-to-fresh transition and the owner answers Yes to "Is your LED color back?". |

After the last step: restore (section 5), then show the report with "Copy report" and "Reveal in Finder".

## 4. Components

### MouseCore (no UI, no IOKit)

- `HardwareCheck/CheckStep.swift`: `CheckStepID` (the steps above), `StepOutcome` (`pass`, `fail`, `skipped`, detail text, optional raw hex, optional measurements).
- `HardwareCheck/CheckReport.swift`: Codable report (date, app version, mouse model, connection per step, outcomes) and a Markdown rendering.
- `HardwareCheck/PollingRateEstimator.swift`: turns a list of event timestamps into a rate in Hz (median interval; ignores gaps longer than 100 ms).
- `HardwareCheck/RestoreSnapshot.swift`: Codable snapshot (stored values plus owner-entered DPI presets and button remaps), its file location (`~/Library/Application Support/MouseBar/check-restore.json`), and the ordered list of writes needed to restore.
- `MouseDevice.rawBatteryQuery() -> [UInt8]?`: flush, send the battery command, return the first report as raw bytes (no decoding, no echo filter), all under the existing FIFO lock.
- `MouseSession` additions:
  - `applyTransient(_ key:, _ value:)`: validate, write to the mouse; does not change `values`, the store, or schedule a save.
  - `saveNow()`: sends the family's save command immediately (under the device lock).
  - `setPollInterval(_:)`: restarts the battery loop with a new interval; the session's default stays 60 s.
  - `rawBatteryQuery()`: forwards to the device.
- HID logging: an `os.Logger` (subsystem `dev.mousebar.MouseBar`, category `hid`) in `MouseDevice` logs every payload written and every report read, in hex, at debug level.

### MouseBar (SwiftUI)

- `HardwareCheck/CheckRunner.swift` (`@MainActor @Observable`): owns the current step, outcomes, and the snapshot; drives the steps through the active session obtained from `AppModel`; reacts to connection and battery changes published by `AppModel`.
- `HardwareCheck/CheckWindow.swift` and one small view per step (instructions, the action button, Yes/No buttons or the capture box, Skip, Cancel).
- `HardwareCheck/EventCaptureBox.swift` (`NSViewRepresentable`): counts `mouseMoved` events (sets `NSEvent.isMouseCoalescingEnabled = false` while measuring, restores the previous value after) and reports key-down events (F18).
- `AppModel` additions: `isCheckRunning` (Settings window controls are disabled while true), access to the active session for the runner, and a published connection description (model, wired or wireless).
- Entry points: "Hardware Check…" item in the menu bar menu and a button at the bottom of the Settings window. Window scene id `hardware-check`.

## 5. Safety and restore

- **Snapshot first.** Step 0 writes `check-restore.json` before any write: the session's stored values plus the owner's DPI presets and button remaps (or factory defaults if the owner chose "I don't know").
- **Restore** writes, through the normal `set` path (so they are stored and validated): the owner's DPI presets (active preset 1), button map, LED color, startup lighting, polling rate, then `saveNow()`, then deletes the snapshot file.
- **Restore triggers:** finishing, Cancel, closing the wizard window, quitting the app (the quit timeout becomes 5 s while a restore is pending), and the next app launch if `check-restore.json` still exists (crash or force-quit). The launch-time restore runs when a supported mouse connects.
- **Disconnect mid-step:** the step is marked `fail` with "mouse disconnected", the wizard pauses with Retry and Skip; restore waits for the mouse to reconnect.
- **Concurrent edits:** the Settings window is read-only while the check runs, so no user edit interleaves with test writes.
- **Button safety:** step 5 never touches button 1 except the rejection attempt, which goes through validation and is refused before any write.

## 6. Follow-ups decided by the report

These are part of this sub-project and are done after the owner has run the wizard:

1. Dongle echo filter: if step 2 shows byte 0 is the command echo, enable the battery echo filter for the wireless model with the observed byte. If not, keep the dongle unfiltered and document the observed layout.
2. Active preset: if step 6 passes, add the "Active preset" picker to the DPI section of the Settings window and a quick DPI switch to the menu (the code drafted in the phase 0-2 plan, Task 13 Step 4), and stop forcing `selected` to 0. If it fails, keep them out and document it.
3. Save persistence: if step 7 passes, the README states that saves persist on the mouse; if not, investigate the save command before claiming it.
4. Color over rainbow: if the owner reports the stored color is hidden by the rainbow startup lighting after relaunch, re-apply non-persisted settings (color) after the others on connect.
5. Update `docs/superpowers/notes/2026-10-10-hardware-verification.md` from the report.

## 7. Verification

No new unit tests (owner's decision). Verification is:

- `swift build --arch arm64` with zero warnings.
- The existing test suite (`swift test`, 106 tests) still passes, as a regression check.
- A `--demo` launch: the wizard opens, every step can be stepped through against the simulated mouse, Cancel triggers restore, and no file is written to the real `~/Library/Application Support/MouseBar` in demo mode.
- The owner's hardware run of the wizard is the hardware verification; its report is committed to `docs/superpowers/notes/`.

## 8. Risks

- macOS may still deliver fewer mouse-move events than the device polling rate even with coalescing off; the pass rule is relative (1000 Hz at least 3 times 125 Hz) to tolerate that.
- The dongle's reply layout is unknown; step 2 records it without assuming an echo.
- A restore can only bring back what the snapshot knows; DPI presets and button remaps depend on the owner's entries in step 0.
- If `0x27` (startup lighting) also changes the live LED mode, step 3 or 8 answers may be affected; the report records the order of writes.
