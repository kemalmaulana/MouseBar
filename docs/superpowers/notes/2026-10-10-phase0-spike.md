# Phase 0 spike: native HID on the Prime Mini Wireless

Date: 2026-10-10. Machine: Apple Silicon Mac, macOS 27.0.1. Mouse: SteelSeries Prime Mini Wireless on the USB cable (`1038:184a`). The 2.4 GHz dongle (`1038:1848`) was not attached, so the dongle path is **untested**.

SteelSeries GG's `SteelSeriesEngine` process was running during all runs below (it was not stopped).

## What was run (all read-only, nothing written to the mouse)

- `ioreg`: one `IOUSBHostDevice` "SteelSeries Prime Mini Wireless", product id 6218 (`0x184A`), with HID interfaces 0 to 4.
- `.build/out/Products/Debug/hidprobe list`
- `.build/out/Products/Debug/hidprobe battery` (twice)
- `~/rivalcfg/rivalcfg --battery-level` (several times)

## Results

`hidprobe list` (native `IOHIDManager` enumeration):

| interface | usagePage | usage |
|---|---|---|
| 0 | 0x0001 | 0x0002 (mouse) |
| 1 | 0x0001 | 0x0006 (keyboard) |
| 2 | 0x000c | 0x0001 (consumer) |
| 3 | 0xffc0 | 0x0001 (vendor, 64-byte input/output) |
| 4 | 0xffc1 | 0x0001 (vendor) |

- The interface-number lookup (`bInterfaceNumber`, device property or registry ancestor) works on macOS 27: every line has `iface=` filled in. Interface 3 is the control interface rivalcfg uses.
- No Input Monitoring or other permission prompt appeared. `IOHIDDeviceOpen` on the private device from `IOHIDDeviceCreate` succeeded (this is the path added in the Task 8 fix).

`hidprobe battery`, first run:

    raw reply: 92 94 00 2e 37 00 ... (64 bytes)
    battery: 95% (charging)

- The reply has no report-id prefix. Byte 0 is an echo of the command (`0x92`), byte 1 is `0x94`: bit 7 set (charging), level bits `0x14` = 20, `(20 - 1) * 5` = 95. `BatteryDecoder` reading `reply[1]` is correct.
- `~/rivalcfg/rivalcfg --battery-level` printed `Charging [========= ] 95 %`. Native and rivalcfg agree.
- The MouseBar app (demo-less run by the Task 12 implementer) also showed a charging battery icon with 95%.

`hidprobe battery`, second run, immediately after:

    raw reply: 21 00 00 2e 37 00 ... (64 bytes)
    reply is not a valid battery reading

- This reply does not answer the battery query: byte 0 is `0x21`, which is the LED color command, not `0x92`. It is most likely a report produced by GG's running engine talking to the same interface.
- One `rivalcfg --battery-level` run also failed once with "Unable to get the battery level" and worked on the next call.
- Consequence: while GG's engine is running, a read can return another program's report. The decoder correctly returned "not valid" (nil) instead of a wrong percentage. A reply whose first byte is not the command echo should be ignored and the read retried until the timeout (not yet implemented; see follow-ups).

## Not done

- Dongle (`1038:1848`) battery read and the `0x40` wireless command variant.
- `hidprobe dpi <index>` (writes DPI presets to the mouse): needs the owner's consent first. Whether preset selection through the sensitivity command works is unknown, so the menu's quick DPI switch and the "Active preset" picker stay unconfirmed.
- Any settings write from the app.

## Decision

**GO for the native path on the cable** (enumeration, open, battery read, decode all work without extra permissions). The dongle path is unverified.

## Follow-ups from this run

1. Make battery reads robust: in `MouseDevice.readBattery`, discard reports whose first byte is not the command echo and keep reading until the timeout. For the dongle the echo byte may differ (`0xD2` vs `0x92`); confirm on the dongle before choosing the match rule.
2. When GG's engine runs, MouseBar should keep its existing warning. Quitting or uninstalling GG removes the interference.
