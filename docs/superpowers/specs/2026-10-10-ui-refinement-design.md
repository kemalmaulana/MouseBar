# MouseBar UI refinement

Date: 2026-10-10
Status: approved by the owner in conversation (2026-10-10)
Branch: `feat/hardware-check-wizard`
Related: `docs/superpowers/specs/2026-10-10-hardware-check-wizard-design.md` (built first; it uses the theme from section 2)

## 1. Purpose and success criteria

MouseBar's UI today is functional but raw: a plain text dropdown, one tall Settings form with rivalcfg labels ("Button4", "scrollup"), long captions, and an error shown in a red section. This refinement makes it feel like a native macOS utility, consistent in light and dark mode, readable at a glance, and usable with VoiceOver and the keyboard.

Success means:

1. The menu bar dropdown is a panel with the mouse, connection, battery gauge, quick controls, warnings, save feedback and actions.
2. Settings is split into five toolbar tabs, each fitting without scrolling at the default window size.
3. Every setting and button has a friendly name; values show units ("1000 Hz", "5 min", "Off").
4. No status is shown by color alone; every icon and control has an accessibility label; keyboard focus works everywhere; Reduce Motion disables animations.
5. The owner sees when a change is being saved to the mouse, when it is saved, and when saving failed.

Non-goals: custom fonts, a fixed brand color, an always-dark theme, new mouse features, support for other mice.

## 2. Design system (`Sources/MouseBar/Theme.swift`)

- Identity: native. System accent color, system materials, light and dark follow macOS. SF Pro text styles only (`.title3`, `.headline`, `.callout`, `.body`, `.caption`); no fixed point sizes. `.monospacedDigit()` for every number; `.monospaced()` (SF Mono) for hex color codes.
- Spacing tokens: 4, 8, 12, 16, 24. Corner radius 10. Window content padding 20. Minimum hit target 28 pt.
- Battery colors: level above 40% green, 15 to 40% orange, below 15% red. Status colors: pass green, warning orange, fail red.
- Color is never the only signal: every status pairs its color with an SF Symbol and a word ("Low", "Charging", "Asleep", "Passed", "Failed", "Skipped").
- Motion: 200 to 250 ms ease-in-out for gauge and step transitions; instant when `accessibilityReduceMotion` is on.
- Symbols: `bolt.fill` charging, `cable.connector` cable, `antenna.radiowaves.left.and.right` dongle, `moon.zzz.fill` asleep, `battery.0percent` low, `exclamationmark.triangle.fill` warning, `xmark.octagon.fill` error, `checkmark.circle.fill` pass, `xmark.circle.fill` fail, `minus.circle` skipped.
- Shared components: `StatusBanner` (icon, message, optional action, optional dismiss; warning and error styles), `DefaultCapsule` (small "Default" capsule with a help tooltip), `SaveStatusLine` (`Saving to mouse…`, `✓ Saved to mouse`, or hidden).

## 3. Menu bar item

- Template SF Symbol for the battery level plus the percentage text.
- Below 15%: red `battery.0percent` symbol and the percentage; charging: `bolt.fill` variant; asleep: dimmed with `moon.zzz.fill`; no mouse: `computermouse`.
- "Show percentage" preference (UserDefaults key `showPercentage`, default on) hides the text.

## 4. Dropdown panel

`MenuBarExtra` with `.menuBarExtraStyle(.window)`, 300 pt wide, system material background, padding 16.

1. Header: mouse symbol, model name without the "(wired mode)" / "(2.4 GHz wireless mode)" suffix, and a badge: **Cable** (`cable.connector`) or **2.4 GHz** (`antenna.radiowaves.left.and.right`).
2. Battery: linear `Gauge` tinted by level, large percentage, status line ("Charging · read 1 min ago", "Asleep · last 80%", "Reading battery…").
3. Quick controls: polling rate segmented control (Hz) and LED color swatch opening a color popover. The DPI segmented control appears only when active-preset selection has been confirmed (a flag the hardware check sets; until then hidden).
4. Banners: SteelSeries GG running (warning, recommends quitting or uninstalling GG); errors (error style, dismissable).
5. Save feedback line (section 2).
6. Empty state when no mouse is connected: symbol, "Connect your mouse", and the Input Monitoring hint when opening failed.
7. Footer: "Hardware Check…", "Settings…" (⌘,), "Quit MouseBar" (⌘Q).

## 5. Settings window: toolbar tabs

A `TabView` with five tabs, each a grouped `Form`: **Performance** (`speedometer`), **Buttons** (`computermouse`), **Lighting** (`lightbulb`), **Power** (`powersleep`), **Device** (`info.circle`). Fixed width 560 pt; height fits the tab. An app-side `SettingsLayout` table maps each profile setting key to a tab, an order and a friendly label; unknown keys appear in an "Other" section of the Device tab, so the UI stays data-driven.

Common behavior: settings MouseBar has never set show a `DefaultCapsule` next to their section title (tooltip: "The mouse can't report its settings. This shows the factory default; changing it writes it to the mouse."). Errors appear as a `StatusBanner` at the top of the current tab. The `SaveStatusLine` sits at the bottom of every tab.

- **Performance**
  - DPI presets: one row per preset with a number badge (1 to 5), the value (monospaced), a slider (100 to 18000, step 100) and a stepper; "Add preset" (up to 5) and remove per row (at least 1). A ★ marks the active preset only when active-preset selection is confirmed.
  - Polling rate: segmented control with "Hz".
- **Buttons**
  - Left: a drawn top-down mouse outline (SwiftUI `Path`) with numbered markers on each button; clicking a marker selects its row.
  - Right: a list of the eight buttons with numbers and friendly names (Left click, Right click, Middle click, Side back, Side forward, DPI button, Scroll up, Scroll down) and an action menu per button, grouped Mouse (the other buttons, Cycle DPI, Scroll up, Scroll down, Disabled), Media (Play/Pause, Next, Previous, Volume up, Volume down, Mute), and "Keyboard key…" which opens a searchable popover of the keyboard layout keys.
  - "Restore defaults" button (writes the factory map).
- **Lighting**: LED color well plus six preset swatches; startup lighting segmented (Off, Rainbow); dim timer slider labelled "Off", seconds below 60, minutes from 60.
- **Power**: sleep timer slider labelled "Never" at 0, minutes otherwise.
- **Device**: model, connection, battery, rivalcfg profile version; "Show percentage in menu bar" toggle; "Hardware Check…" button; "Reset to factory defaults…" (destructive). The confirmation says "Rewrites every setting on the mouse and saves it. Your MouseBar settings are cleared."

## 6. Save feedback

`MouseSession` reports save progress to the app: `saving` when the debounced save starts, `saved` when the save command succeeded, `failed(message)` when it failed. The app shows `Saving to mouse…`, then `✓ Saved to mouse` for 3 seconds, or an error banner. Settings that are not saved on the device (LED color) show nothing.

## 7. Accessibility and motion

- `.accessibilityLabel` on every icon, badge, gauge ("Battery 95 percent, charging"), marker ("Button 4, Side back, mapped to Play/Pause"), swatch and capsule; decorative symbols are hidden from accessibility.
- Semantic controls only (`Button`, `Toggle`, `Picker`, `Slider`, `Stepper`, `Gauge`); default focus rings kept; every control reachable by keyboard; Escape closes popovers.
- `@Environment(\.accessibilityReduceMotion)` turns gauge and transition animations off.

## 8. Verification

No new unit tests (owner's decision). Verification: `swift build --arch arm64` with zero warnings, the existing test suite still passes, and a `--demo` launch of the app with no crash. The owner reviews the look on the real mouse.
