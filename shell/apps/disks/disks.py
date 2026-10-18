#!/usr/bin/env python3
"""disks.py - backend of DISKS, the Ultimit disks manager and disk-usage checker (JSON on stdout).

Runs unprivileged: drives, partitions, mounting and formatting go through UDisks2 on the system D-Bus
(gi.repository.Gio); its polkit rules ask for a password through the desktop's own agent. Reading the
state needs none. The D-Bus-to-JSON step (`convert`) is a pure function over a GetManagedObjects dict.

  disks.py state                         drives, their partitions (with free gaps), usage, which formats can be made
  disks.py health DRIVE_ID               SMART summary: verdict good | warning | failing | unknown, plain lines
  disks.py mount DEV | unmount DEV
  disks.py eject DRIVE_ID | power-off DRIVE_ID
  disks.py format DEV FSTYPE LABEL       ext4 | exfat | ntfs | vfat; refuses anything the system is using
  disks.py create-partition DRIVE_ID GAP_OFFSET SIZE FS|none LABEL   in a free gap (1 MiB aligned, clamped to it)
  disks.py delete-partition DEV | resize-partition DEV SIZE | set-label DEV LABEL
  disks.py new-table DRIVE_ID gpt|dos    wipes the whole drive
  disks.py scan PATH                     what takes space: walks PATH once, JSON progress lines, caches the result
  disks.py children PATH                 (from the cache) the biggest direct children of PATH
  disks.py largest ROOT [N]              (from the cache) the biggest files under ROOT
  disks.py peek PATH                     first names on a mounted volume (for the format warning)
  disks.py trash PATH                    move an item of a scanned tree to the trash (gio trash), update the cache

A dismissed password prompt is {ok:false, cancelled:true}, not an error. DISKS_FAKE=1 runs against the fake
drives in fixtures/ (state kept in $TMPDIR/disks-fake-state.json, mounts in a temp dir); nothing real is touched.
"""
import hashlib
import heapq
import json
import os
import re
import shutil
import sqlite3
import stat as statmod
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
UD = "org.freedesktop.UDisks2"
UD_DRIVES = "/org/freedesktop/UDisks2/drives/"
GAP_MIN = 4 << 20            # free space smaller than this between partitions is alignment, not shown
SYSTEM_MOUNTS = {"/", "/home", "/boot", "/efi", "/usr", "/var", "/opt", "/etc", "/srv", "/nix", "/gnu"}
SYSTEM_PREFIXES = ("/boot", "/efi", "/usr", "/var", "/etc")
SKIP_TREES = ("/proc", "/sys", "/dev", "/run")
LDM_DATA = "af9b60a0-1431-4f62-bc68-3311714a69ad"

# fs id -> name shown, mkfs program, label limit (bytes or characters), characters not allowed in a label
FORMATS = [
    {"id": "ext4", "name": "ext4 (Linux)", "tool": "mkfs.ext4", "label_max": 16, "bytes": True, "bad": ""},
    {"id": "exfat", "name": "exFAT (any system, big files)", "tool": "mkfs.exfat", "label_max": 15, "bytes": False, "bad": ""},
    {"id": "ntfs", "name": "NTFS (Windows)", "tool": "mkfs.ntfs", "label_max": 128, "bytes": False, "bad": ""},
    {"id": "vfat", "name": "FAT32 (old devices)", "tool": "mkfs.vfat", "label_max": 11, "bytes": False, "bad": "\"*+,./:;<=>?[\\]|"},
]

GPT_TYPES = {
    "c12a7328-f81f-11d2-ba4b-00a0c93ec93b": "EFI system",
    "e3c9e316-0b5c-4db8-817d-f92df00215ae": "Microsoft reserved",
    "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7": "Basic data",
    "de94bba4-06d1-4d40-a16a-bfd50179d6ac": "Windows recovery",
    LDM_DATA: "Windows dynamic disk data",
    "5808c8aa-7e8f-42e0-85d2-e1e90434cfb3": "Windows dynamic disk metadata",
    "0fc63daf-8483-4772-8e79-3d69d8477de4": "Linux filesystem",
    "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f": "Linux swap",
    "933ac7e1-2eb4-4f13-b844-0e14e2aef915": "Linux home",
    "4f68bce3-e8cd-4db1-96e7-fbcaf984b709": "Linux root",
    "e6d6d379-f507-44c2-a23c-238f2a3df928": "Linux LVM",
    "ca7d7ccb-63ed-4c53-861c-1742536059cc": "Linux LUKS",
    "21686148-6449-6e6f-744e-656564726976": "BIOS boot",
    "bc13c2ff-59e6-4262-a352-b275fd6f7172": "Boot loader",
    "a19d880f-05fc-4d3b-a006-743f0f84911e": "Linux RAID",
    "48465300-0000-11aa-aa11-00306543ecba": "Apple HFS+",
    "7c3457ef-0000-11aa-aa11-00306543ecba": "Apple APFS",
}
MBR_TYPES = {
    "0x01": "FAT12", "0x04": "FAT16", "0x06": "FAT16", "0x07": "NTFS / exFAT", "0x0b": "FAT32", "0x0c": "FAT32",
    "0x0e": "FAT16", "0x05": "Extended", "0x0f": "Extended", "0x82": "Linux swap", "0x83": "Linux filesystem",
    "0x8e": "Linux LVM", "0xee": "GPT protective", "0xef": "EFI system", "0xfd": "Linux RAID", "0x27": "Windows recovery",
    "0x42": "Windows dynamic disk", "0xa5": "FreeBSD", "0xaf": "Apple HFS+",
}
MIB = 1 << 20
GPT_LINUX = "0fc63daf-8483-4772-8e79-3d69d8477de4"
GPT_BASIC = "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7"
# Manager.CanResize mode bits
OFF_SHRINK, OFF_GROW, ON_SHRINK, ON_GROW = 2, 4, 8, 16
CHECK_FIRST = ("ext2", "ext3", "ext4")      # offline resize2fs refuses a file system that was not checked since its last mount
FAKE_CAN_RESIZE = {"ext4": (True, 22, ""), "ntfs": (True, 6, ""), "btrfs": (True, 24, ""), "xfs": (True, 20, ""),
                   "vfat": (False, 6, "vfat-resize")}
RESIZE_TOOLS = {"ntfs": "ntfsresize"}
TABLES = ("gpt", "dos")

FS_NAMES = {"ntfs": "NTFS", "vfat": "FAT32", "exfat": "exFAT", "ext4": "ext4", "ext3": "ext3", "ext2": "ext2",
            "btrfs": "Btrfs", "xfs": "XFS", "f2fs": "F2FS", "swap": "swap", "crypto_LUKS": "LUKS encrypted",
            "LVM2_member": "LVM", "iso9660": "ISO 9660", "udf": "UDF", "hfsplus": "HFS+", "apfs": "APFS",
            "linux_raid_member": "RAID member", "BitLocker": "BitLocker"}


def out(o):
    sys.stdout.write(json.dumps(o))
    sys.stdout.write("\n")
    sys.stdout.flush()


def fake():
    return os.environ.get("DISKS_FAKE") == "1"


# ---------------------------------------------------------------- pure conversion: GetManagedObjects -> drives

def bstr(v):
    """A D-Bus byte string (bytes, a list of ints, or already text) as text, cut at the NUL."""
    if v is None:
        return ""
    if isinstance(v, str):
        return v.split("\0")[0]
    if isinstance(v, (bytes, bytearray)):
        return bytes(v).split(b"\0")[0].decode("utf-8", "replace")
    if isinstance(v, (list, tuple)) and all(isinstance(x, int) for x in v):
        return bytes(v).split(b"\0")[0].decode("utf-8", "replace")
    return str(v)


def bstrs(v):
    return [bstr(x) for x in (v or [])]


def valid_path(p):
    return isinstance(p, str) and p not in ("", "/")


def system_mount(mp):
    return mp in SYSTEM_MOUNTS or any(mp.startswith(p + "/") for p in SYSTEM_PREFIXES)


def default_usage(mountpoint):
    """-> (total, used, free) of a mounted filesystem, or None."""
    try:
        s = os.statvfs(mountpoint)
    except OSError:
        return None
    total = s.f_blocks * s.f_frsize
    return total, (s.f_blocks - s.f_bfree) * s.f_frsize, s.f_bavail * s.f_frsize


def type_name(table, tid):
    if table == "gpt":
        return GPT_TYPES.get((tid or "").lower(), "")
    return MBR_TYPES.get((tid or "").lower(), "")


def fs_name(fs):
    return FS_NAMES.get(fs, fs)


def kind_of(optical, bus, rotational):
    if bus == "loop":
        return "image"
    if optical:
        return "optical"
    if bus in ("usb", "mmc", "nvme"):
        return {"usb": "usb", "mmc": "sd", "nvme": "nvme"}[bus]
    if rotational is True:
        return "hdd"
    if rotational is False:
        return "ssd"
    return "disk"


