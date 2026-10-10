# MouseBar

Unofficial and not affiliated with SteelSeries.

A native Apple Silicon menu bar app for SteelSeries mice: battery level at the top right of the screen and the mouse's settings in a window. It does not use SteelSeries GG.

Status: v0.1, early. Hardware-tested so far on one mouse (SteelSeries Prime Mini Wireless, USB cable): enumeration, opening the control interface and reading the battery (matches rivalcfg). Changing settings from the app, the 2.4 GHz dongle, and saving to the mouse's memory are implemented and unit-tested against rivalcfg's byte output but NOT yet verified on hardware. Other mice are untested (the Prime Wireless profile is included but unverified).

## Build and run

    Scripts/bundle.sh release
    open build/MouseBar.app

Requires macOS 14+, Xcode 27 or Swift 6.4, and an arm64 Mac. To try the UI with a simulated mouse (nothing is sent to a real one), run `open build/MouseBar.app --args --demo`.

There is no launch-at-login yet; add the app to System Settings > General > Login Items by hand.

If SteelSeries GG is installed, quit it first and consider uninstalling it: both programs talk to the same device. A battery read can return a report that is not the battery answer while GG's engine runs (seen once; likely GG's traffic). MouseBar ignores such reports on the cable.

## Settings

DPI presets (up to 5), polling rate, LED color, button remapping, sleep and dim timers, startup lighting, factory reset.

- Settings are re-applied when the mouse (re)connects, except DPI presets: those stay in the mouse's own memory and the app does not re-send them.
- LED color is not stored on the mouse. MouseBar re-applies it when the mouse connects or wakes.
- The other settings are sent to the mouse, and a save command follows about 2 seconds after your last change. This is the design; whether the mouse keeps them after a power cycle is not yet verified on hardware.
- The mouse cannot report its current settings, so the window shows factory defaults for anything MouseBar has not set. The first change to a DPI preset or button rewrites the whole list or map (and saves it).

## Interface

- **Menu bar:** battery symbol and percentage (hide the percentage in Settings → Device). It may turn red when low (tint not yet verified in the menu bar) and shows a moon while the mouse sleeps.
- **Panel:** click the menu bar item for the mouse, its connection (Cable or 2.4 GHz), a battery gauge, quick polling-rate and LED controls, warnings, and "Saving to mouse… / Saved to mouse" feedback. A DPI switch appears once the hardware check has confirmed that the mouse accepts an active-preset change.
- **Settings (⌘,):** tabs for Performance (DPI presets, polling rate), Buttons (diagram plus per-button actions, including media and keyboard keys), Lighting, Power, and Device (info, Hardware Check, reset). A "Default" tag marks values MouseBar has never set.
- **Hardware Check:** from the panel or Settings → Device. It walks you through 9 short steps on your real mouse (battery over cable and dongle, LED, polling rate, buttons, DPI, saving, wake) and writes a Markdown report to `~/Library/Application Support/MouseBar/reports/`. MouseBar puts back the settings it has stored and the DPI presets and button remaps you enter here. Everything else goes back to factory defaults, and the active DPI preset becomes preset 1. This happens when it finishes, when you cancel or quit, or at the next launch after a crash (not yet verified on hardware).

## Tools

- `swift run hidprobe list | battery | dpi <index>`: diagnose what macOS shows and what the mouse answers. `list` and `battery` do not change settings (`battery` sends a query packet). `dpi <index>` WRITES the default presets 400/800/1200/2400/3200 to the mouse's working memory without saving; a later MouseBar save can store them, so power-cycle the mouse afterwards.
- `Tools/gen_profiles.py`: regenerates `Sources/MouseCore/Generated/GeneratedProfiles.swift` and the test vectors from rivalcfg 4.17.0 (`python3 -m venv .venv && .venv/bin/pip install -r Tools/requirements.txt && .venv/bin/python -I Tools/gen_profiles.py`).

## Credits

The mouse protocol comes from [rivalcfg](https://github.com/flozz/rivalcfg) by Fabien LOISON (flozz), licensed WTFPL.
