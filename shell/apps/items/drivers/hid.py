"""hid.py - shared helpers for ITEMS drivers: USB HID keyboard usage codes and modifier bits, the names
people type for them ("a", "f13", "kp_plus", "ctrl+shift+a"), and finding/writing a hidraw node."""
import fcntl, glob, os

# HID keyboard page usages (USB HID Usage Tables, page 0x07)
KEYS = {chr(ord("a") + i): 0x04 + i for i in range(26)}
KEYS.update({str((i + 1) % 10): 0x1E + i for i in range(10)})
KEYS.update({f"f{i + 1}": 0x3A + i for i in range(12)})
KEYS.update({f"f{i + 13}": 0x68 + i for i in range(12)})
KEYS.update({
    "enter": 0x28, "esc": 0x29, "backspace": 0x2A, "tab": 0x2B, "space": 0x2C, "minus": 0x2D, "equal": 0x2E,
    "lbracket": 0x2F, "rbracket": 0x30, "backslash": 0x31, "semicolon": 0x33, "quote": 0x34, "grave": 0x35,
    "comma": 0x36, "period": 0x37, "slash": 0x38, "capslock": 0x39, "printscreen": 0x46, "scrolllock": 0x47,
    "pause": 0x48, "insert": 0x49, "home": 0x4A, "pageup": 0x4B, "delete": 0x4C, "end": 0x4D, "pagedown": 0x4E,
    "arrow_right": 0x4F, "arrow_left": 0x50, "arrow_down": 0x51, "arrow_up": 0x52, "numlock": 0x53, "kp_slash": 0x54, "kp_star": 0x55,
    "kp_minus": 0x56, "kp_plus": 0x57, "kp_enter": 0x58, "kp_period": 0x63, "menu": 0x65,
})
KEYS.update({f"kp_{(i + 1) % 10}": 0x59 + i for i in range(10)})
KEYNAMES = {v: k for k, v in KEYS.items()}

MODS = {"ctrl": 0x01, "shift": 0x02, "alt": 0x04, "super": 0x08,
        "rctrl": 0x10, "rshift": 0x20, "ralt": 0x40, "rsuper": 0x80}


def parse_key(text):
    """'ctrl+shift+a' -> (modifier bits, usage). Raises ValueError with a sentence for the person."""
    parts = [p for p in text.strip().lower().replace(" ", "").split("+") if p]
    if not parts:
        raise ValueError("empty")
    mod = 0
    for p in parts[:-1]:
        if p not in MODS:
            raise ValueError(f"'{p}' is not a modifier (use {', '.join(MODS)})")
        mod |= MODS[p]
    if parts[-1] not in KEYS:
        raise ValueError(f"'{parts[-1]}' is not a key name")
    return mod, KEYS[parts[-1]]


def key_text(mod, usage):
    return "+".join([n for n, bit in MODS.items() if mod & bit] + [KEYNAMES.get(usage, f"0x{usage:02x}")])


def find_hidraw(vid, pid, descriptor_bytes=b""):
    """/dev/hidrawN of the interface of vid:pid whose report descriptor contains descriptor_bytes, or None."""
    want = f"HID_ID=0003:{vid:08X}:{pid:08X}"
    for h in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            with open(h + "/device/uevent") as f:
                if want not in f.read():
                    continue
            with open(h + "/device/report_descriptor", "rb") as f:
                if descriptor_bytes in f.read():
                    return "/dev/" + os.path.basename(h)
        except OSError:
            pass
    return None


def present(vid, pid):
    return any(f"HID_ID=0003:{vid:08X}:{pid:08X}" in open(u).read()
               for u in glob.glob("/sys/class/hidraw/hidraw*/device/uevent"))


def HIDIOCSFEATURE(n):
    return (3 << 30) | (n << 16) | (ord("H") << 8) | 0x06


def send_features(dev, packets, delay=0.02):
    """Send each packet (first byte = report id) as a HID feature report."""
    import time
    fd = os.open(dev, os.O_RDWR)
    try:
        for p in packets:
            fcntl.ioctl(fd, HIDIOCSFEATURE(len(p)), bytes(p))
            time.sleep(delay)
    finally:
        os.close(fd)