def convert(objs, sysinfo=None, usage=None):
    """GetManagedObjects dict ({path: {iface: {prop: value}}}) -> list of drives, each with its partitions in
    disk order and the free gaps between them. `sysinfo` {block name: {bus, rotational, holders}} fills in what
    UDisks leaves empty; `usage(mountpoint)` -> (total, used, free) | None (default: statvfs)."""
    sysinfo = sysinfo or {}
    usage = usage or default_usage

    def I(name):
        return UD + "." + name
    blocks = {p: i for p, i in objs.items() if I("Block") in i}
    devname = {p: os.path.basename(bstr(i[I("Block")].get("Device"))) for p, i in blocks.items()}
    by_name = {n: p for p, n in devname.items() if n}

    def blk(p):
        return blocks[p][I("Block")]

    # blocks stacked on another block: an unlocked LUKS volume, a device-mapper volume (LVM, LDM) on top of it
    inner = {}

    def add_inner(under, over):
        if under in blocks and over in blocks and over != under and over not in inner.setdefault(under, []):
            inner[under].append(over)
    for p in blocks:
        cb = blk(p).get("CryptoBackingDevice")
        if valid_path(cb):
            add_inner(cb, p)
    for p, n in devname.items():
        for h in sysinfo.get(n, {}).get("holders", []):
            if h in by_name:
                add_inner(p, by_name[h])

    # attached disk images (loop devices) have no Drive object: their whole-disk block stands in for it
    sources = [(p, i, i[I("Drive")], False) for p, i in objs.items() if I("Drive") in i]
    for p, i in blocks.items():
        lo = i.get(I("Loop"))
        if lo is None or I("Partition") in i or not bstr(lo.get("BackingFile")) or not blk(p).get("Size"):
            continue
        if valid_path(blk(p).get("CryptoBackingDevice")):
            continue
        sources.append((p, {}, {"Model": "Disk image " + os.path.basename(bstr(lo.get("BackingFile"))),
                                "Size": blk(p).get("Size"), "Ejectable": True, "SortKey": "~" + devname[p]}, True))

    drives = []
    for dpath, ifs, d, is_loop in sources:
        disk = dpath if is_loop else next(
            (p for p, i in blocks.items() if blk(p).get("Drive") == dpath and I("Partition") not in i), None)
        name = devname.get(disk, "") if disk else ""
        sysi = sysinfo.get(name, {})
        bus = d.get("ConnectionBus") or sysi.get("bus") or ""
        if is_loop:
            bus = "loop"
        if bus == "sdio":
            bus = "mmc"
        if not bus:
            bus = "sata" if I("Drive.Ata") in ifs else "nvme" if I("NVMe.Controller") in ifs else "unknown"
        rot = sysi.get("rotational")
        if rot is None:
            rr = d.get("RotationRate", 0)
            rot = True if (isinstance(rr, int) and rr != 0) else (False if I("Drive.Ata") in ifs else None)
        size = int(d.get("Size", 0) or 0)
        table = ""
        if disk and I("PartitionTable") in blocks[disk]:
            table = blocks[disk][I("PartitionTable")].get("Type", "")
        parts = []
        if disk:
            for p, i in blocks.items():
                if I("Partition") in i and i[I("Partition")].get("Table") == disk:
                    parts.append(p)
        parts.sort(key=lambda p: (blocks[p][I("Partition")].get("Offset", 0), p))

        # volumes on the whole disk rather than on a partition (a Windows dynamic-disk volume): they belong
        # to the partition that carries the data
        orphan = {}
        if disk:
            for o in inner.get(disk, []):
                if I("Filesystem") in blocks[o]:
                    cands = [p for p in parts if blocks[p][I("Partition")].get("Type", "").lower() == LDM_DATA]
                    cands = cands or sorted((p for p in parts if not blk(p).get("IdType")),
                                            key=lambda p: -blocks[p][I("Partition")].get("Size", 0))
                    if cands:
                        orphan.setdefault(cands[0], []).append(o)

        def volume(p, offset, psize, number, pname, ptype, contained=False):
            b = blk(p)
            fs = b.get("IdType", "")
            under = list(inner.get(p, [])) + orphan.get(p, [])
            fsrc = p                      # the block that holds the filesystem we show and act on
            members = []
            locked = False
            if under:
                fs_under = [o for o in under if I("Filesystem") in blocks[o]]
                if len(under) == 1 and fs_under:
                    fsrc = under[0]
                else:
                    members = under
            elif I("Encrypted") in blocks[p] or fs == "crypto_LUKS":
                locked = True
            fb = blk(fsrc)
            fifs = blocks[fsrc]
            holders = members or [fsrc]
            swap = fb.get("IdType") == "swap" or fs == "swap" or I("Swapspace") in fifs
            mounts = []
            reasons = []
            for o in holders:
                if I("Filesystem") in blocks[o]:
                    mounts += [m for m in bstrs(blocks[o][I("Filesystem")].get("MountPoints")) if m]
                if I("Swapspace") in blocks[o] and blocks[o][I("Swapspace")].get("Active"):
                    reasons.append("Active swap space")
            for m in mounts:
                if system_mount(m):
                    reasons.insert(0, "Holds %s, which the system needs" % m)
            use = usage(mounts[0]) if mounts else None
            fsname = fs if members or fsrc == p else fb.get("IdType", "")
            v = {
                "kind": "partition", "device": bstr(b.get("Device")), "target": bstr(fb.get("Device")),
                "number": number, "offset": offset, "size": psize,
                "type_id": ptype or "", "type": type_name(table, ptype) if ptype else "", "name": pname or "",
                "fs": fsname, "fs_name": fs_name(fsname), "label": fb.get("IdLabel", ""), "uuid": fb.get("IdUUID", ""),
                "mounts": mounts, "mounted": bool(mounts),
                "used": use[1] if use else None, "free": use[2] if use else None, "fs_size": use[0] if use else None,
                "is_system": bool(reasons), "system_reason": reasons[0] if reasons else "",
                "mountable": (I("Filesystem") in fifs) and not members and not swap,
                "locked": locked, "crypto": locked or I("Encrypted") in blocks[p] or fs == "crypto_LUKS",
                "swap": swap, "members": [bstr(blk(o).get("Device")) for o in members],
                "read_only": bool(b.get("ReadOnly")), "contained": contained,
            }
            v["can_format"] = not (reasons or members or fsrc != p or v["read_only"])
            return v

        plist = []
        for p in parts:
            pp = blocks[p][I("Partition")]
            if pp.get("IsContainer"):
                continue                      # an extended partition: its logical partitions are listed instead
            plist.append(volume(p, int(pp.get("Offset", 0)), int(pp.get("Size", 0)), int(pp.get("Number", 0)),
                                pp.get("Name", ""), pp.get("Type", ""), bool(pp.get("IsContained"))))
        if disk and not parts and not table and size > 0:
            plist.append(volume(disk, 0, size, 0, "", ""))     # no partition table: the whole disk is the volume
        items, cur = [], 0
        for v in plist:
            if v["offset"] - cur >= GAP_MIN:
                items.append({"kind": "free", "offset": cur, "size": v["offset"] - cur})
            items.append(v)
            cur = max(cur, v["offset"] + v["size"])
        if size - cur >= GAP_MIN:
            items.append({"kind": "free", "offset": cur, "size": size - cur})

        vendor, model = (d.get("Vendor") or "").strip(), (d.get("Model") or "").strip()
        title = (model if model.startswith(vendor) else (vendor + " " + model)).strip() or "Drive"
        sys_parts = [v for v in plist if v["is_system"]]
        drives.append({
            "id": dpath.rsplit("/", 1)[-1], "name": title, "model": model, "vendor": vendor,
            "serial": d.get("Serial", ""), "size": size,
            "bus": bus, "kind": kind_of(d.get("Optical"), bus, rot), "rotational": rot,
            "removable": bool(d.get("Removable") or d.get("MediaRemovable")),
            "ejectable": bool(d.get("Ejectable")), "can_power_off": bool(d.get("CanPowerOff")),
            "media": d.get("Media", ""), "media_available": d.get("MediaAvailable", True) is not False,
            "device": bstr(blk(disk).get("Device")) if disk else "", "table": table,
            "smart": I("Drive.Ata") in ifs or I("NVMe.Controller") in ifs,
            "is_system": bool(sys_parts), "system_reason": sys_parts[0]["system_reason"] if sys_parts else "",
            "loop": is_loop, "sort": d.get("SortKey", ""), "partitions": items,
        })
    drives.sort(key=lambda x: (x["sort"], x["device"]))
    for d in drives:
        d.pop("sort")
    return drives


def find_volume(drives, dev):
    """-> (drive, volume) for a device node (the partition, or the device the filesystem lives on)."""
    for d in drives:
        for v in d["partitions"]:
            if v["kind"] == "partition" and dev in (v["device"], v["target"]):
                return d, v
    return None, None


# ---------------------------------------------------------------- SMART verdict (pure)

def _hours_text(h):
    if h < 48:
        return "%d hours" % h
    days = h // 24
    return "%d days" % days if days < 730 else "%.1f years" % (days / 365.25)


