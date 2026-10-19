#!/usr/bin/env python3
"""items.py - helper for ITEMS, the Ultimit device settings app (mice and other peripherals with their own
settings). Prints one JSON object on stdout; never raises to the caller.

  items.py list              devices ITEMS supports, each with "present" (plugged in now)
  items.py get ID            {device, schema, config, keys, modifiers}; config is the saved one or the default
  items.py set ID < JSON     check the config, save it, send it to the device

Devices that can't report their settings back (most gaming mice) are configured from the saved file, so
~/.config/ultimit/items/ID.json is the source of truth.
ITEMS_FAKE=1: every device is "present" and apply writes the packets to $ITEMS_FAKE_OUT (default
/tmp/items-fake-<ID>.txt) instead of the device. ITEMS_CONFIG_DIR overrides the config folder (tests).
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from drivers import DRIVERS, hid  # noqa: E402

FAKE = os.environ.get("ITEMS_FAKE") == "1"


def config_dir():
    return os.environ.get("ITEMS_CONFIG_DIR") or os.path.join(
        os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "ultimit", "items")


def driver(dev_id):
    for d in DRIVERS:
        if d.ID == dev_id:
            return d
    raise LookupError(f"unknown device '{dev_id}'")


def load_config(d):
    try:
        with open(os.path.join(config_dir(), d.ID + ".json")) as f:
            return json.load(f), True
    except (OSError, ValueError):
        return d.default_config(), False


def save_config(d, cfg):
    os.makedirs(config_dir(), exist_ok=True)
    path = os.path.join(config_dir(), d.ID + ".json")
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cfg, f, indent=1)
    os.replace(tmp, path)


def cmd_list():
    return {"ok": True, "devices": [{"id": d.ID, "name": d.NAME, "kind": d.KIND,
                                     "present": FAKE or d.is_present()} for d in DRIVERS]}


def cmd_get(dev_id):
    d = driver(dev_id)
    cfg, saved = load_config(d)
    return {"ok": True, "device": {"id": d.ID, "name": d.NAME, "kind": d.KIND, "present": FAKE or d.is_present()},
            "schema": d.schema(), "config": cfg, "saved": saved,
            "keys": sorted(hid.KEYS), "modifiers": list(hid.MODS)}


def cmd_set(dev_id, text):
    d = driver(dev_id)
    try:
        cfg = json.loads(text)
        d.build(cfg)                       # validate before saving anything
    except ValueError as e:
        return {"ok": False, "error": str(e), "kind": "invalid"}
    save_config(d, cfg)
    try:
        fake_out = (os.environ.get("ITEMS_FAKE_OUT") or f"/tmp/items-fake-{d.ID}.txt") if FAKE else None
        d.apply(cfg, fake_out)
    except (RuntimeError, OSError) as e:
        return {"ok": False, "error": f"Saved, but not sent: {e}", "kind": "device", "saved": True}
    return {"ok": True, "saved": True}


def main(argv):
    try:
        if len(argv) >= 1 and argv[0] == "list":
            out = cmd_list()
        elif len(argv) == 2 and argv[0] == "get":
            out = cmd_get(argv[1])
        elif len(argv) == 2 and argv[0] == "set":
            out = cmd_set(argv[1], sys.stdin.read())
        else:
            out = {"ok": False, "error": "usage: items.py list | get ID | set ID < JSON"}
    except LookupError as e:
        out = {"ok": False, "error": str(e)}
    except Exception as e:                 # the window shows this instead of hanging on bad JSON
        out = {"ok": False, "error": f"ITEMS helper error: {e}"}
    print(json.dumps(out))


if __name__ == "__main__":
    main(sys.argv[1:])
