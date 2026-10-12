# MouseBar

Unofficial and not affiliated with SteelSeries.

A native Apple Silicon menu bar app for SteelSeries mice, and a Logitech G304 on a Lightspeed receiver (Logitech: untested on hardware): battery level at the top right of the screen and the mouse's settings in a window. It does not use SteelSeries GG.

Status: v0.1, early. Hardware-tested so far on one mouse (SteelSeries Prime Mini Wireless, USB cable): enumeration, opening the control interface and reading the battery (matches rivalcfg). Changing settings from the app, the 2.4 GHz dongle, and saving to the mouse's memory are implemented and unit-tested against rivalcfg's byte output but NOT yet verified on hardware. Other mice are untested (the Prime Wireless profile is included but unverified).

Logitech support is NOT yet verified on hardware: the G304 has only been enumerated (the receiver and the mouse were found), never read. See [Logitech mice](#logitech-mice).

## Build and run

    Scripts/build-logi.sh        # once, and after Rust/ changes: builds Vendor/MouseBarLogi.xcframework
    Scripts/bundle.sh release
    open build/MouseBar.app

`Scripts/build-logi.sh` must run before any `swift build`, `swift test` or `Scripts/bundle.sh`: `Package.swift` links the Rust library as a binary target, so SwiftPM cannot even load the package without `Vendor/MouseBarLogi.xcframework` (git-ignored). `Scripts/bundle.sh` stops with a message when it is missing.

Requires macOS 14+, Xcode 27 or Swift 6.4, and an arm64 Mac, plus Rust (stable, via [rustup](https://rustup.rs)) for the Logitech library. To try the UI with a simulated mouse (nothing is sent to a real one), run `open build/MouseBar.app --args --demo`.

There is no launch-at-login yet; add the app to System Settings > General > Login Items by hand.

If SteelSeries GG is installed, quit it first and consider uninstalling it: both programs talk to the same device. A battery read can return a report that is not the battery answer while GG's engine runs (seen once; likely GG's traffic). MouseBar ignores such reports on the cable.

## Logitech mice

Supported: the Logitech G304 on its Lightspeed receiver, through [OpenLogi](https://github.com/AprilNEA/OpenLogi)'s HID++ crates. **Not yet verified on hardware.** So far a check that changed no mouse setting only enumerated the receiver (`046d:c53f`) and found the G304 (wpid `4074`) offline (asleep or off); nothing has been read from it and nothing written. See `docs/superpowers/notes/2026-10-12-logitech-g304-verification.md`.

What it is built to do (none of it seen on a real G304 yet):

- **Battery** in the menu bar and panel, read from the mouse.
- **DPI** (Settings) and **polling rate** (Settings and panel). The window shows what the mouse reports (no "Default" tag for those two), and the supported values come from the mouse.
- **Mouse picker:** with more than one mouse connected (a SteelSeries and a Logitech), the name in the panel header opens a menu to pick which one the menu bar and Settings show. MouseBar remembers the choice.
- **Conflict banner:** the panel warns if Logitech G HUB, Logi Options+ or the OpenLogi agent was running when MouseBar launched (it checks once). They all talk to the same receiver and fight MouseBar. Quit them first. MouseBar never quits another app for you.

Every DPI or polling rate change is built to be written to the mouse and then read back, and if the mouse reports a different value, to show an error instead of pretending it worked (not yet seen on hardware). The G304 has onboard profiles: in onboard mode the mouse may ignore or override these writes, and the read-back is meant to show it. Values you set are meant to be sent again when the mouse reconnects or wakes (implemented, not yet seen on hardware).

There is no factory reset for a Logitech mouse. Settings → Device → "Forget MouseBar's settings for this mouse…" only makes MouseBar stop re-applying the DPI and polling rate it saved: nothing is written to the mouse, which keeps its current settings, and the window then shows what the mouse reports.

To check your own G304 without changing any mouse setting, wake it (switch on, fresh AA battery) and run `swift run logiprobe`: it prints the library version, the paired devices, and for each online one its DPI, polling rate and battery. It changes no mouse setting; like Solaar, it asks the receiver to re-announce its devices (OpenLogi's enumeration sets the receiver's wireless-notification flag in the receiver's working memory and triggers its device-arrival notifications).

## Settings

For SteelSeries mice: DPI presets (up to 5), polling rate, LED color, button remapping, sleep and dim timers, startup lighting, factory reset. A Logitech mouse has only DPI and polling rate (see [Logitech mice](#logitech-mice)).

- Settings are re-applied when the mouse (re)connects, except DPI presets: those stay in the mouse's own memory and the app does not re-send them.
- LED color is not stored on the mouse. MouseBar re-applies it when the mouse connects or wakes.
- The other settings are sent to the mouse, and a save command follows about 2 seconds after your last change. This is the design; whether the mouse keeps them after a power cycle is not yet verified on hardware.
- SteelSeries only: the mouse cannot report its current settings, so the window shows factory defaults for anything MouseBar has not set. The first change to a DPI preset or button rewrites the whole list or map (and saves it).

## Interface

- **Menu bar:** battery symbol and percentage (hide the percentage in Settings → Device). It may turn red when low (tint not yet verified in the menu bar) and shows a moon while the mouse sleeps.
- **Panel:** click the menu bar item for the mouse, its connection (Cable or 2.4 GHz), a battery gauge, quick polling-rate and LED controls, warnings, and "Saving to mouse… / Saved to mouse" feedback. A DPI switch appears once the hardware check has confirmed that the mouse accepts an active-preset change.
- **Settings (⌘,):** for a SteelSeries mouse, tabs for Performance (DPI presets, polling rate), Buttons (diagram plus per-button actions, including media and keyboard keys), Lighting, Power, and Device (info, Hardware Check, reset). A "Default" tag marks values MouseBar has never set (SteelSeries only; a Logitech mouse reports its values). For a Logitech mouse only Performance (DPI, polling rate) and Device (info, "Forget MouseBar's settings…") appear.
- **Hardware Check** (SteelSeries mice only; it is not offered for a Logitech mouse): from the panel or Settings → Device. It walks you through 9 short steps on your real mouse (battery over cable and dongle, LED, polling rate, buttons, DPI, saving, wake) and writes a Markdown report to `~/Library/Application Support/MouseBar/reports/`. MouseBar puts back the settings it has stored and the DPI presets and button remaps you enter here. Everything else goes back to factory defaults, and the active DPI preset becomes preset 1. This happens when it finishes, when you cancel or quit, or at the next launch after a crash (not yet verified on hardware).

## Tools

- `swift run hidprobe list | battery | dpi <index>`: diagnose what macOS shows and what the mouse answers. `list` and `battery` do not change settings (`battery` sends a query packet). `dpi <index>` WRITES the default presets 400/800/1200/2400/3200 to the mouse's working memory without saving; a later MouseBar save can store them, so power-cycle the mouse afterwards.
- `Scripts/gen-notices.sh`: rewrites the Rust dependency table and licence texts in `THIRD_PARTY_NOTICES.md` from `cargo metadata` (needs the crates' sources in `~/.cargo`, i.e. one earlier `Scripts/build-logi.sh`). The sections above the marker line in that file are hand-written.
- `Tools/gen_profiles.py`: regenerates `Sources/MouseCore/Generated/GeneratedProfiles.swift` and the test vectors from rivalcfg 4.17.0 (`python3 -m venv .venv && .venv/bin/pip install -r Tools/requirements.txt && .venv/bin/python -I Tools/gen_profiles.py`).

## Credits

The SteelSeries mouse protocol comes from [rivalcfg](https://github.com/flozz/rivalcfg) by Fabien LOISON (flozz), licensed WTFPL.

The Logitech support uses [OpenLogi](https://github.com/AprilNEA/OpenLogi) by AprilNEA (`MIT OR Apache-2.0`), whose `openlogi-hidpp` crate is a fork of `hidpp` from [logy](https://github.com/lus/logy) by Lukas Schulte Pelkum (0BSD). Licence texts and the Rust dependency list are in `THIRD_PARTY_NOTICES.md`, which is also inside the app bundle (`Contents/Resources`).
