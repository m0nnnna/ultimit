#!/usr/bin/python3 -I
"""collect-logs.py - gather an install report when the Ultimit installer fails, so the failure can be
diagnosed from a file instead of a photo. Runs as root in the ISO's live system. Installed there as
`ultimit-collect-logs` by start.sh, so it also works from a console (Ctrl+Alt+F2) when the screen is gone.

  collect-logs.py [--json] [--no-usb]

Writes /run/ultimit-installer/ultimit-install-report-<time>.tar.gz and copies it to every other
USB/removable drive it can write to (a Ventoy data partition counts). Passwords, Wi-Fi keys and
password hashes are blanked out first; nothing else is edited. Prints where the report went.
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import time

RUN = os.environ.get("INSTALLER_RUN", "/run/ultimit-installer")
STAMP = time.strftime("%Y%m%d-%H%M%S")
NAME = "ultimit-install-report-" + STAMP

FILES = ["/var/log/ultimit-installer.log", RUN + "/ui.log", RUN + "/seatd.log", "/var/log/ultimit-installer-net.log",
         "/proc/cmdline", "/cdrom/.disk/info", "/cdrom/ultimit/installer/base.json", "/autoinstall.yaml",
         "/target/var/log/apt/term.log", "/target/var/log/apt/history.log", "/target/etc/fstab",
         "/etc/resolv.conf"]
GLOBS = ["/var/log/installer/*", "/var/log/installer/*/*", "/etc/netplan/*", "/run/netplan/*", "/run/systemd/network/*",
         "/run/subiquity/*.log", "/target/var/crash/*.crash"]
CMDS = {
    "system.txt": "uname -a; echo; cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name /sys/class/dmi/id/bios_version "
                  "2>/dev/null; echo; [ -d /sys/firmware/efi ] && echo UEFI || echo BIOS; free -m; df -h; "
                  "grep -m1 'model name' /proc/cpuinfo",
    "disks.txt": "lsblk -f -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT,RM,MODEL; echo; fdisk -l 2>&1 | head -120; echo; efibootmgr -v 2>&1",
    "hardware.txt": "lspci -nnk; echo; lsusb; echo; lsmod",
    "drivers.txt": "ubuntu-drivers devices 2>&1; ls /sys/class/drm /sys/class/net",
    "network.txt": "ip -d addr; echo; ip route; echo; resolvectl status 2>&1 | head -60; echo; nmcli -t general 2>&1; "
                   "systemctl --no-pager --failed 2>&1; echo; ping -c2 -W3 archive.ubuntu.com 2>&1; "
                   "curl -sI --max-time 8 http://archive.ubuntu.com/ubuntu/dists/resolute/Release 2>&1 | head -3",
    "journal.txt": "journalctl -b --no-pager -n 4000 2>&1",
    "journal-subiquity.txt": "journalctl -b --no-pager -u 'snap.subiquity*' -u 'subiquity*' -u 'ubuntu-server-install*' -n 3000 2>&1",
    "dmesg.txt": "dmesg 2>&1 | tail -1500",
    "processes.txt": "ps auxf | head -150; mount | grep -v cgroup",
}
SECRET = re.compile(r'(?i)(pass(?:word|wd|phrase)?|psk|secret|token|key|hash)(["\']?\s*[:=]\s*)(["\']?)[^\s"\',}]+')
HASH = re.compile(r"\$(?:5|6|y|2[aby])\$[^\s\"',}]+")


def clean(text):
    text = SECRET.sub(lambda m: m.group(1) + m.group(2) + m.group(3) + "<removed>", text)
    return HASH.sub("<hash removed>", text)


def sh(cmd, timeout=40):
    try:
        p = subprocess.run(["sh", "-c", cmd], capture_output=True, text=True, timeout=timeout, errors="replace")
        return p.stdout + p.stderr
    except (subprocess.TimeoutExpired, OSError) as e:
        return "(%s)\n" % e


def tail(path, limit=2_000_000):
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - limit))
            return f.read().decode("utf-8", "replace")
    except OSError:
        return None


def summary(out):
    """The few lines that usually name the problem, for the screen and the top of the report."""
    lines = []
    curtin = tail("/var/log/installer/curtin-install.log", 600_000) or ""
    steps = re.findall(r"^start: (\S+)", curtin, re.M)
    if steps:
        lines.append("last step started: " + steps[-1])
    pat = re.compile(r"(Traceback|Error|ERROR|FAILED|failed|E: |Unable to|Could not|Temporary failure|returned non-zero)")
    hits = [l.strip() for l in curtin.splitlines() if pat.search(l)]
    lines += hits[-8:]
    ui = tail(RUN + "/ui.log", 20000) or ""
    if "error" in ui.lower():
        lines.append("screen log mentions an error (see ui.log)")
    return "\n".join(lines) if lines else "no obvious error line found; send the whole report"


def build():
    work = os.path.join(RUN, NAME)
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work, exist_ok=True)

    def put(name, text):
        dst = os.path.join(work, name.lstrip("/").replace("/", "__"))
        with open(dst, "w") as f:
            f.write(clean(text))

    for p in FILES:
        t = tail(p)
        if t is not None:
            put(p, t)
    for g in GLOBS:
        for p in sorted(glob.glob(g)):
            if os.path.isfile(p):
                t = tail(p)
                if t is not None:
                    put(p, t)
    for name, cmd in CMDS.items():
        put(name, sh(cmd))
    s = summary(work)
    put("SUMMARY.txt", "Ultimit install report %s\n\n%s\n" % (STAMP, s))
    tar = os.path.join(RUN, NAME + ".tar.gz")
    with tarfile.open(tar, "w:gz") as t:
        t.add(work, arcname=NAME)
    shutil.rmtree(work, ignore_errors=True)
    return tar, s


def usb_targets():
    """Writable partitions on removable drives (the install target and the optical boot media are skipped)."""
    out = []
    try:
        j = json.loads(sh("lsblk -J -o PATH,TYPE,FSTYPE,LABEL,MOUNTPOINT,RM,HOTPLUG,RO,TRAN"))
    except ValueError:
        return out

    def walk(nodes, parent_rm=False):
        for n in nodes:
            rm = parent_rm or str(n.get("rm")) in ("1", "True", "true") or str(n.get("hotplug")) in ("1", "True", "true") \
                or n.get("tran") == "usb"
            if n.get("type") == "part" and rm and n.get("fstype") in ("vfat", "exfat", "ext4", "ext3", "ntfs", "btrfs", "xfs") \
                    and str(n.get("ro")) not in ("1", "True", "true") and "VTOYEFI" != n.get("label"):
                out.append(n)
            walk(n.get("children") or [], rm)
    walk(j.get("blockdevices") or [])
    return out


def save_to_usb(tar):
    saved = []
    for i, n in enumerate(usb_targets()):
        mp, mounted_here = n.get("mountpoint"), False
        if mp in ("/", "/cdrom", "/target") or (mp and mp.startswith("/target")):
            continue
        if not mp:
            mp = "%s/usb%d" % (RUN, i)
            os.makedirs(mp, exist_ok=True)
            fs = {"ntfs": "ntfs3"}.get(n["fstype"], n["fstype"])
            if subprocess.run(["mount", "-t", fs, n["path"], mp], capture_output=True).returncode != 0:
                continue
            mounted_here = True
        try:
            dst = os.path.join(mp, os.path.basename(tar))
            shutil.copyfile(tar, dst)
            os.sync()
            saved.append("%s (%s)" % (n.get("label") or n["path"], n["path"]))
        except OSError:
            pass
        finally:
            if mounted_here:
                subprocess.run(["umount", mp], capture_output=True)
    return saved


def main(a):
    as_json = "--json" in a
    os.makedirs(RUN, exist_ok=True)
    tar, s = build()
    saved = [] if "--no-usb" in a else save_to_usb(tar)
    if as_json:
        print(json.dumps({"ok": True, "file": tar, "saved": saved, "summary": s}))
    else:
        print("Report: " + tar)
        print("Saved to: " + (", ".join(saved) if saved else "no USB drive found (plug one in and run this again)"))
        print("\n" + s)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