def health_summary(kind, props, attrs):
    """kind 'ata' | 'nvme'; props: the SMART properties of the drive's interface; attrs: SmartGetAttributes result
    (ATA: list of [id, name, flags, value, worst, threshold, pretty, unit, ...]; NVMe: dict). -> summary dict."""
    lines, bad, warn = [], [], []
    temp_c = None
    t = props.get("SmartTemperature")
    if isinstance(t, (int, float)) and t > 0:
        temp_c = round(t - 273.15)
    hours = None
    attributes = []
    if kind == "ata":
        if not props.get("SmartSupported"):
            return {"ok": True, "verdict": "unknown", "title": "No health data",
                    "lines": [{"text": "This drive does not report health information (SMART), or it is switched off. "
                                       "That is normal for some USB adapters and memory sticks.", "tone": "dim"}],
                    "temperature_c": None, "power_on_hours": None, "attributes": []}
        hours = int(props.get("SmartPowerOnSeconds", 0) or 0) // 3600
        raw = {}
        for a in attrs or []:
            raw[a[0]] = a[6]
            attributes.append({"id": a[0], "name": a[1].replace("-", " "), "value": a[3], "worst": a[4],
                               "threshold": a[5], "raw": a[6]})
        if props.get("SmartFailing"):
            bad.append("The drive reports that it is failing.")
        nf = props.get("SmartNumAttributesFailing", -1)
        if isinstance(nf, int) and nf > 0:
            bad.append("%d health indicator%s past the manufacturer's limit." % (nf, "" if nf == 1 else "s"))
        realloc, pending, uncorr = raw.get(5, 0), raw.get(197, 0), raw.get(198, 0)
        if realloc:
            (bad if realloc >= 100 else warn).append(
                "%d sector%s reallocated (the drive moved data off damaged areas)." % (realloc, "" if realloc == 1 else "s"))
        if pending:
            warn.append("%d sector%s waiting to be reallocated (could not be read reliably)." % (pending, "" if pending == 1 else "s"))
        if uncorr:
            warn.append("%d sector%s could not be corrected." % (uncorr, "" if uncorr == 1 else "s"))
        nb = props.get("SmartNumBadSectors", -1)
        if isinstance(nb, int) and nb > 0 and not realloc and not pending:
            warn.append("%d bad sector%s." % (nb, "" if nb == 1 else "s"))
        st = props.get("SmartSelftestStatus", "")
        if st == "fatal" or st.startswith("error"):
            warn.append("The last self-test found a problem (%s)." % st.replace("_", " "))
        elif st == "success":
            lines.append({"text": "Last self-test passed.", "tone": "ok"})
        elif st == "inprogress":
            lines.append({"text": "A self-test is running.", "tone": "dim"})
    else:
        crit = props.get("SmartCriticalWarning") or []
        if crit:
            names = {"spare": "spare capacity is low", "temperature": "temperature is out of range",
                     "degraded": "reliability is degraded", "readonly": "it switched to read-only",
                     "volatile_memory": "its volatile memory backup failed", "pmr_readonly": "persistent memory is read-only"}
            bad.append("The drive raised a critical warning: " + ", ".join(names.get(c, c) for c in crit) + ".")
        hours = props.get("SmartPowerOnHours")
        a = attrs if isinstance(attrs, dict) else {}
        used = a.get("percent_used")
        if isinstance(used, int) and used >= 0:
            attributes.append({"name": "wear used", "raw": "%d%%" % used})
            if used >= 100:
                bad.append("The drive reports its rated write endurance is used up (%d%%)." % used)
            elif used >= 90:
                warn.append("%d%% of the drive's rated write endurance is used." % used)
        spare, thr = a.get("avail_spare"), a.get("spare_thresh")
        if isinstance(spare, int):
            attributes.append({"name": "spare capacity", "raw": "%d%%" % spare})
            if isinstance(thr, int) and spare < thr:
                bad.append("Spare capacity (%d%%) is below the drive's limit (%d%%)." % (spare, thr))
        me = a.get("media_errors")
        if isinstance(me, int):
            attributes.append({"name": "media errors", "raw": str(me)})
            if me > 0:
                warn.append("%d media error%s logged." % (me, "" if me == 1 else "s"))
        st = props.get("SmartSelftestStatus", "")
        if st.startswith("failed") or st == "fatal" or st.startswith("error"):
            warn.append("The last self-test found a problem (%s)." % st.replace("_", " "))
    if temp_c is not None:
        if temp_c >= 70:
            warn.append("It is hot: %d °C." % temp_c)
        else:
            lines.append({"text": "Temperature %d °C." % temp_c, "tone": "ok" if temp_c < 60 else "warn"})
    if isinstance(hours, int) and hours >= 0:
        lines.append({"text": "Powered on for %s." % _hours_text(hours), "tone": "dim"})
    verdict = "failing" if bad else "warning" if warn else "good"
    title = {"failing": "Failing: back up now", "warning": "Warning", "good": "Healthy"}[verdict]
    head = [{"text": "The drive reports no problems.", "tone": "ok"}] if verdict == "good" else []
    lines = head + [{"text": x, "tone": "bad"} for x in bad] + [{"text": x, "tone": "warn"} for x in warn] + lines
    if verdict == "failing":
        lines.append({"text": "Copy anything you care about to another drive soon.", "tone": "bad"})
    return {"ok": True, "verdict": verdict, "title": title, "lines": lines, "temperature_c": temp_c,
            "power_on_hours": hours, "attributes": attributes}


# ---------------------------------------------------------------- label validation / formats

def available_formats(which=shutil.which):
    path = os.environ.get("PATH", "") + ":/usr/sbin:/sbin"
    return [{k: f[k] for k in ("id", "name", "label_max", "bytes", "bad")} for f in FORMATS if which(f["tool"], path=path)]


def check_label(fs, label):
    """-> error text or None."""
    f = next((f for f in FORMATS if f["id"] == fs), None)
    if not f:
        return "Unknown file system."
    if any(ord(c) < 32 or ord(c) == 127 for c in label):
        return "The name cannot contain control characters."
    n = len(label.encode("utf-8")) if f["bytes"] else len(label)
    if n > f["label_max"]:
        return "The name can be at most %d %s for %s." % (f["label_max"], "bytes" if f["bytes"] else "characters",
                                                          "FAT32" if fs == "vfat" else fs)
    bad = sorted(set(c for c in label if c in f["bad"]))
    if bad:
        return "FAT32 names cannot contain %s" % " ".join(bad)
    return None


# ---------------------------------------------------------------- backends (UDisks2 over D-Bus / the fake)

def friendly_error(msg):
    msg = re.sub(r"^GDBus\.Error:[\w.]+:\s*", "", msg or "").strip()
    if "busy" in msg.lower():
        return "Something is still using it. Close the programs and files on it and try again."
    return msg or "That did not work."


class Cancelled(Exception):
    pass


class Failed(Exception):
    pass


