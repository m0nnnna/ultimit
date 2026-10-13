#!/usr/bin/python3 -I
"""probe.py - what the Ultimit installer screen needs to know, as JSON on stdout. Runs as root in
the ISO's live system (greeter/installer/start.sh); nothing here changes a disk.

  probe.py disks              every disk Ultimit could go on: size, model, what is on it (Windows,
                              BitLocker, Linux), its largest free gap; the USB stick it booted
                              from is marked "boot"
  probe.py net                online? (Ubuntu's archive answers), the Wi-Fi devices, and the time
                              zone where this PC is (Ubuntu's geoip service), once online
  probe.py wifi-scan DEV      the Wi-Fi networks DEV sees (strongest first)
  probe.py wifi-connect DEV SSID [PASSWORD]
                              join that network (netplan, as Ubuntu's installer does) and wait
                              until online (30 s)
  probe.py status             the install's progress: subiquity's state and its latest step

Test hooks (anything but root): PROBE_FAKE_DIR=<dir> reads lsblk.json, sfdisk-<name>.json,
boot-device and net.json from there.
"""
import json
import os
import re
import subprocess
import sys
import time

FAKE = os.environ.get("PROBE_FAKE_DIR") if os.getuid() != 0 else None
MIN_GAP = 25 * 1000 ** 3          # free space "install alongside" needs (25 GB)
RUN = "/run/ultimit-installer"


def run(argv, timeout=30):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL,
                           env=dict(os.environ, LC_ALL="C"))
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""


def fake(name):
    try:
        with open(os.path.join(FAKE, name)) as f:
            return f.read()
    except OSError:
        return None


# ---------------------------------------------------------------------------------------- disks
def boot_device():
    """The disk the ISO is on (/cdrom), so nobody installs over the USB stick."""
    if FAKE:
        return (fake("boot-device") or "").strip()
    rc, src = run(["findmnt", "-n", "-o", "SOURCE", "/cdrom"])
    src = src.strip()
    if not src:
        return ""
    rc, parent = run(["lsblk", "-n", "-d", "-o", "PKNAME", src])
    return "/dev/" + parent.strip() if parent.strip() else src


