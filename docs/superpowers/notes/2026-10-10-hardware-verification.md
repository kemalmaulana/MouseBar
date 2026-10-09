# Hardware verification: MouseBar Phase 2

Date: 2026-10-10. Mouse: SteelSeries Prime Mini Wireless on the USB cable (`1038:184a`).

Phase 2 is **not verified**. Only the read-only "Launch" row has been run. Every row that writes to the real mouse, or needs a physical replug, is waiting for the owner's go-ahead.

## Checklist

Run `build/MouseBar.app` normally (no `--demo`), with the dongle plugged in and SteelSeries GG's engine not running (`pgrep -x SteelSeriesEngine` prints nothing).

| Action in MouseBar | Expected on the mouse / screen | Result |
|---|---|---|
| Launch | Menu bar shows a battery icon and a percentage within about 5 seconds, within 5 points of `~/rivalcfg/rivalcfg --battery-level` | PASS (read-only): app (non-demo, run by an earlier task) showed a charging battery icon with 95%; `rivalcfg --battery-level` printed `Charging ... 95 %`; `hidprobe battery` decoded 95% charging |
| Settings: Polling rate 125, then 1000 | Command succeeds; no error text. (Judge with any mouse-rate test page if available) | NOT RUN: writes to the user's real mouse or needs a physical replug; waiting for the owner's go-ahead |
| Settings: LED color to blue, then green | Mouse LED changes immediately | NOT RUN: writes to the user's real mouse or needs a physical replug; waiting for the owner's go-ahead |
| Settings: Sensitivity preset 1 to 3200 and press the mouse's DPI button | Pointer speed changes between presets | NOT RUN: writes to the user's real mouse or needs a physical replug; waiting for the owner's go-ahead |
| Settings: Buttons: button 4 to PlayPause, button 5 to VolumeUp | Side buttons now control media / volume | NOT RUN: writes to the user's real mouse or needs a physical replug; waiting for the owner's go-ahead |
| Settings: Buttons: Button 1 to disabled | Window shows the rejection message; left click still works | NOT RUN: writes to the user's real mouse or needs a physical replug; waiting for the owner's go-ahead |
| Settings: Sleep timer 1 min, leave the mouse still 70 s, move it | After two missed polls the menu shows "mouse asleep"; after waking the label returns to a fresh percentage | NOT RUN: writes to the user's real mouse or needs a physical replug; waiting for the owner's go-ahead |
| Quit and relaunch | Chosen LED color and settings are applied again without opening Settings | NOT RUN: writes to the user's real mouse or needs a physical replug; waiting for the owner's go-ahead |
| Unplug the dongle | Menu bar icon switches to the plain mouse symbol and "No mouse connected"; replug restores it | NOT RUN: writes to the user's real mouse or needs a physical replug; waiting for the owner's go-ahead |
| Plug the USB cable (dongle also in) | Menu shows the "(wired mode)" model name; the battery shows charging (bolt icon) | NOT RUN: writes to the user's real mouse or needs a physical replug; waiting for the owner's go-ahead |
| Pull the cable out | App falls back to the dongle model without relaunch | NOT RUN: writes to the user's real mouse or needs a physical replug; waiting for the owner's go-ahead |

## Observed during development

- (a) The second `hidprobe battery` read returned a foreign report `21 00 00 2e 37 ...` while SteelSeries GG's engine was running. The decoder correctly rejected it instead of showing a wrong percentage.
- (b) The dongle (`1038:1848`) path is untested because only the cable was attached.
- (c) Preset selection through the sensitivity command is unconfirmed, so the app has no active-preset picker or quick DPI switch yet.
- (d) `docs/superpowers/notes/2026-10-10-phase0-spike.md` has the raw spike data.
