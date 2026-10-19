"""redragon_m990.py - Redragon M990 Legend RGB (USB 04d9:fc41, Holtek). Reverse-engineered from the
official Windows app (RDCfg.exe, V1052) by recording its USB traffic.

Protocol: HID feature reports 2 (16 bytes) and 3 (64 bytes) on the vendor interface (usage page 0xffa0).
  02 f5 00                                begin
  02 f3 AL AH N 00 00 00 <N data bytes>   write N bytes of settings memory at AH:AL
  02 f1 02 XX                             apply section XX (01 02 04 08 10)
  02 f5 01                                end
The mouse can't report its settings back, so the app (and ITEMS) keeps the settings and rewrites the whole
map on every apply. We replay the exact 176-packet sequence the app sends (redragon_m990.template) with
the data bytes patched from the config.

Settings memory, per profile p (base = PROFILE_BASE[p]; profile 1->2 is 0xC0 apart, the rest 0xB0):
  base+0x44 + 6*i   DPI level i: enabled, X lo, X hi, Y lo, Y hi (units of 100 DPI)
  base+0x82 + off   button slot: 4 bytes. 90 00 KK = key, 8f MM KK = key with modifiers,
                    81 left, 82 right, 83 middle, 8a DPI+, 89 DPI-
  0x449 + 8*p       lighting: R G B mode speed effect brightness
Side buttons 1-16 are slots 0x20..0x5c in physical order (checked on the mouse).
"""
import os
from . import hid

ID = "redragon-m990"
NAME = "Redragon M990 Legend RGB"
KIND = "mouse"
VID, PID = 0x04D9, 0xFC41
VENDOR_DESCRIPTOR = b"\x06\xa0\xff"      # Usage Page (0xffa0): the configuration interface

TEMPLATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "redragon_m990.template")
PROFILES = 5
PROFILE_BASE = [0x00, 0xC0, 0x170, 0x220, 0x2D0]
DPI_BASE, BTN_BASE, LED_BASE = 0x44, 0x82, 0x449

BUTTONS = [("left", "Left", 0x00), ("right", "Right", 0x04), ("middle", "Middle (wheel click)", 0x08),
           ("fire", "Fire", 0x0C), ("dpi_up", "DPI +", 0x10), ("dpi_down", "DPI −", 0x14)]
BUTTONS += [(f"side{i + 1}", f"Side {i + 1}", 0x20 + 4 * i) for i in range(16)]
# slots the app writes whose physical button isn't identified yet: shown under "Other", kept as raw bytes
BUTTONS += [("slot_9a", "Other (slot 9A)", 0x18), ("slot_e2", "Other (slot E2)", 0x60),
            ("slot_e6", "Other (slot E6)", 0x64)]

FUNCTIONS = {"left": "81000000", "right": "82000000", "middle": "83000000",
             "dpi_up": "8a000000", "dpi_down": "89000000"}

# name -> (mode, speed, effect), in the app's menu order
EFFECTS = {"breathing": (0x01, 0x04, 0x04), "rainbow": (0x01, 0x04, 0x08), "static": (0x01, 0x00, 0x02),
           "wave": (0x02, 0x04, 0x00), "trail": (0x06, 0x04, 0x00), "reactive": (0x07, 0x04, 0x00),
           "flash": (0x01, 0x04, 0x10), "off": (0x00, 0x00, 0x00)}
EFFECT_LABELS = {"breathing": "Breathing", "rainbow": "Rainbow", "static": "Full lighted", "wave": "Wave",
                 "trail": "Go without trace", "reactive": "Reactive", "flash": "Flash", "off": "Off"}

SIDE_DEFAULT = "1 2 3 4 5 6 7 8 9 0 kp_plus kp_minus equal period kp_star kp_slash".split()


def schema():
    return {
        "profiles": PROFILES,
        "buttons": [{"id": b, "label": l} for b, l, _ in BUTTONS],
        "functions": list(FUNCTIONS),
        "effects": [{"id": e, "label": EFFECT_LABELS[e]} for e in EFFECTS],
        "brightness": [1, 2, 3, 4],
        "dpi": {"levels": 5, "min": 100, "max": 32000, "step": 100},
        "colors": True,
    }


