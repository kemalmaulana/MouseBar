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