def gaps(disk):
    """Free space on a disk (bytes): the largest gap, and the whole disk when it has no table."""
    name = os.path.basename(disk["path"])
    text = fake("sfdisk-%s.json" % name) if FAKE else run(["sfdisk", "-J", disk["path"]])[1]
    try:
        t = json.loads(text or "")["partitiontable"]
    except (ValueError, KeyError, TypeError):
        return disk["size"], False    # no partition table: all of it is free
    ss = t.get("sectorsize", 512)
    first, last = t.get("firstlba", 2048), t.get("lastlba", disk["size"] // ss - 34)
    parts = sorted((p["start"], p["start"] + p["size"]) for p in t.get("partitions", []))
    best, pos = 0, first
    for s, e in parts:
        best = max(best, s - pos)
        pos = max(pos, e)
    best = max(best, last + 1 - pos)
    # 1 MiB alignment loses a little at each end
    return max(0, best * ss - 2 * 1024 * 1024), True


def describe(parts):
    """What a person would call what's on the disk: Windows itself (its reserved or recovery
    partition, or NTFS beside a boot partition), only files from Windows (an NTFS data drive),
    BitLocker, Linux."""
    types = [(p.get("parttypename") or "") for p in parts]
    fs = [(p.get("fstype") or "").lower() for p in parts]
    bitlocker = "bitlocker" in fs
    ntfs = "ntfs" in fs or bitlocker or any("Microsoft basic data" in t for t in types)
    win = any(t in ("Microsoft reserved", "Windows recovery environment") for t in types) \
        or (ntfs and any(t == "EFI System" for t in types))
    linux = any(f in ("ext4", "btrfs", "xfs") for f in fs)
    return win, ntfs and not win, bitlocker, linux


def disks():
    text = fake("lsblk.json") if FAKE else run(
        ["lsblk", "-J", "-b", "-o", "NAME,PATH,SIZE,MODEL,TYPE,TRAN,RM,RO,FSTYPE,PARTTYPENAME,LABEL"])[1]
    try:
        devs = json.loads(text or "")["blockdevices"]
    except (ValueError, KeyError):
        return {"disks": [], "error": "Could not list the drives."}
    boot = boot_device()
    out = []
    for d in devs:
        if d.get("type") != "disk" or d.get("ro") in (True, "1", 1) or int(d.get("size") or 0) < 8 * 1000 ** 3:
            continue
        if re.match(r"^(loop|zram|ram|sr|fd)", d.get("name", "")):
            continue
        parts = d.get("children") or []
        size = int(d["size"])
        free, table = gaps({"path": d["path"], "size": size})
        win, winfiles, bitlocker, linux = describe(parts)
        out.append({
            "path": d["path"], "name": d["name"], "size": size,
            "model": (d.get("model") or "").strip() or ("NVMe drive" if d["name"].startswith("nvme") else "Drive"),
            "tran": d.get("tran") or "", "usb": d.get("tran") == "usb" or d.get("rm") in (True, "1", 1),
            "boot": d["path"] == boot, "empty": not parts,
            "windows": win, "windowsFiles": winfiles, "bitlocker": bitlocker, "linux": linux,
            "partitions": len(parts), "free": free, "canAlongside": table and bool(parts) and free >= MIN_GAP,
        })
    # Internal drives first; the one with room next to Windows, then SSDs (NVMe), then the biggest
    out.sort(key=lambda x: (x["boot"], x["usb"], not x["canAlongside"], x["tran"] != "nvme", -x["size"]))
    return {"disks": out, "minGap": MIN_GAP}


# ---------------------------------------------------------------------------------------- network
def online():
    rc, _ = run(["curl", "-s", "-o", "/dev/null", "--max-time", "6", "http://archive.ubuntu.com/ubuntu/"], timeout=10)
    return rc == 0


def timezone():
    """Where this PC is, as Ubuntu's installer asks it (geoip.ubuntu.com), e.g. America/New_York."""
    rc, text = run(["curl", "-s", "--max-time", "6", "https://geoip.ubuntu.com/lookup"], timeout=10)
    m = re.search(r"<TimeZone>([A-Za-z_]+(?:/[A-Za-z0-9_+-]+){0,2})</TimeZone>", text or "")
    return m.group(1) if m else ""


def net():
    if FAKE:
        try:
            return json.loads(fake("net.json") or "")
        except ValueError:
            return {"online": False, "wifi": []}
    wifi = sorted(n for n in os.listdir("/sys/class/net") if os.path.isdir("/sys/class/net/%s/wireless" % n))
    up = online()
    return {"online": up, "wifi": wifi, "timezone": timezone() if up else ""}


def wifi_scan(dev):
    run(["ip", "link", "set", dev, "up"])
    rc, text = run(["iw", "dev", dev, "scan"], timeout=25)
    nets, cur = {}, None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("BSS "):
            cur = {"ssid": "", "signal": -100.0, "secure": False}
        elif cur is None:
            continue
        elif line.startswith("signal:"):
            try:
                cur["signal"] = float(line.split()[1])
            except (IndexError, ValueError):
                pass
        elif line.startswith("SSID:"):
            cur["ssid"] = line[5:].strip()
            if cur["ssid"] and (cur["ssid"] not in nets or nets[cur["ssid"]]["signal"] < cur["signal"]):
                nets[cur["ssid"]] = cur
        elif line.startswith(("RSN:", "WPA:")):
            cur["secure"] = True
    out = sorted(nets.values(), key=lambda n: -n["signal"])
    for n in out:   # 0..4 bars from dBm
        n["bars"] = 4 if n["signal"] > -55 else 3 if n["signal"] > -67 else 2 if n["signal"] > -75 else 1
    return {"networks": out}


def yaml_str(s):
    return json.dumps(s)   # a JSON string is a valid YAML string


def wifi_connect(dev, ssid, password):
    ap = {"password": password} if password else {}
    conf = ("# Written by the Ultimit installer\nnetwork:\n  version: 2\n  renderer: networkd\n"
            "  wifis:\n    %s:\n      dhcp4: true\n      access-points:\n        %s: %s\n"
            % (dev, yaml_str(ssid), json.dumps(ap)))
    path = "/etc/netplan/90-ultimit-wifi.yaml"
    with open(path, "w") as f:
        f.write(conf)
    os.chmod(path, 0o600)
    rc, _ = run(["netplan", "apply"], timeout=60)
    for _ in range(30):
        if online():
            return {"ok": True}
        time.sleep(1)
    return {"ok": False, "error": "Couldn't connect. Check the password, or plug in a network cable."}


# ---------------------------------------------------------------------------------------- progress
STEPS = [   # subiquity/curtin step names -> what the screen says
    ("waiting", "Getting ready"), ("partitioning", "Preparing the drive"), ("extract", "Copying Ubuntu onto the drive"),
    ("curthooks", "Setting up the system"), ("install_ubuntu-restricted-addons", "Adding media codecs"),
    ("ubuntu-drivers-install", "Adding graphics drivers"), ("run_unattended_upgrades", "Installing security updates"),
    ("run_user_supplied", "Installing Ultimit"), ("restore_apt_config", "Installing Ultimit"),
]


def status():
    o = {"state": "", "step": "", "installed": os.path.exists(RUN + "/installed"), "error": ""}
    rc, text = run(["curl", "-s", "--max-time", "4", "--unix-socket", "/run/subiquity/socket",
                    "http://localhost/meta/status"], timeout=6)
    try:
        st = json.loads(text)
        o["state"] = st.get("state", "")
        if st.get("error"):
            o["error"] = "The install stopped with an error."
    except ValueError:
        pass
    # The latest step subiquity started (its events are in the journal, SUBIQUITY_EVENT_TYPE=start)
    rc, text = run(["journalctl", "-b", "-o", "json", "-n", "300", "--no-pager", "SUBIQUITY_EVENT_TYPE=start"], timeout=8)
    for line in reversed(text.splitlines()):
        try:
            name = json.loads(line).get("SUBIQUITY_CONTEXT_NAME", "")
        except ValueError:
            continue
        label = next((lab for key, lab in STEPS if key in name), "")
        if label:
            o["step"] = label
            break
    return o


def main(a):
    cmd = a[1] if len(a) > 1 else ""
    if cmd == "disks":
        o = disks()
    elif cmd == "net":
        o = net()
    elif cmd == "wifi-scan" and len(a) == 3:
        o = wifi_scan(a[2])
    elif cmd == "wifi-connect" and len(a) in (4, 5):
        o = wifi_connect(a[2], a[3], a[4] if len(a) == 5 else "")
    elif cmd == "status":
        o = status()
    else:
        print(json.dumps({"error": "usage: probe.py disks|net|wifi-scan DEV|wifi-connect DEV SSID [PW]|status"}))
        return 2
    print(json.dumps(o))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