def default_config():
    prof = {"color": "ff0000", "effect": "static", "brightness": 2,
            "dpi": [2000, 4000, 8000, 16000, 32000],
            "buttons": {"left": "left", "right": "right", "middle": "middle", "fire": "raw:99810301",
                        "dpi_up": "dpi_up", "dpi_down": "dpi_down",
                        "slot_9a": "raw:9b040000", "slot_e2": "raw:8b000000", "slot_e6": "raw:8c000000"}}
    for i, k in enumerate(SIDE_DEFAULT):
        prof["buttons"][f"side{i + 1}"] = k
    return {"profiles": [dict(prof, buttons=dict(prof["buttons"])) for _ in range(PROFILES)]}


def encode_action(text):
    t = str(text).strip().lower()
    if t.startswith("raw:"):
        try:
            b = bytes.fromhex(t[4:])
        except ValueError:
            raise ValueError("raw: needs hex bytes, like raw:81000000")
        if not 1 <= len(b) <= 4:
            raise ValueError("raw: takes 1 to 4 bytes")
        return (b + bytes(4))[:4]
    if t in FUNCTIONS:
        return bytes.fromhex(FUNCTIONS[t])
    mod, usage = hid.parse_key(t)
    return bytes([0x8F if mod else 0x90, mod, usage, 0])


class Image:
    """The template packets plus an address -> (packet, byte) map for patching."""
    def __init__(self):
        with open(TEMPLATE) as f:
            self.pkts = [bytearray.fromhex(l.strip()) for l in f if l.strip()]
        self.where = {}
        for i, p in enumerate(self.pkts):
            if p[1] == 0xF3:
                addr, n = p[2] | p[3] << 8, p[4]
                for k in range(n):
                    self.where[addr + k] = (i, 8 + k)

    def put(self, addr, data):
        for k, v in enumerate(data):
            i, o = self.where[addr + k]
            self.pkts[i][o] = v


def build(config):
    """config -> the packets to send. Raises ValueError("profile N: field: problem")."""
    img = Image()
    profs = config.get("profiles") or []
    if len(profs) != PROFILES:
        raise ValueError(f"needs {PROFILES} profiles")
    for p, s in enumerate(profs):
        where = f"profile {p + 1}"
        try:
            rgb = bytes.fromhex(str(s["color"]).lstrip("#"))
            assert len(rgb) == 3
        except Exception:
            raise ValueError(f"{where}: color: use six hex digits, like ff8800")
        if s["effect"] not in EFFECTS:
            raise ValueError(f"{where}: effect: unknown '{s['effect']}'")
        br = int(s["brightness"])
        if br not in schema()["brightness"]:
            raise ValueError(f"{where}: brightness: 1 to 4")
        img.put(LED_BASE + 8 * p, rgb + bytes(EFFECTS[s["effect"]]) + bytes([br]))
        dpi = s["dpi"]
        if len(dpi) != 5:
            raise ValueError(f"{where}: dpi: needs 5 levels")
        for i, v in enumerate(dpi):
            v = int(v)
            if v == 0:
                d = bytes(5)
            elif 100 <= v <= 32000:
                u = v // 100
                d = bytes([1, u & 0xFF, u >> 8, u & 0xFF, u >> 8])
            else:
                raise ValueError(f"{where}: dpi {i + 1}: 100 to 32000 (0 = off)")
            img.put(DPI_BASE + PROFILE_BASE[p] + 6 * i, d)
        btns = s.get("buttons") or {}
        for bid, label, off in BUTTONS:
            if bid in btns:
                try:
                    img.put(BTN_BASE + PROFILE_BASE[p] + off, encode_action(btns[bid]))
                except ValueError as e:
                    raise ValueError(f"{where}: {label}: {e}")
    return img.pkts


def is_present():
    return hid.present(VID, PID)


def apply(config, fake_out=None):
    pkts = build(config)
    if fake_out:
        with open(fake_out, "w") as f:
            f.write("\n".join(p.hex() for p in pkts) + "\n")
        return
    dev = hid.find_hidraw(VID, PID, VENDOR_DESCRIPTOR)
    if not dev:
        raise RuntimeError("The mouse isn't plugged in.")
    try:
        hid.send_features(dev, pkts)
    except PermissionError:
        raise RuntimeError("No permission to talk to the mouse. Ultimit's udev rule gives it to you; "
                           "unplug the mouse and plug it back in (or log in again).")