class Real:
    """UDisks2 on the system bus."""

    def __init__(self):
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib
        self.Gio, self.GLib = Gio, GLib
        self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

    def _call(self, path, iface, method, params, timeout=60000):
        try:
            return self.bus.call_sync(UD, path, iface, method, params, None, self.Gio.DBusCallFlags.NONE, timeout, None)
        except self.GLib.Error as e:
            name = ""
            try:
                name = self.Gio.DBusError.get_remote_error(e) or ""
            except Exception:
                pass
            text = name + " " + e.message
            if "NotAuthorized" in text:
                if "Dismissed" in text:
                    raise Cancelled()
                raise Failed("You are not allowed to do that.")
            raise Failed(friendly_error(e.message))

    def _opts(self, extra=None):
        V = self.GLib.Variant
        o = {"auth.no_user_interaction": V("b", False)}
        for k, v in (extra or {}).items():
            o[k] = V("b", v) if isinstance(v, bool) else V("s", v)
        return o

    def _opt_call(self, path, iface, method, extra=None, timeout=60000):
        return self._call(path, iface, method, self.GLib.Variant("(a{sv})", (self._opts(extra),)), timeout)

    def objects(self):
        return self._call("/org/freedesktop/UDisks2", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", None).unpack()[0]

    def mount(self, block):
        return self._opt_call(block, UD + ".Filesystem", "Mount").unpack()[0]

    def unmount(self, block):
        self._opt_call(block, UD + ".Filesystem", "Unmount")

    def eject(self, drive):
        if "/block_devices/" in drive:             # a disk image: detach it (the image file stays)
            self._opt_call(drive, UD + ".Loop", "Delete")
            return
        self._opt_call(drive, UD + ".Drive", "Eject")

    def power_off(self, drive):
        self._opt_call(drive, UD + ".Drive", "PowerOff")

    def format(self, block, fs, label):
        V = self.GLib.Variant
        o = self._opts({"label": label, "update-partition-type": True, "tear-down": True})
        if fs == "ext4":
            o["take-ownership"] = V("b", True)
        self._call(block, UD + ".Block", "Format", V("(sa{sv})", (fs, o)), timeout=900000)

    def create_partition(self, table, offset, size, ptype, name, fs, label):
        V = self.GLib.Variant
        if fs == "none":
            return self._call(table, UD + ".PartitionTable", "CreatePartition",
                              V("(ttssa{sv})", (offset, size, ptype, name, self._opts())), timeout=120000)
        fo = {"label": V("s", label)}
        if fs == "ext4":
            fo["take-ownership"] = V("b", True)
        return self._call(table, UD + ".PartitionTable", "CreatePartitionAndFormat",
                          V("(ttssa{sv}sa{sv})", (offset, size, ptype, name, self._opts(), fs, fo)), timeout=900000)

    def delete_partition(self, block):
        self._opt_call(block, UD + ".Partition", "Delete", {"tear-down": True}, timeout=120000)

    def resize_partition(self, block, size):
        self._call(block, UD + ".Partition", "Resize", self.GLib.Variant("(ta{sv})", (size, self._opts())), timeout=120000)

    def fs_resize(self, block, size):
        self._call(block, UD + ".Filesystem", "Resize", self.GLib.Variant("(ta{sv})", (size, self._opts())), timeout=1800000)

    def fs_check(self, block):
        # Repair, not Check: Check is read-only (e2fsck -n), which resize2fs does not accept as checked;
        # Repair is the forced e2fsck it wants, and changes nothing on a clean file system
        return bool(self._opt_call(block, UD + ".Filesystem", "Repair", timeout=1800000).unpack()[0])

    def set_label(self, block, label):
        self._call(block, UD + ".Filesystem", "SetLabel", self.GLib.Variant("(sa{sv})", (label, self._opts())))

    def new_table(self, disk, kind):
        V = self.GLib.Variant
        self._call(disk, UD + ".Block", "Format", V("(sa{sv})", (kind, self._opts({"tear-down": True}))), timeout=300000)

    def can_resize(self, fs):
        """Manager.CanResize -> (available, mode bits, utility needed when not available)."""
        try:
            r = self._call("/org/freedesktop/UDisks2/Manager", UD + ".Manager", "CanResize",
                           self.GLib.Variant("(s)", (fs,)), timeout=10000).unpack()[0]
            return bool(r[0]), int(r[1]), r[2]
        except Failed:
            return False, 0, ""

    def smart(self, drive, kind):
        """Refresh the drive's SMART data -> (properties, attributes) of the SMART interface."""
        V = self.GLib.Variant
        iface = UD + (".Drive.Ata" if kind == "ata" else ".NVMe.Controller")
        self._opt_call(drive, iface, "SmartUpdate", timeout=120000)
        props = self._call(drive, "org.freedesktop.DBus.Properties", "GetAll", V("(s)", (iface,))).unpack()[0]
        attrs = self._opt_call(drive, iface, "SmartGetAttributes").unpack()[0]
        return props, attrs

    def sysinfo(self, objs):
        return real_sysinfo(objs)

    usage = None


def real_sysinfo(objs):
    """Bus, rotational flag and holders of each block device, from /sys (UDisks leaves some of it empty)."""
    res = {}
    for p, i in objs.items():
        b = i.get(UD + ".Block")
        if not b:
            continue
        n = os.path.basename(bstr(b.get("Device")))
        base = "/sys/class/block/" + n
        if not n or not os.path.isdir(base):
            continue
        s = {}
        try:
            s["holders"] = sorted(os.listdir(base + "/holders"))
        except OSError:
            pass
        if UD + ".Partition" not in i:
            real = os.path.realpath(base)
            s["bus"] = ("usb" if "/usb" in real else "mmc" if "/mmc" in real or n.startswith("mmcblk") else
                        "nvme" if n.startswith("nvme") else "sata" if "/ata" in real else "virtio" if "/virtio" in real else
                        "scsi" if "/host" in real else "")
            try:
                with open(base + "/queue/rotational") as f:
                    s["rotational"] = f.read().strip() == "1"
            except OSError:
                pass
        res[n] = s
    return res


class Fake:
    """A pretend UDisks2: the objects of fixtures/fake-objects.json, kept in a state file so actions stick."""

    def __init__(self):
        self.path = os.environ.get("DISKS_FAKE_STATE") or os.path.join(os.environ.get("TMPDIR", "/tmp"), "disks-fake-state.json")
        self.mnt = os.path.join(os.path.dirname(self.path), "disks-fake-mnt")
        if os.path.exists(self.path):
            with open(self.path) as f:
                self.data = json.load(f)
        else:
            with open(os.path.join(HERE, "fixtures", "fake-objects.json")) as f:
                self.data = json.load(f)
            for i in self.data["objects"].values():     # mounted at start: real (small) folders in the temp dir
                fsi = i.get(UD + ".Filesystem")
                if fsi and fsi.get("MountPoints"):
                    fsi["MountPoints"] = [self.fake_mount(m) for m in fsi["MountPoints"]]
            self.save()

    def fake_mount(self, mp):
        if not mp.startswith("/run/media/fake/"):
            return mp
        d = os.path.join(self.mnt, mp.rsplit("/", 1)[-1])
        make_fake_tree(d)
        return d

    def save(self):
        with open(self.path, "w") as f:
            json.dump(self.data, f)

    def objects(self):
        return self.data["objects"]

    def sysinfo(self, objs):
        return {}

    def usage(self, mountpoint):
        for dev, u in self.data.get("usage", {}).items():
            o = self.data["objects"].get(self.blockpath(dev))
            if o and mountpoint in bstrs(o.get(UD + ".Filesystem", {}).get("MountPoints")):
                return u[0], u[1], u[0] - u[1]
        return None

    def blockpath(self, dev):
        for p, i in self.data["objects"].items():
            if UD + ".Block" in i and bstr(i[UD + ".Block"].get("Device")) == dev:
                return p
        return None

    def mount(self, block):
        fsi = self.data["objects"][block][UD + ".Filesystem"]
        if fsi.get("MountPoints"):
            raise Failed("It is already mounted.")
        b = self.data["objects"][block][UD + ".Block"]
        d = os.path.join(self.mnt, re.sub(r"[^\w.-]+", "_", b.get("IdLabel") or os.path.basename(b["Device"])))
        make_fake_tree(d)
        fsi["MountPoints"] = [d]
        self.save()
        return d

    def unmount(self, block):
        self.data["objects"][block][UD + ".Filesystem"]["MountPoints"] = []
        self.save()

    def eject(self, drive):
        o = self.data["objects"]
        for p in [p for p, i in o.items() if i.get(UD + ".Block", {}).get("Drive") == drive]:
            o.pop(p)
        o.pop(drive, None)
        self.save()

    power_off = eject

    def format(self, block, fs, label):
        b = self.data["objects"][block][UD + ".Block"]
        b["IdType"], b["IdLabel"] = fs, label
        self.data.setdefault("usage", {})[bstr(b["Device"])] = [b.get("Size", 0), 4 << 20]
        self.save()

    def _blocks_of(self, disk):
        o = self.data["objects"]
        return [p for p, i in o.items() if i.get(UD + ".Partition", {}).get("Table") == disk]

    def create_partition(self, table, offset, size, ptype, name, fs, label):
        o = self.data["objects"]
        disk = o[table][UD + ".Block"]
        dev = bstr(disk["Device"])
        nums = [o[p][UD + ".Partition"]["Number"] for p in self._blocks_of(table)]
        n = max(nums or [0]) + 1
        pdev = dev + ("p" if dev[-1].isdigit() else "") + str(n)
        path = "/org/freedesktop/UDisks2/block_devices/" + os.path.basename(pdev)
        blk = {"CryptoBackingDevice": "/", "Device": pdev, "Drive": disk["Drive"], "IdLabel": label if fs != "none" else "",
               "IdType": fs if fs != "none" else "", "IdUUID": ("FAKE-%04d" % n) if fs != "none" else "",
               "ReadOnly": False, "Size": size}
        obj = {UD + ".Block": blk, UD + ".Partition": {"IsContained": False, "IsContainer": False, "Name": name, "Number": n,
                                                        "Offset": offset, "Size": size, "Table": table, "Type": ptype}}
        if fs != "none":
            obj[UD + ".Filesystem"] = {"MountPoints": []}
        o[path] = obj
        if fs != "none":
            self.data.setdefault("usage", {})[pdev] = [size, 4 << 20]
        self.save()
        return path

    def delete_partition(self, block):
        gone = self.data["objects"].pop(block)
        self.data.get("usage", {}).pop(bstr(gone[UD + ".Block"]["Device"]), None)
        self.save()

    def resize_partition(self, block, size):
        o = self.data["objects"][block]
        o[UD + ".Partition"]["Size"] = size
        o[UD + ".Block"]["Size"] = size
        self.save()

    def fs_resize(self, block, size):
        dev = bstr(self.data["objects"][block][UD + ".Block"]["Device"])
        u = self.data.setdefault("usage", {}).get(dev)
        if u:
            u[0] = size
            if u[1] > size:
                raise Failed("The data does not fit.")
        self.save()

    def fs_check(self, block):
        return True

    def set_label(self, block, label):
        self.data["objects"][block][UD + ".Block"]["IdLabel"] = label
        self.save()

    def new_table(self, disk, kind):
        o = self.data["objects"]
        for p in self._blocks_of(disk):
            o.pop(p)
        o[disk][UD + ".PartitionTable"] = {"Type": kind}
        self.save()

    def can_resize(self, fs):
        return FAKE_CAN_RESIZE.get(fs, (False, 0, ""))

    def smart(self, drive, kind):
        h = self.data.get("health", {}).get(drive.rsplit("/", 1)[-1])
        if h is None:
            raise Failed("No health data.")
        return h["props"], h["attrs"]


def make_fake_tree(d):
    """A small pretend volume: a few folders with files (real bytes, so the usage scan has something to show)."""
    if os.path.isdir(d) and os.listdir(d):
        return
    spec = {"Games/Steam": [4, 700000], "Games/Saves": [6, 40000], "Videos": [3, 1500000], "Music": [8, 250000],
            "Documents": [10, 30000], "Backups": [2, 2200000]}
    import random
    rnd = random.Random(7)
    for rel, (n, size) in spec.items():
        os.makedirs(os.path.join(d, rel), exist_ok=True)
        for k in range(n):
            with open(os.path.join(d, rel, "file%02d.bin" % k), "wb") as f:
                f.write(rnd.randbytes(int(size * (0.4 + rnd.random()))))


def backend():
    return Fake() if fake() else Real()


# ---------------------------------------------------------------- commands: state / health / actions

def load(be):
    objs = be.objects()
    drives = convert(objs, be.sysinfo(objs), be.usage)
    if isinstance(be, Real):
        remember_used(drives)
    return drives, objs


def remember_used(drives):
    """Used space of unmounted volumes, as last measured while mounted (since login; kept by UUID in the cache
    dir), so a volume that was unmounted can still be offered for shrinking. Resizing measures again anyway."""
    f = os.path.join(cache_dir(), "used.json")
    try:
        with open(f, encoding="utf-8") as fh:
            known = json.load(fh)
    except (OSError, ValueError):
        known = {}
    seen = dict(known)
    for d in drives:
        for v in d["partitions"]:
            if v["kind"] != "partition" or not v["uuid"]:
                continue
            key = v["uuid"] + ":" + v["fs"]
            if v["used"] is not None:
                seen[key] = [v["used"], v["fs_size"]]
            elif key in known:
                v["used"], v["fs_size"] = known[key]
                v["free"] = max(0, v["fs_size"] - v["used"]) if v["fs_size"] else None
                v["used_remembered"] = True
    if seen != known:
        try:
            with open(f + ".tmp", "w", encoding="utf-8") as fh:
                json.dump(seen, fh)
            os.replace(f + ".tmp", f)
        except OSError:
            pass


def state(be=None):
    be = be or backend()
    drives, _ = load(be)
    annotate(drives, be.can_resize)
    return {"ok": True, "fake": fake(), "home": os.path.expanduser("~"), "formats": available_formats(), "drives": drives}


def result(fn):
    """Run an action, mapping the backend's exceptions to the JSON the UI expects."""
    try:
        r = fn()
        o = {"ok": True}
        if isinstance(r, dict):
            o.update(r)
        return o
    except Cancelled:
        return {"ok": False, "cancelled": True}
    except Failed as e:
        return {"ok": False, "error": str(e)}


def health(drive_id, be=None):
    be = be or backend()
    objs = be.objects()
    dp = UD_DRIVES + drive_id
    if dp not in objs:
        return {"ok": False, "error": "That drive is gone."}
    ifs = objs[dp]
    if UD + ".NVMe.Controller" in ifs:
        kind, iface = "nvme", UD + ".NVMe.Controller"
    elif UD + ".Drive.Ata" in ifs:
        kind, iface = "ata", UD + ".Drive.Ata"
    else:
        return {"ok": True, "verdict": "unknown", "title": "No health data", "temperature_c": None, "power_on_hours": None,
                "attributes": [], "lines": [{"text": "This drive does not report health information (SMART). "
                                                     "That is normal for memory sticks and many USB adapters.", "tone": "dim"}]}
    if kind == "ata" and not ifs[iface].get("SmartSupported") and not isinstance(be, Fake):
        return health_summary("ata", ifs[iface], [])
    try:
        props, attrs = be.smart(dp, kind)
        return health_summary(kind, props, attrs)
    except Cancelled:
        return {"ok": False, "cancelled": True}
    except Failed as e:
        props = ifs.get(iface, {})
        if kind == "nvme" and props.get("SmartUpdated"):   # what UDisks already knows
            o = health_summary("nvme", props, {})
            o["lines"].append({"text": "Could not refresh the data now (%s)." % e, "tone": "dim"})
            return o
        return {"ok": False, "error": str(e)}


def volume_for(be, dev):
    if not re.match(r"^/dev/[\w./-]+$", dev or "") or ".." in dev:
        return None, None, None
    drives, objs = load(be)
    d, v = find_volume(drives, dev)
    return d, v, objs


def block_path(objs, dev):
    for p, i in objs.items():
        b = i.get(UD + ".Block")
        if b and bstr(b.get("Device")) == dev:
            return p
    return None


def uses_system(v):
    return v["is_system"] or any(system_mount(m) for m in v["mounts"])


def mount(dev, be=None):
    be = be or backend()
    d, v, objs = volume_for(be, dev)
    if not v:
        return {"ok": False, "error": "That volume is gone."}
    if not v["mountable"]:
        return {"ok": False, "error": "This volume cannot be mounted."}
    if v["mounted"]:
        return {"ok": True, "mountpoint": v["mounts"][0]}
    return result(lambda: {"mountpoint": be.mount(block_path(objs, v["target"]))})


def unmount_volume(be, objs, v):
    if v["mounted"]:
        be.unmount(block_path(objs, v["target"]))


def unmount(dev, be=None):
    be = be or backend()
    d, v, objs = volume_for(be, dev)
    if not v:
        return {"ok": False, "error": "That volume is gone."}
    if uses_system(v):
        return {"ok": False, "error": "The system is using this volume."}
    return result(lambda: unmount_volume(be, objs, v))


def with_drive(drive_id, be, action):
    drives, objs = load(be)
    d = next((x for x in drives if x["id"] == drive_id), None)
    if not d:
        return {"ok": False, "error": "That drive is gone."}
    vols = [v for v in d["partitions"] if v["kind"] == "partition"]
    if d["is_system"] or any(uses_system(v) for v in vols):
        return {"ok": False, "error": "The system is using this drive."}

    def go():
        action(d, block_path(objs, d["device"]) if d.get("loop") else UD_DRIVES + drive_id, objs, vols)
    return result(go)


def eject(drive_id, be=None):
    be = be or backend()

    def go(d, dp, objs, vols):
        if not d["ejectable"] and not d["can_power_off"]:
            raise Failed("This drive cannot be ejected.")
        for v in vols:
            unmount_volume(be, objs, v)
        (be.eject if d["ejectable"] else be.power_off)(dp)
    return with_drive(drive_id, be, go)


def power_off(drive_id, be=None):
    be = be or backend()

    def go(d, dp, objs, vols):
        if not d["can_power_off"]:
            raise Failed("This drive cannot be powered off.")
        for v in vols:
            unmount_volume(be, objs, v)
        be.power_off(dp)
    return with_drive(drive_id, be, go)


def format_volume(dev, fs, label, be=None):
    be = be or backend()
    if fs not in [f["id"] for f in available_formats()]:
        return {"ok": False, "error": "That file system is not available on this computer."}
    err = check_label(fs, label)
    if err:
        return {"ok": False, "error": err}
    d, v, objs = volume_for(be, dev)
    if not v:
        return {"ok": False, "error": "That volume is gone."}
    if uses_system(v):
        return {"ok": False, "error": "The system is using this volume. It cannot be formatted."}
    if not v["can_format"]:
        return {"ok": False, "error": "This volume cannot be formatted from here."}
    bp = block_path(objs, v["device"])
    if not bp:
        return {"ok": False, "error": "That volume is gone."}

    def go():
        unmount_volume(be, objs, v)
        be.format(bp, fs, label)
    return result(go)


# ---------------------------------------------------------------- partition management

def align_up(n, a=MIB):
    return -(-n // a) * a


def align_down(n, a=MIB):
    return n // a * a


def part_type(table, fs):
    """Partition type for a new partition: GPT type GUID or MBR id, chosen from the table and the file system."""
    basic = fs in ("ntfs", "exfat", "vfat")
    if table == "dos":
        return {"ntfs": "0x07", "exfat": "0x07", "vfat": "0x0c"}.get(fs, "0x83")
    return GPT_BASIC if basic else GPT_LINUX


def gap_limits(drive, gap):
    """(start, room) of a free gap: 1 MiB aligned, and clear of GPT's backup table at the end of the disk."""
    start = max(MIB, align_up(gap["offset"]))
    end = gap["offset"] + gap["size"]
    if drive["table"] == "gpt" and end > drive["size"] - MIB:
        end = drive["size"] - MIB
    end = align_down(end)
    return start, max(0, end - start)


def plan_create(drive, gap_offset, want=None):
    """-> (offset, size) for a new partition in the gap at `gap_offset`; `want` bytes (None = all of it) is clamped
    to the gap and rounded down to 1 MiB. Raises Failed with a plain reason."""
    gap = next((x for x in drive["partitions"] if x["kind"] == "free" and x["offset"] == gap_offset), None)
    if not gap:
        raise Failed("That free space is gone.")
    if drive["table"] not in TABLES:
        raise Failed("This drive has no partition table yet. Create a new one first.")
    if drive["table"] == "dos" and len([x for x in drive["partitions"] if x["kind"] == "partition" and not x.get("contained")]) >= 4:
        raise Failed("A DOS partition table holds at most four main partitions.")
    start, room = gap_limits(drive, gap)
    if room < MIB:
        raise Failed("That free space is too small for a partition.")
    size = room if want is None else align_down(min(int(want), room))
    size = max(size, MIB)
    if room - size <= MIB:
        size = room                       # never leave a sliver nobody can use
    return start, size


def drive_has_system(d):
    return d["is_system"] or any(uses_system(v) for v in d["partitions"] if v["kind"] == "partition")


def refuse_volume(d, v):
    """Why a volume may not be deleted or resized ('' = fine)."""
    if uses_system(v):
        return "The system is using this volume."
    if drive_has_system(d):
        return "The system is using this drive."
    if v["read_only"]:
        return "This volume is read-only."
    if v["members"] or v["target"] != v["device"]:
        return "This partition is part of something larger (RAID, LVM or a Windows dynamic disk)."
    return ""


def refuse_table(d):
    if drive_has_system(d):
        return "The system is using this drive."
    if d["size"] <= 0 or not d["device"]:
        return "No disk is available to write a table to."
    return ""


def refuse_label(v):
    if uses_system(v):
        return "The system is using this volume."
    if not v["mountable"] or not v["fs"] or v["swap"] or v["read_only"]:
        return "This volume has no file system whose name can be changed."
    return ""


def label_error(fs, label):
    if fs in [f["id"] for f in FORMATS]:
        return check_label(fs, label)
    if any(ord(c) < 32 or ord(c) == 127 for c in label):
        return "The name cannot contain control characters."
    if len(label.encode("utf-8")) > 64:
        return "That name is too long."
    return None


def resize_info(d, v, can, which=shutil.which):
    """What resizing partition `v` of drive `d` can do: {ok, why, size, min, max, grow, shrink, mode}.
    `can(fs)` -> (available, mode bits, utility), as Manager.CanResize."""
    r = {"ok": False, "why": "", "size": v["size"], "min": v["size"], "max": v["size"], "grow": False, "shrink": False, "mode": 0}
    why = refuse_volume(d, v)
    if why:
        r["why"] = why
        return r
    items = d["partitions"]
    i = next((k for k, x in enumerate(items) if x is v or (x["kind"] == "partition" and x["device"] == v["device"])), -1)
    nxt = items[i + 1] if 0 <= i < len(items) - 1 else None
    after = d["size"] if i == len(items) - 1 else v["offset"] + v["size"]
    if nxt and nxt["kind"] == "free":
        after = nxt["offset"] + nxt["size"]
    if d["table"] == "gpt" and after > d["size"] - MIB:
        after = d["size"] - MIB
    maxsize = max(v["size"], align_down(after) - v["offset"]) if d["table"] in TABLES else v["size"]
    grow_room = maxsize - v["size"] >= MIB
    if v["fs"] in ("", None):
        grow, shrink, mode = grow_room, False, 0
        if not grow_room:
            r["why"] = "There is no free space after it to grow into."
    else:
        avail, mode, util = can(v["fs"])
        tool = RESIZE_TOOLS.get(v["fs"])
        if not avail:
            r["why"] = "Resizing %s is not supported%s." % (v["fs_name"], (" (it needs " + util + ")") if util else "")
            return r
        if tool and not which(tool, path=os.environ.get("PATH", "") + ":/usr/sbin:/sbin"):
            r["why"] = "Resizing %s needs %s, which is not installed." % (v["fs_name"], tool)
            return r
        grow = grow_room and bool(mode & (OFF_GROW | ON_GROW))
        shrink = bool(mode & (OFF_SHRINK | ON_SHRINK))
        r["min"] = v["size"]
        if shrink:
            if v["used"] is None:
                shrink = False
                r["why"] = "Mount it once so its used space can be measured before it is shrunk."
            else:
                mn = align_up(v["used"] + max(64 * MIB, v["used"] // 10))
                if mn + MIB > v["size"]:
                    shrink = False
                    r["why"] = "It is nearly full, so there is nothing to give back."
                else:
                    r["min"] = max(MIB, mn)
        if not grow and not shrink and not r["why"]:
            r["why"] = "There is no free space after it to grow into."
    r.update(grow=grow, shrink=shrink, mode=mode, max=maxsize if grow else v["size"], ok=grow or shrink)
    if not shrink:
        r["min"] = v["size"]
    return r


def annotate(drives, can=None, which=shutil.which):
    """Add what each drive, volume and free gap may be used for: `table_why` / `manage` / `create`."""
    can = can or (lambda fs: (False, 0, ""))
    for d in drives:
        d["table_why"] = refuse_table(d)
        for x in d["partitions"]:
            if x["kind"] == "free":
                try:
                    off, size = plan_create(d, x["offset"])
                    x["create"] = {"ok": True, "why": "", "offset": off, "max": size}
                except Failed as e:
                    x["create"] = {"ok": False, "why": str(e), "offset": x["offset"], "max": 0}
            else:
                x["manage"] = {"delete": refuse_volume(d, x), "label": refuse_label(x), "resize": resize_info(d, x, can, which)}
    return drives


def _drive_and_objs(be, drive_id):
    drives, objs = load(be)
    d = next((x for x in drives if x["id"] == drive_id), None)
    return d, objs


def create_partition(drive_id, gap_offset, size, fs, label, be=None):
    be = be or backend()
    if fs != "none" and fs not in [f["id"] for f in available_formats()]:
        return {"ok": False, "error": "That file system is not available on this computer."}
    err = check_label(fs, label) if fs != "none" else None
    if err:
        return {"ok": False, "error": err}
    d, objs = _drive_and_objs(be, drive_id)
    if not d:
        return {"ok": False, "error": "That drive is gone."}

    def go():
        want = int(size) if str(size).strip() not in ("", "0") else None      # 0 = all of the free space
        if want is not None and want < MIB:
            raise Failed("That is too small for a partition.")
        offset, sz = plan_create(d, int(gap_offset), want)
        table = block_path(objs, d["device"])
        if not table:
            raise Failed("That drive is gone.")
        try:
            be.create_partition(table, offset, sz, part_type(d["table"], fs), "", fs, label if fs != "none" else "")
        except Failed:
            # UDisks keeps the new partition when only the formatting failed: take it out again
            left = [p for p, i in be.objects().items() if i.get(UD + ".Partition", {}).get("Table") == table
                    and abs(int(i[UD + ".Partition"].get("Offset", 0)) - offset) < MIB]
            for p in left:
                try:
                    be.delete_partition(p)
                except (Failed, Cancelled):
                    pass
            raise
        return {"offset": offset, "size": sz}
    return result(go)


def delete_partition(dev, be=None):
    be = be or backend()
    d, v, objs = volume_for(be, dev)
    if not v:
        return {"ok": False, "error": "That volume is gone."}
    why = refuse_volume(d, v)
    if why:
        return {"ok": False, "error": why + " It cannot be deleted."}
    bp = block_path(objs, v["device"])

    def go():
        unmount_volume(be, objs, v)
        be.delete_partition(bp)
    return result(go)


def resize_partition(dev, size, be=None):
    be = be or backend()
    d, v, objs = volume_for(be, dev)
    if not v:
        return {"ok": False, "error": "That volume is gone."}
    info = resize_info(d, v, be.can_resize)
    if not info["ok"]:
        return {"ok": False, "error": (info["why"] or "It cannot be resized.")}
    try:
        size = align_down(int(size))
    except (TypeError, ValueError):
        return {"ok": False, "error": "That is not a size."}
    if abs(size - v["size"]) < MIB:
        return {"ok": False, "error": "That is the size it already has."}
    if size > v["size"] and not info["grow"]:
        return {"ok": False, "error": "There is no free space after it to grow into."}
    if size > v["size"] and size > info["max"]:
        return {"ok": False, "error": "It can grow to at most %s." % bstr_size(info["max"])}
    if size < v["size"] and not info["shrink"]:
        return {"ok": False, "error": info["why"] or "It cannot be shrunk."}
    if size < v["size"] and size < info["min"]:
        return {"ok": False, "error": "It cannot shrink below %s, or its data would not fit." % bstr_size(info["min"])}
    bp, fp = block_path(objs, v["device"]), block_path(objs, v["target"])
    growing, mode = size > v["size"], info["mode"]

    def go():
        online = bool(mode & (ON_GROW if growing else ON_SHRINK))
        mounted_here = False
        if v["fs"] and not growing:
            # measure what is on it now: the used space shown may be from before it was last unmounted
            mp = v["mounts"][0] if v["mounted"] else None
            if not mp:
                mp, mounted_here = be.mount(fp), True
            use = (be.usage or default_usage)(mp)
            if use is None or size < align_up(use[1] + max(64 * MIB, use[1] // 10)):
                if mounted_here and not online:
                    be.unmount(fp)
                raise Failed("Its data would not fit in %s." % bstr_size(size))
        if not v["fs"]:
            pass
        elif online:                        # resize in place, mounted (ext4 grows this way)
            if not v["mounted"] and not mounted_here:
                be.mount(fp)
        else:                               # offline: unmounted and checked first (resize2fs insists)
            if v["mounted"] or mounted_here:
                be.unmount(fp)
            if v["fs"] in CHECK_FIRST and not be.fs_check(fp):
                raise Failed("The file system has errors. Repair it (e.g. on the PC it came from) before resizing.")
        if growing:                         # the partition first, then what lives in it
            be.resize_partition(bp, size)
            if v["fs"]:
                try:
                    be.fs_resize(fp, size)
                except Failed as e:
                    raise Failed("The partition grew, but its file system did not (your data is fine): %s" % e)
        else:                               # the file system first, then the partition
            be.fs_resize(fp, size)
            be.resize_partition(bp, size)
        return {"size": size}
    return result(go)


def bstr_size(n):
    u = ["B", "kB", "MB", "GB", "TB"]
    i = 0
    n = float(n)
    while n >= 1000 and i < 4:
        n /= 1000
        i += 1
    return ("%d %s" % (round(n), u[i])) if i == 0 or n >= 100 else ("%.1f %s" % (n, u[i]))


def new_table(drive_id, kind, be=None):
    be = be or backend()
    if kind not in TABLES:
        return {"ok": False, "error": "Choose GPT or DOS."}
    d, objs = _drive_and_objs(be, drive_id)
    if not d:
        return {"ok": False, "error": "That drive is gone."}
    why = refuse_table(d)
    if why:
        return {"ok": False, "error": why + " Its partition table cannot be replaced."}
    disk = block_path(objs, d["device"])
    vols = [v for v in d["partitions"] if v["kind"] == "partition"]

    def go():
        for v in vols:
            unmount_volume(be, objs, v)
        be.new_table(disk, kind)
    return result(go)


def set_label(dev, label, be=None):
    be = be or backend()
    d, v, objs = volume_for(be, dev)
    if not v:
        return {"ok": False, "error": "That volume is gone."}
    why = refuse_label(v)
    if why:
        return {"ok": False, "error": why}
    err = label_error(v["fs"], label)
    if err:
        return {"ok": False, "error": err}
    return result(lambda: be.set_label(block_path(objs, v["target"]), label))


# ---------------------------------------------------------------- usage scanner and its cache

def cache_dir():
    d = os.environ.get("DISKS_CACHE")
    if not d:
        rt = os.environ.get("XDG_RUNTIME_DIR")
        d = os.path.join(rt, "ultimit-disks") if rt else "/tmp/ultimit-disks-%d" % os.getuid()
    os.makedirs(d, mode=0o700, exist_ok=True)
    return d


def cache_file(root):
    return os.path.join(cache_dir(), hashlib.sha1(root.encode()).hexdigest()[:16] + ".sqlite")


SCHEMA = """
CREATE TABLE dirs(id INTEGER PRIMARY KEY, parent INTEGER, name TEXT, size INTEGER, items INTEGER, errs INTEGER,
                  fo_n INTEGER, fo_b INTEGER);
CREATE TABLE files(dir INTEGER, name TEXT, size INTEGER);
CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT);
"""
KEEP_FILES, KEEP_BIG = 200, 50    # files kept per folder; beyond the first KEEP_BIG only files of 256 KiB and up
BIG = 256 << 10


def keep_files(files):
    """files: [(size, name)] -> (kept, size-descending; count of the rest; bytes of the rest)."""
    top = heapq.nlargest(KEEP_FILES, files) if len(files) > KEEP_FILES else sorted(files, reverse=True)
    kept = [f for i, f in enumerate(top) if f[0] > 0 and (i < KEEP_BIG or f[0] >= BIG)]
    return kept, len(files) - len(kept), sum(f[0] for f in files) - sum(f[0] for f in kept)


def skip_tree(root, path):
    return path in SKIP_TREES and not (root == path or root.startswith(path + "/"))


def scan(root, write=None, interval=0.2):
    """Walk `root` (one filesystem, no symlinks followed, allocated size, hardlinks counted once) into the cache.
    Progress lines {"progress": files, "bytes": n, "path": p} go through write(); returns the final summary."""
    write = write or out
    root = os.path.abspath(root)
    try:
        rst = os.stat(root)
    except OSError as e:
        return {"ok": False, "error": "Cannot read %s: %s" % (root, e.strerror)}
    if not statmod.S_ISDIR(rst.st_mode):
        return {"ok": False, "error": "%s is not a folder." % root}
    dev = rst.st_dev
    t0 = time.monotonic()
    final = cache_file(root)
    part = final + ".part"
    if os.path.exists(part):
        os.remove(part)
    db = sqlite3.connect(part)
    db.execute("PRAGMA journal_mode=OFF")
    db.execute("PRAGMA synchronous=OFF")
    db.executescript(SCHEMA)

    # per folder, indexed by id (1 = root); a folder's id is always larger than its parent's
    names, parent = [None, root], [0, 0]
    own_size, own_items, errs, fo_n, fo_b = [0, rst.st_blocks * 512], [0, 0], [0, 0], [0, 0], [0, 0]
    seen = set()
    unreadable = []
    other_fs = nfiles = nbytes = tick = 0
    last = t0
    stack = [(1, root)]
    batch = []
    while stack:
        did, path = stack.pop()
        try:
            it = os.scandir(path)
        except OSError:
            errs[did] += 1
            if len(unreadable) < 200:
                unreadable.append(path)
            continue
        files = []
        with it:
            while True:
                try:
                    e = next(it)
                except StopIteration:
                    break
                except OSError:
                    errs[did] += 1
                    break
                try:
                    st = e.stat(follow_symlinks=False)
                except OSError:
                    errs[did] += 1
                    continue
                if statmod.S_ISDIR(st.st_mode):
                    if st.st_dev != dev:
                        other_fs += 1
                        continue
                    sub = path.rstrip("/") + "/" + e.name
                    if skip_tree(root, sub):
                        continue
                    names.append(e.name); parent.append(did)
                    own_size.append(st.st_blocks * 512); own_items.append(0); errs.append(0); fo_n.append(0); fo_b.append(0)
                    stack.append((len(names) - 1, sub))
                    continue
                size = st.st_blocks * 512
                if st.st_nlink > 1:
                    key = (st.st_dev, st.st_ino)
                    if key in seen:
                        size = 0
                    else:
                        seen.add(key)
                files.append((size, e.name))
                nfiles += 1
                nbytes += size
                tick += 1
                if tick & 255 == 0:
                    now = time.monotonic()
                    if now - last >= interval:
                        last = now
                        write({"progress": nfiles, "bytes": nbytes, "path": path})
        own_items[did] = len(files)
        own_size[did] += sum(f[0] for f in files)
        kept, fo_n[did], fo_b[did] = keep_files(files)
        batch.extend((did, n, s) for s, n in kept)
        if len(batch) > 50000:
            db.executemany("INSERT INTO files VALUES(?,?,?)", batch)
            batch = []
    if batch:
        db.executemany("INSERT INTO files VALUES(?,?,?)", batch)
    for i in range(len(names) - 1, 1, -1):     # sizes, counts and errors up the tree
        p = parent[i]
        own_size[p] += own_size[i]
        own_items[p] += own_items[i]
        errs[p] += errs[i]
    db.executemany("INSERT INTO dirs VALUES(?,?,?,?,?,?,?,?)",
                   ((i, parent[i], names[i], own_size[i], own_items[i], errs[i], fo_n[i], fo_b[i]) for i in range(1, len(names))))
    db.execute("CREATE INDEX dirs_parent ON dirs(parent, name)")
    db.execute("CREATE INDEX files_dir ON files(dir, size)")
    db.execute("CREATE INDEX files_size ON files(size)")
    secs = round(time.monotonic() - t0, 2)
    meta = {"root": root, "when": str(int(time.time())), "other_fs": str(other_fs), "seconds": str(secs),
            "unreadable": json.dumps(unreadable)}
    db.executemany("INSERT INTO meta VALUES(?,?)", meta.items())
    db.commit()
    db.close()
    os.replace(part, final)
    return {"ok": True, "done": True, "root": root, "size": own_size[1], "items": own_items[1], "dirs": len(names) - 1,
            "errors": errs[1], "unreadable": unreadable[:20], "other_fs": other_fs, "seconds": secs}


def caches_for(path):
    """Cache databases that cover `path`, newest scan first: [(root, when, file)]."""
    path = os.path.abspath(path)
    res = []
    d = cache_dir()
    for fn in os.listdir(d):
        if not fn.endswith(".sqlite"):
            continue
        try:
            db = sqlite3.connect(os.path.join(d, fn))
            m = dict(db.execute("SELECT k, v FROM meta").fetchall())
            db.close()
        except sqlite3.Error:
            continue
        r = m.get("root", "")
        if r and (path == r or path.startswith(r.rstrip("/") + "/")):
            res.append((r, int(m.get("when", 0)), os.path.join(d, fn)))
    res.sort(key=lambda x: -x[1])
    return res


def resolve(db, root, path):
    """-> list of folder ids from the root down to `path`, or None when it is not a scanned folder."""
    rel = os.path.relpath(path, root)
    ids = [1]
    if rel == ".":
        return ids
    for part in rel.split(os.sep):
        r = db.execute("SELECT id FROM dirs WHERE parent=? AND name=?", (ids[-1], part)).fetchone()
        if not r:
            return None
        ids.append(r[0])
    return ids


NOT_SCANNED = {"ok": False, "error": "This folder has not been scanned yet.", "notscanned": True}


def children(path, limit=200):
    path = os.path.abspath(path)
    for root, when, fn in caches_for(path):
        db = sqlite3.connect(fn)
        ids = resolve(db, root, path)
        if ids is None:
            db.close()
            continue
        did = ids[-1]
        size, items, errs_, fo_n, fo_b = db.execute("SELECT size, items, errs, fo_n, fo_b FROM dirs WHERE id=?", (did,)).fetchone()
        entries = [{"name": n, "kind": "dir", "size": s, "items": i, "errors": e}
                   for n, s, i, e in db.execute("SELECT name, size, items, errs FROM dirs WHERE parent=?", (did,))]
        entries += [{"name": n, "kind": "file", "size": s, "items": 1, "errors": 0}
                    for n, s in db.execute("SELECT name, size FROM files WHERE dir=?", (did,))]
        meta = dict(db.execute("SELECT k, v FROM meta").fetchall())
        db.close()
        entries.sort(key=lambda e: (-e["size"], e["name"]))
        rolled_n, rolled_b, rolled_items = fo_n, fo_b, fo_n
        if len(entries) > limit:
            rest = entries[limit:]
            entries = entries[:limit]
            rolled_n += len(rest)
            rolled_b += sum(e["size"] for e in rest)
            rolled_items += sum(e["items"] for e in rest)
        if rolled_n > 0:
            entries.append({"name": "%d smaller item%s" % (rolled_n, "" if rolled_n == 1 else "s"), "kind": "other",
                            "size": rolled_b, "items": rolled_items, "errors": 0})
        for e in entries:
            e["pct"] = round(100.0 * e["size"] / size, 1) if size else 0.0
        return {"ok": True, "path": path, "root": root, "size": size, "items": items, "errors": errs_,
                "scanned": when, "other_fs": int(meta.get("other_fs", 0)),
                "unreadable": json.loads(meta.get("unreadable", "[]"))[:50], "entries": entries}
    return dict(NOT_SCANNED)


def dir_path(db, root, did):
    parts = []
    while did > 1:
        pid, name = db.execute("SELECT parent, name FROM dirs WHERE id=?", (did,)).fetchone()
        parts.append(name)
        did = pid
    return os.path.join(root, *reversed(parts))


def largest(root, n=100):
    root = os.path.abspath(root)
    for r, when, fn in caches_for(root):
        db = sqlite3.connect(fn)
        ids = resolve(db, r, root)
        if ids is None:
            db.close()
            continue
        if ids[-1] == 1:
            rows = db.execute("SELECT dir, name, size FROM files ORDER BY size DESC LIMIT ?", (n,)).fetchall()
        else:   # a sub-folder: the files of its subtree only
            rows = db.execute("""WITH RECURSIVE sub(id) AS (SELECT ? UNION ALL SELECT d.id FROM dirs d JOIN sub ON d.parent=sub.id)
                                 SELECT dir, name, size FROM files WHERE dir IN sub ORDER BY size DESC LIMIT ?""",
                              (ids[-1], n)).fetchall()
        dirs = {}
        files = []
        for did, name, size in rows:
            if did not in dirs:
                dirs[did] = dir_path(db, r, did)
            files.append({"path": os.path.join(dirs[did], name), "name": name, "dir": dirs[did], "size": size})
        total = db.execute("SELECT size FROM dirs WHERE id=?", (ids[-1],)).fetchone()[0]
        db.close()
        return {"ok": True, "root": root, "size": total, "files": files}
    return dict(NOT_SCANNED)


def trash(path, runner=None):
    """Move an item of a scanned tree to the trash and take it out of the cache. Never the scanned root itself."""
    path = os.path.abspath(path)
    covering = caches_for(path)
    if any(r == path for r, _, _ in covering):
        return {"ok": False, "error": "The scanned folder itself cannot be moved to the trash from here."}
    if not covering:
        return {"ok": False, "error": "That is not inside a scanned folder."}
    root = covering[0][0]
    parent_dir = os.path.dirname(path)
    rel_parent = os.path.relpath(parent_dir, root)
    expected = os.path.realpath(root) if rel_parent == "." else os.path.join(os.path.realpath(root), rel_parent)
    if os.path.realpath(parent_dir) != expected:    # a symlink in the way: not what the scan saw
        return {"ok": False, "error": "That is not inside the scanned folder."}
    try:
        st = os.lstat(path)
    except OSError:
        return {"ok": False, "error": "That item is already gone."}
    isdir = statmod.S_ISDIR(st.st_mode)
    if isdir and st.st_dev != os.stat(root).st_dev:
        return {"ok": False, "error": "That is another drive's folder."}
    if not fake():     # fake mode only updates the cache; no real file is touched
        import subprocess
        try:
            p = (runner or subprocess.run)(["gio", "trash", "--", path], capture_output=True, text=True, timeout=300)
        except FileNotFoundError:
            return {"ok": False, "error": "gio is not installed."}
        except Exception as e:
            return {"ok": False, "error": str(e)}
        if p.returncode != 0:
            msg = (p.stderr or "").strip().replace("gio: ", "")
            return {"ok": False, "error": msg or "Could not move it to the trash."}
    return {"ok": True, "freed": update_caches(path, st, isdir)}


def update_caches(path, st, isdir):
    freed = 0
    for root, when, fn in caches_for(path):
        if path == root:
            continue
        db = sqlite3.connect(fn)
        pids = resolve(db, root, os.path.dirname(path))
        if pids is None:
            db.close()
            continue
        name = os.path.basename(path)
        if isdir:
            r = db.execute("SELECT id, size, items, errs FROM dirs WHERE parent=? AND name=?", (pids[-1], name)).fetchone()
            if not r:
                db.close()
                continue
            did, size, items, errs_ = r
            sub = "WITH RECURSIVE sub(id) AS (SELECT ? UNION ALL SELECT d.id FROM dirs d JOIN sub ON d.parent=sub.id) "
            db.execute(sub + "DELETE FROM files WHERE dir IN sub", (did,))
            db.execute(sub + "DELETE FROM dirs WHERE id IN sub", (did,))
        else:
            r = db.execute("SELECT size FROM files WHERE dir=? AND name=?", (pids[-1], name)).fetchone()
            size, items, errs_ = (r[0] if r else st.st_blocks * 512), 1, 0
            if r:
                db.execute("DELETE FROM files WHERE dir=? AND name=?", (pids[-1], name))
            else:
                db.execute("UPDATE dirs SET fo_n=MAX(fo_n-1,0), fo_b=MAX(fo_b-?,0) WHERE id=?", (size, pids[-1]))
        db.execute("UPDATE dirs SET size=MAX(size-?,0), items=MAX(items-?,0), errs=MAX(errs-?,0) WHERE id IN (%s)"
                   % ",".join("?" * len(pids)), (size, items, errs_, *pids))
        db.commit()
        db.close()
        freed = size
    return freed


def peek(path, limit=12):
    """The first few top-level names of a mounted volume, for the format warning: [{name, dir}], total count."""
    try:
        with os.scandir(path) as it:
            ents = sorted(it, key=lambda e: e.name.lower())
    except OSError as e:
        return {"ok": False, "error": e.strerror or "Cannot read it."}
    ents = [e for e in ents if not e.name.startswith(".")] or ents
    return {"ok": True, "total": len(ents), "names": [{"name": e.name, "dir": e.is_dir(follow_symlinks=False)} for e in ents[:limit]]}


# ---------------------------------------------------------------- CLI

def main(argv):
    cmd, args = (argv[0], argv[1:]) if argv else ("", [])
    try:
        if cmd == "state":
            out(state())
        elif cmd == "health" and len(args) == 1:
            out(health(args[0]))
        elif cmd == "mount" and len(args) == 1:
            out(mount(args[0]))
        elif cmd == "unmount" and len(args) == 1:
            out(unmount(args[0]))
        elif cmd == "eject" and len(args) == 1:
            out(eject(args[0]))
        elif cmd == "power-off" and len(args) == 1:
            out(power_off(args[0]))
        elif cmd == "format" and len(args) == 3:
            out(format_volume(*args))
        elif cmd == "create-partition" and len(args) == 5:
            out(create_partition(*args))
        elif cmd == "delete-partition" and len(args) == 1:
            out(delete_partition(args[0]))
        elif cmd == "resize-partition" and len(args) == 2:
            out(resize_partition(*args))
        elif cmd == "new-table" and len(args) == 2:
            out(new_table(*args))
        elif cmd == "set-label" and len(args) == 2:
            out(set_label(*args))
        elif cmd == "scan" and len(args) == 1:
            out(scan(args[0]))
        elif cmd == "children" and len(args) == 1:
            out(children(args[0]))
        elif cmd == "largest" and len(args) in (1, 2):
            out(largest(args[0], int(args[1]) if len(args) == 2 else 100))
        elif cmd == "peek" and len(args) == 1:
            out(peek(args[0]))
        elif cmd == "trash" and len(args) == 1:
            out(trash(args[0]))
        else:
            out({"ok": False, "error": "usage: disks.py state|health|mount|unmount|eject|power-off|format|create-partition|delete-partition|resize-partition|new-table|set-label|scan|children|largest|peek|trash"})
            return 2
    except Exception as e:   # never leave the UI without JSON
        out({"ok": False, "error": "%s: %s" % (type(e).__name__, e)})
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
