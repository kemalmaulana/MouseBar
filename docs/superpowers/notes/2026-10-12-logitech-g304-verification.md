# Hardware verification: MouseBar Logitech support (G304)

Date: 2026-10-12. Mouse: Logitech G304 on a Lightspeed receiver (`046d:c53f`), wpid `4074`.

Logitech support is **not verified on hardware**. The G304 has only been enumerated: it was offline (asleep or off), so nothing has been read from it and nothing has been written to it.

## What was observed

- From a spike on 2026-10-12 that changed no mouse setting, OpenLogi's CLI `openlogi list` printed `Lightspeed Receiver (vid=046d pid=c53f)` and `slot 1 ○ Unknown device (mouse, wpid=4074, battery=—)`. `○` means offline. The G304 stayed offline for 2 minutes of polling.
- The owner has no AA battery for the G304 right now, so it cannot be woken yet.
- During Tasks 1-2 of the implementation the whole USB hub was unplugged, so `logiprobe` saw 0 devices.
- Every other row below was NOT RUN.

## Run this first (changes no mouse setting)

Wake the G304 (switch it on, fresh AA battery), leave G HUB, Logi Options+ and the OpenLogi agent quit, then:

    swift run logiprobe

It prints the library version, each paired device, and for each online one its DPI, polling rate and battery. It never calls the DPI or polling-rate setters and changes no mouse setting. It is not strictly read-only: like Solaar, OpenLogi's enumeration asks the receiver to re-announce its devices (it sets the receiver's wireless-notification flag, register `0x00`, read-modify-write in the receiver's RAM, and triggers device-arrival notifications through register `0x02`). A failed settings or battery read is printed for that device and the probe goes on. Paste the output into the Result column of the first rows below.

## Checklist

Run `build/MouseBar.app` normally (no `--demo`) with the receiver plugged in and no Logitech app running. Writes need the owner's go-ahead.

| Check | Expected | Result |
|---|---|---|
| Enumerate | The Lightspeed receiver is found and the G304 appears in its slot with wpid `4074` | PARTIAL (`openlogi list`, no mouse setting changed): receiver `046d:c53f` found; G304 at slot 1, wpid `4074`, offline (asleep or off). `logiprobe` has not seen it online. |
| Battery | `logiprobe` and the menu bar show a percentage, charging state if any | NOT RUN: the G304 was offline and the owner has no AA battery to wake it |
| DPI read | `logiprobe` prints the current DPI and the supported values | NOT RUN: the G304 was offline |
| Report rate read | `logiprobe` prints the current rate and the supported rates | NOT RUN: the G304 was offline |
| DPI write + read-back | Change DPI in Settings; the value read back matches; the pointer speed changes | NOT RUN: writes to the real mouse; waiting for the owner's go-ahead and an awake mouse |
| Report rate write + read-back | Change polling rate in Settings; the value read back matches | NOT RUN: writes to the real mouse; waiting for the owner's go-ahead and an awake mouse |
| Wake re-apply | Put the mouse to sleep, wake it; the DPI and polling rate you set are applied again without opening Settings | NOT RUN: needs an awake mouse and the owner's go-ahead |
| Picker | With the SteelSeries mouse and the G304 both connected, the panel header menu switches between them and remembers the choice after relaunch | NOT RUN: needs the G304 online |

## Open questions for the hardware run

- The G304 has onboard profiles. If a DPI or polling-rate write is read back unchanged, MouseBar reports "The mouse kept N DPI instead of M. Its onboard profile may be in control." (or "The mouse kept N Hz instead of M. Its onboard profile may be in control.") Note whether that happens and in which profile mode.
