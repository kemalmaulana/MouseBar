# MouseBar

A native Apple Silicon menu bar app for SteelSeries mice: battery level at the top right of the screen and the mouse's settings in a window. It does not use SteelSeries GG.

Status: v0.1, early. Hardware-tested so far on one mouse (SteelSeries Prime Mini Wireless, USB cable): enumeration, opening the control interface and reading the battery (matches rivalcfg). Changing settings from the app, the 2.4 GHz dongle, and saving to the mouse's memory are implemented and unit-tested against rivalcfg's byte output but NOT yet verified on hardware. Other mice are not supported yet.

## Build and run

    Scripts/bundle.sh release
    open build/MouseBar.app

Requires macOS 14+, Xcode 27 or Swift 6.4, and an arm64 Mac. Add `--args --demo` to `open` to try the UI with a simulated mouse.

If SteelSeries GG is installed, quit it first and consider uninstalling it: both programs talk to the same device. With GG's engine running, a battery read can return a report meant for GG instead of the battery answer (seen once during the hardware spike).

## Settings

DPI presets (up to 5), polling rate, LED color, button remapping, sleep and dim timers, startup lighting, factory reset. Settings are re-applied whenever the mouse connects, and by design a save command is sent to the mouse about 2 seconds after your last change. Whether the mouse's own memory keeps the settings after that save is not yet verified on hardware.

## Tools

- `swift run hidprobe list | battery | dpi <index>`: diagnose what macOS shows and what the mouse answers. `list` and `battery` only read; `dpi` writes to the mouse.
- `Tools/gen_profiles.py`: regenerates `Sources/MouseCore/Generated/GeneratedProfiles.swift` and the test vectors from rivalcfg 4.17.0 (`python3 -m venv .venv && .venv/bin/pip install -r Tools/requirements.txt && .venv/bin/python -I Tools/gen_profiles.py`).

## Credits

The mouse protocol comes from [rivalcfg](https://github.com/flozz/rivalcfg) by Fabien LOISON (flozz), licensed WTFPL. This project is unofficial and not affiliated with SteelSeries.
