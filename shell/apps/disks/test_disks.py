#!/usr/bin/env python3
"""Unit tests for disks.py. Run: python3 -m unittest apps/disks/test_disks.py   (from shell/)
Nothing real is touched: UDisks2 is replaced by a recording backend, scans run on temp trees."""
import importlib.machinery, importlib.util, json, os, stat, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TMP = tempfile.mkdtemp(prefix="disks-test-")
os.environ["DISKS_CACHE"] = TMP + "/cache"
os.environ.pop("DISKS_FAKE", None)


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, path)
    spec = importlib.util.spec_from_loader(name, loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    return m


dk = load("disks", os.path.join(HERE, "disks.py"))
REAL = json.load(open(os.path.join(HERE, "fixtures", "real-objects.json")))
FAKE = json.load(open(os.path.join(HERE, "fixtures", "fake-objects.json")))
SYS = {"sdc": {"holders": []}, "sdc3": {"holders": []}, "dm-0": {}}
SYS_REAL = {"sdc": {"holders": ["dm-0"], "bus": "sata", "rotational": True}, "sda": {"bus": "sata", "rotational": False},
            "nvme0n1": {"bus": "nvme", "rotational": False}}
NOUSE = lambda mp: (1000, 400, 600)


def drives(objs=REAL, sysinfo=SYS_REAL):
    return dk.convert(objs, sysinfo, NOUSE)


class Recorder:
    """A backend that records what would have been done."""
    def __init__(self, objs, sysinfo=None):
        self.objs, self.calls, self.si = objs, [], sysinfo or {}
        self.usage = NOUSE
    def objects(self): return self.objs
    def sysinfo(self, objs): return self.si
    def mount(self, b): self.calls.append(("mount", b)); return "/run/media/x"
    def unmount(self, b): self.calls.append(("unmount", b))
    def eject(self, d): self.calls.append(("eject", d))
    def power_off(self, d): self.calls.append(("power_off", d))
    def format(self, b, fs, label): self.calls.append(("format", b, fs, label))
    def create_partition(self, *a): self.calls.append(("create",) + a)
    def delete_partition(self, b): self.calls.append(("delete", b))
    def resize_partition(self, b, n): self.calls.append(("resize_part", b, n))
    def fs_resize(self, b, n): self.calls.append(("resize_fs", b, n))
    def fs_check(self, b): self.calls.append(("check", b)); return getattr(self, "check_ok", True)
    def set_label(self, b, l): self.calls.append(("label", b, l))
    def new_table(self, d, k): self.calls.append(("table", d, k))
    def can_resize(self, fs): return dk.FAKE_CAN_RESIZE.get(fs, (False, 0, ""))


class Jobs(unittest.TestCase):
    def test_convert_jobs(self):
        UD = dk.UD
        objs = {"/b/sdc1": {UD + ".Block": {"Device": list(b"/dev/sdc1\0")}},
                "/j/1": {UD + ".Job": {"Operation": "format-mkfs", "Objects": ["/b/sdc1"], "Progress": 0.4,
                                       "ProgressValid": True, "ExpectedEndTime": 30_000_000}},
                "/j/2": {UD + ".Job": {"Operation": "something-new", "Objects": [], "ProgressValid": False}}}
        j = dk.convert_jobs(objs, now_us=10_000_000)
        self.assertEqual(j[0], {"op": "format-mkfs", "text": "Creating the file system", "devices": ["/dev/sdc1"],
                                "progress": 0.4, "rate": 0, "left": 20})
        self.assertEqual((j[1]["text"], j[1]["progress"], j[1]["left"]), ("Something new", None, None))


class Convert(unittest.TestCase):
    def test_four_drives(self):
        ds = drives()
        self.assertEqual(sorted(d["name"] for d in ds), ["Acer SSD FA100 2TB", "JAJS600M2TB", "ST8000DM004-2CX1", "WDC WD2000FYYZ-0"])
        by = {d["device"]: d for d in ds}
        self.assertEqual(by["/dev/nvme0n1"]["kind"], "nvme")
        self.assertEqual(by["/dev/sda"]["kind"], "ssd")
        self.assertEqual(by["/dev/sdb"]["kind"], "hdd")  # RotationRate -1 without sysfs
        self.assertTrue(by["/dev/nvme0n1"]["smart"])

    def test_partitions_in_disk_order_with_gap(self):
        d = next(x for x in drives() if x["device"] == "/dev/nvme0n1")
        offs = [p["offset"] for p in d["partitions"]]
        self.assertEqual(offs, sorted(offs))
        self.assertEqual([p["number"] for p in d["partitions"] if p["kind"] == "partition"], [1, 2, 3, 6, 5, 4])
        # nothing overlaps and the sizes add up to the disk (apart from small alignment gaps)
        tot = sum(p["size"] for p in d["partitions"])
        self.assertLessEqual(tot, d["size"])
        self.assertGreater(tot, d["size"] - (8 << 20))

    def test_free_gap_synthesised(self):
        d = next(x for x in drives(FAKE["objects"], {}) if x["id"] == "Fake_NVMe_1TB")
        free = [p for p in d["partitions"] if p["kind"] == "free"]
        self.assertEqual(len(free), 1)
        self.assertEqual(free[0]["offset"] + free[0]["size"], d["size"])
        d2 = next(x for x in drives(FAKE["objects"], {}) if x["id"] == "Fake_HDD_8TB")
        self.assertEqual(d2["partitions"][-1]["kind"], "free")

    def test_small_gaps_ignored(self):
        d = next(x for x in drives() if x["device"] == "/dev/sda")
        self.assertEqual([p["kind"] for p in d["partitions"]], ["partition"])

    def test_system_detection(self):
        d = next(x for x in drives() if x["device"] == "/dev/nvme0n1")
        sysp = {p["device"] for p in d["partitions"] if p["kind"] == "partition" and p["is_system"]}
        self.assertEqual(sysp, {"/dev/nvme0n1p1", "/dev/nvme0n1p5"})   # /boot/efi and /
        self.assertTrue(d["is_system"])
        ntfs = next(p for p in d["partitions"] if p.get("device") == "/dev/nvme0n1p3")
        self.assertFalse(ntfs["is_system"])     # mounted under /run/media: a data volume
        self.assertFalse(next(x for x in drives() if x["device"] == "/dev/sdb")["is_system"])

    def test_system_mount_paths(self):
        for m in ("/", "/home", "/boot", "/boot/efi", "/usr", "/var/lib/x"):
            self.assertTrue(dk.system_mount(m), m)
        for m in ("/run/media/u/x", "/mnt/disk", "/home/u/Games", "/media/u"):
            self.assertFalse(dk.system_mount(m), m)

    def test_swap_is_system(self):
        d = next(x for x in drives(FAKE["objects"], {}) if x["id"] == "Fake_NVMe_1TB")
        sw = next(p for p in d["partitions"] if p.get("swap"))
        self.assertTrue(sw["is_system"])

    def test_dynamic_disk_volume_attached_to_data_partition(self):
        d = next(x for x in drives() if x["device"] == "/dev/sdc")
        p = next(p for p in d["partitions"] if p.get("number") == 3)
        self.assertEqual(p["target"], "/dev/dm-0")
        self.assertTrue(p["mounted"])
        self.assertEqual(p["label"], "Windows Data")
        self.assertFalse(p["can_format"])       # formatting would break the Windows volume layout

    def test_usage_only_when_mounted(self):
        for d in drives():
            for p in d["partitions"]:
                if p["kind"] == "partition":
                    self.assertEqual(p["used"] is not None, p["mounted"])

    def test_byte_arrays(self):
        self.assertEqual(dk.bstr([47, 100, 101, 118, 0]), "/dev")
        self.assertEqual(dk.bstr(b"/x\0"), "/x")
        self.assertEqual(dk.bstr("/y"), "/y")

    def test_connection_from_sysfs(self):
        objs = json.loads(json.dumps(FAKE["objects"]))
        d = next(x for x in drives(objs, {}) if x["id"] == "Fake_USB_64GB")
        self.assertEqual((d["bus"], d["kind"], d["removable"], d["ejectable"]), ("usb", "usb", True, True))

    def test_unpartitioned_disk_is_one_volume(self):
        objs = {"/org/freedesktop/UDisks2/drives/D": {dk.UD + ".Drive": {"Size": 1 << 30, "Model": "Stick", "ConnectionBus": "usb"}},
                "/org/freedesktop/UDisks2/block_devices/sdz": {dk.UD + ".Block": {
                    "Device": "/dev/sdz", "Drive": "/org/freedesktop/UDisks2/drives/D", "Size": 1 << 30, "IdType": "vfat", "IdLabel": "X"},
                    dk.UD + ".Filesystem": {"MountPoints": []}}}
        d = dk.convert(objs, {}, NOUSE)[0]
        self.assertEqual(d["partitions"][0]["device"], "/dev/sdz")
        self.assertTrue(d["partitions"][0]["can_format"])


class Formats(unittest.TestCase):
    def test_label_rules(self):
        self.assertIsNone(dk.check_label("ext4", "Data"))
        self.assertIsNone(dk.check_label("ext4", ""))
        self.assertIsNotNone(dk.check_label("ext4", "x" * 17))
        self.assertIsNone(dk.check_label("exfat", "x" * 15))
        self.assertIsNotNone(dk.check_label("exfat", "x" * 16))
        self.assertIsNotNone(dk.check_label("vfat", "TWELVECHARS!"))
        self.assertIsNotNone(dk.check_label("vfat", "A:B"))
        self.assertIsNone(dk.check_label("ntfs", "My Games"))
        self.assertIsNotNone(dk.check_label("ntfs", "a\nb"))
        self.assertIsNotNone(dk.check_label("zfs", ""))

    def test_available_formats_follow_tools(self):
        f = dk.available_formats(lambda t, path=None: "/x/" + t if t in ("mkfs.ext4", "mkfs.vfat") else None)
        self.assertEqual([x["id"] for x in f], ["ext4", "vfat"])


class Actions(unittest.TestCase):
    def setUp(self):
        self._orig = dk.available_formats
        dk.available_formats = lambda which=None: [{"id": i} for i in ("ext4", "exfat", "ntfs", "vfat")]

    def tearDown(self):
        dk.available_formats = self._orig

    def be(self):
        return Recorder(json.loads(json.dumps(REAL)), SYS_REAL)

    def test_format_refuses_system(self):
        for dev in ("/dev/nvme0n1p5", "/dev/nvme0n1p1"):
            be = self.be()
            r = dk.format_volume(dev, "ext4", "x", be)
            self.assertFalse(r["ok"])
            self.assertEqual(be.calls, [])

    def test_format_refuses_bad_input(self):
        be = self.be()
        self.assertFalse(dk.format_volume("/dev/sdb1", "zfs", "", be)["ok"])
        self.assertFalse(dk.format_volume("/dev/sdb1", "vfat", "A" * 12, be)["ok"])
        self.assertFalse(dk.format_volume("/dev/nope", "ext4", "", be)["ok"])
        self.assertFalse(dk.format_volume("/dev/sdb", "ext4", "", be)["ok"])      # whole disk with a table
        self.assertFalse(dk.format_volume("/dev/sdc3", "ntfs", "", be)["ok"])     # holds a dynamic-disk volume
        self.assertFalse(dk.format_volume("../etc", "ext4", "", be)["ok"])
        self.assertEqual(be.calls, [])

    def test_format_unmounts_first(self):
        be = self.be()
        r = dk.format_volume("/dev/sdb1", "ext4", "Stuff", be)
        self.assertTrue(r["ok"], r)
        self.assertEqual([c[0] for c in be.calls], ["unmount", "format"])
        self.assertEqual(be.calls[1][1:], ("/org/freedesktop/UDisks2/block_devices/sdb1", "ext4", "Stuff"))

    def test_unmount_refuses_system(self):
        be = self.be()
        self.assertFalse(dk.unmount("/dev/nvme0n1p5", be)["ok"])
        self.assertTrue(dk.unmount("/dev/sdb1", be)["ok"])
        self.assertEqual(be.calls, [("unmount", "/org/freedesktop/UDisks2/block_devices/sdb1")])

    def test_mount_unmounted_volume(self):
        be = self.be()
        r = dk.mount("/dev/nvme0n1p4", be)
        self.assertEqual(r["mountpoint"], "/run/media/x")
        self.assertFalse(dk.mount("/dev/nvme0n1p2", be)["ok"])    # reserved partition: nothing to mount

    def test_power_off_refuses_system_drive(self):
        be = self.be()
        self.assertFalse(dk.power_off("Acer_SSD_FA100_2TB", be)["ok"])
        self.assertEqual(be.calls, [])

    def test_eject_usb_unmounts_then_ejects(self):
        be = Recorder(json.loads(json.dumps(FAKE["objects"])))
        be.usage = lambda mp: (1, 1, 0)
        o = be.objs["/org/freedesktop/UDisks2/block_devices/sdc1"][dk.UD + ".Filesystem"]
        o["MountPoints"] = ["/run/media/u/STICK"]
        r = dk.eject("Fake_USB_64GB", be)
        self.assertTrue(r["ok"], r)
        self.assertEqual([c[0] for c in be.calls], ["unmount", "eject"])

    def test_cancelled_maps(self):
        be = self.be()
        def boom(*a): raise dk.Cancelled()
        be.unmount = boom
        r = dk.unmount("/dev/sdb1", be)
        self.assertEqual(r, {"ok": False, "cancelled": True})


MB = 1000 * 1000
GB = 1000 * MB
MIB = 1 << 20


def fobjs():
    """The fake drives with the two data volumes mounted, so their used space is known."""
    o = json.loads(json.dumps(FAKE["objects"]))
    for dev in ("sda1", "sdb2"):
        o["/org/freedesktop/UDisks2/block_devices/" + dev]["org.freedesktop.UDisks2.Filesystem"]["MountPoints"] = ["/run/media/x/" + dev]
    return o


def fdrives(usage=lambda mp: (10 ** 12, 4 * 10 ** 11, 6 * 10 ** 11)):
    ds = dk.convert(fobjs(), {}, usage)
    return {d["id"]: d for d in ds}


class Manage(unittest.TestCase):
    """Create / delete / resize / new table / label: the planning maths and the refusals."""
    def setUp(self):
        self._orig = dk.available_formats
        dk.available_formats = lambda which=None: [{"id": i} for i in ("ext4", "exfat", "ntfs", "vfat")]
        self.which = lambda t, path=None: "/usr/sbin/" + t

    def tearDown(self):
        dk.available_formats = self._orig

    def be(self):
        be = Recorder(fobjs(), {})
        be.usage = lambda mp: (10 ** 12, 4 * 10 ** 11, 6 * 10 ** 11)
        return be

    def gap(self, d):
        return next(x for x in d["partitions"] if x["kind"] == "free")

    def test_type_choice(self):
        self.assertEqual(dk.part_type("gpt", "ext4"), dk.GPT_LINUX)
        self.assertEqual(dk.part_type("gpt", "none"), dk.GPT_LINUX)
        for fs in ("ntfs", "exfat", "vfat"):
            self.assertEqual(dk.part_type("gpt", fs), dk.GPT_BASIC)
        self.assertEqual(dk.part_type("dos", "ext4"), "0x83")
        self.assertEqual(dk.part_type("dos", "ntfs"), "0x07")
        self.assertEqual(dk.part_type("dos", "exfat"), "0x07")
        self.assertEqual(dk.part_type("dos", "vfat"), "0x0c")

    def test_alignment_and_clamp(self):
        d = fdrives()["Fake_HDD_8TB"]
        g = self.gap(d)
        off, size = dk.plan_create(d, g["offset"], 100 * GB)
        self.assertEqual(off % MIB, 0)
        self.assertEqual(size % MIB, 0)
        self.assertLessEqual(size, 100 * GB)
        self.assertGreater(size, 100 * GB - MIB)
        off2, whole = dk.plan_create(d, g["offset"])            # default: all of the gap
        self.assertEqual(off2, off)
        self.assertEqual((off + whole) % MIB, 0)
        self.assertLessEqual(off + whole, d["size"] - MIB)       # GPT backup table is left alone
        self.assertEqual(dk.plan_create(d, g["offset"], 10 ** 15)[1], whole)   # too big: clamped
        self.assertEqual(dk.plan_create(d, g["offset"], 5)[1], MIB)            # too small: one MiB
        near = dk.plan_create(d, g["offset"], whole - 100)[1]                   # no unusable sliver left over
        self.assertEqual(near, whole)

    def test_first_gap_starts_at_one_mib(self):
        d = fdrives()["Fake_USB_64GB"]
        d["partitions"] = [{"kind": "free", "offset": 0, "size": d["size"]}]
        d["table"] = "dos"
        self.assertEqual(dk.plan_create(d, 0)[0], MIB)

    def test_create_refusals(self):
        d = fdrives()["Fake_HDD_8TB"]
        g = self.gap(d)
        with self.assertRaises(dk.Failed):
            dk.plan_create(d, g["offset"] + 4096)               # not a gap
        d["table"] = ""
        with self.assertRaises(dk.Failed):
            dk.plan_create(d, g["offset"])
        u = fdrives()["Fake_USB_64GB"]
        u["partitions"] = [{"kind": "partition", "contained": False}] * 4 + [{"kind": "free", "offset": 10 ** 9, "size": GB}]
        with self.assertRaises(dk.Failed):
            dk.plan_create(u, 10 ** 9)

    def test_create_calls_backend(self):
        be = self.be()
        g = self.gap(fdrives()["Fake_HDD_8TB"])
        r = dk.create_partition("Fake_HDD_8TB", g["offset"], 100 * GB, "ntfs", "Stuff", be)
        self.assertTrue(r["ok"], r)
        c = be.calls[0]
        self.assertEqual(c[0], "create")
        self.assertEqual(c[1], "/org/freedesktop/UDisks2/block_devices/sdb")
        self.assertEqual(c[4], dk.GPT_BASIC)
        self.assertEqual((c[2] % MIB, c[3] % MIB), (0, 0))
        self.assertEqual((c[6], c[7]), ("ntfs", "Stuff"))
        self.assertFalse(dk.create_partition("Fake_HDD_8TB", g["offset"], GB, "zfs", "", self.be())["ok"])
        self.assertFalse(dk.create_partition("Fake_HDD_8TB", g["offset"], GB, "vfat", "x" * 12, self.be())["ok"])

    def test_create_none_has_no_filesystem(self):
        be = self.be()
        g = self.gap(fdrives()["Fake_HDD_8TB"])
        self.assertTrue(dk.create_partition("Fake_HDD_8TB", g["offset"], GB, "none", "ignored", be)["ok"])
        self.assertEqual(be.calls[0][6:], ("none", ""))

    def test_system_drive_refusals(self):
        be = self.be()
        for dev in ("/dev/nvme0n1p1", "/dev/nvme0n1p3", "/dev/nvme0n1p4"):     # system, and others on the system drive
            self.assertFalse(dk.delete_partition(dev, be)["ok"], dev)
            self.assertFalse(dk.resize_partition(dev, 10 * GB, be)["ok"], dev)
            self.assertFalse(dk.set_label(dev, "x", be)["ok"], dev)
        self.assertFalse(dk.new_table("Fake_NVMe_1TB", "gpt", be)["ok"])
        self.assertEqual(be.calls, [])

    def test_delete_and_table_allowed_elsewhere(self):
        be = self.be()
        self.assertTrue(dk.delete_partition("/dev/sdb2", be)["ok"])
        self.assertEqual(be.calls[-1], ("delete", "/org/freedesktop/UDisks2/block_devices/sdb2"))
        self.assertTrue(dk.new_table("Fake_USB_64GB", "dos", be)["ok"])
        self.assertEqual(be.calls[-1], ("table", "/org/freedesktop/UDisks2/block_devices/sdc", "dos"))
        self.assertFalse(dk.new_table("Fake_USB_64GB", "ext4", be)["ok"])
        self.assertFalse(dk.delete_partition("/dev/nope", be)["ok"])

    def test_delete_unmounts_first(self):
        be = self.be()
        dk.mount("/dev/sdb2", be)
        be.objs["/org/freedesktop/UDisks2/block_devices/sdb2"]["org.freedesktop.UDisks2.Filesystem"]["MountPoints"] = ["/run/media/x"]
        self.assertTrue(dk.delete_partition("/dev/sdb2", be)["ok"])
        kinds = [c[0] for c in be.calls]
        self.assertLess(kinds.index("unmount"), kinds.index("delete"))

    def test_label(self):
        be = self.be()
        self.assertTrue(dk.set_label("/dev/sdc1", "NEW", be)["ok"])
        self.assertEqual(be.calls[-1], ("label", "/org/freedesktop/UDisks2/block_devices/sdc1", "NEW"))
        self.assertFalse(dk.set_label("/dev/sdc1", "A" * 12, be)["ok"])        # FAT32: 11 characters
        self.assertFalse(dk.set_label("/dev/sdc1", "a\nb", be)["ok"])

    def test_resize_info(self):
        ds = fdrives()
        can = lambda fs: dk.FAKE_CAN_RESIZE.get(fs, (False, 0, ""))
        d = ds["Fake_HDD_8TB"]
        grow = dk.resize_info(d, d["partitions"][1], can, self.which)       # ext4 with a gap after it
        self.assertTrue(grow["grow"])
        self.assertTrue(grow["shrink"])
        self.assertEqual((d["partitions"][1]["offset"] + grow["max"]) % MIB, 0)
        used = 4 * 10 ** 11
        self.assertGreaterEqual(grow["min"], used + 64 * MIB)               # used space plus a margin
        self.assertLess(grow["min"], d["partitions"][1]["size"])
        last = ds["Fake_SATA_SSD_2TB"]
        r = dk.resize_info(last, last["partitions"][0], can, self.which)    # NTFS, nothing after it
        self.assertFalse(r["grow"])
        self.assertTrue(r["shrink"])
        self.assertEqual(r["max"], last["partitions"][0]["size"])
        fat = ds["Fake_USB_64GB"]
        r = dk.resize_info(fat, fat["partitions"][0], can, self.which)      # FAT32: not supported
        self.assertFalse(r["ok"])
        self.assertIn("vfat-resize", r["why"])

    def test_resize_needs_ntfsresize(self):
        ds = fdrives()
        d = ds["Fake_SATA_SSD_2TB"]
        r = dk.resize_info(d, d["partitions"][0], lambda fs: (True, 6, ""), lambda t, path=None: None)
        self.assertFalse(r["ok"])
        self.assertIn("ntfsresize", r["why"])

    def test_resize_unknown_usage_cannot_shrink(self):
        d = fdrives(lambda mp: None)["Fake_HDD_8TB"]
        r = dk.resize_info(d, d["partitions"][1], lambda fs: (True, 22, ""), self.which)
        self.assertTrue(r["grow"])
        self.assertFalse(r["shrink"])

    def test_resize_order(self):
        be = self.be()
        cur = fdrives()["Fake_HDD_8TB"]["partitions"][1]["size"]
        self.assertTrue(dk.resize_partition("/dev/sdb2", cur + 50 * GB, be)["ok"])
        self.assertEqual([c[0] for c in be.calls if c[0] in ("resize_part", "resize_fs")], ["resize_part", "resize_fs"])      # grow: partition, then fs
        be = self.be()
        self.assertTrue(dk.resize_partition("/dev/sdb2", cur - 50 * GB, be)["ok"])
        self.assertEqual([c[0] for c in be.calls if c[0] in ("resize_part", "resize_fs")], ["resize_fs", "resize_part"])      # shrink: fs, then partition
        self.assertEqual(be.calls[-1][2], be.calls[-2][2])

    def test_ext4_grows_mounted_and_shrinks_checked(self):
        # ext4 (mode 22): grows online, so it stays mounted; shrinks offline, so unmounted and e2fsck'd first
        be = self.be()
        cur = fdrives()["Fake_HDD_8TB"]["partitions"][1]["size"]
        self.assertTrue(dk.resize_partition("/dev/sdb2", cur + 50 * GB, be)["ok"])
        self.assertNotIn("unmount", [c[0] for c in be.calls])
        be = self.be()
        self.assertTrue(dk.resize_partition("/dev/sdb2", cur - 50 * GB, be)["ok"])
        ops = [c[0] for c in be.calls]
        self.assertLess(ops.index("unmount"), ops.index("check"))
        self.assertLess(ops.index("check"), ops.index("resize_fs"))
        be = self.be()
        be.check_ok = False
        self.assertFalse(dk.resize_partition("/dev/sdb2", cur - 50 * GB, be)["ok"])
        self.assertNotIn("resize_fs", [c[0] for c in be.calls])

    def test_resize_limits_enforced(self):
        be = self.be()
        cur = fdrives()["Fake_HDD_8TB"]["partitions"][1]["size"]
        self.assertFalse(dk.resize_partition("/dev/sdb2", 10 ** 15, be)["ok"])        # past the gap
        self.assertFalse(dk.resize_partition("/dev/sdb2", 10 * GB, be)["ok"])         # below used space
        self.assertFalse(dk.resize_partition("/dev/sdb2", cur, be)["ok"])             # unchanged
        self.assertFalse(dk.resize_partition("/dev/sdb2", "abc", be)["ok"])
        self.assertFalse(dk.resize_partition("/dev/sdc1", 10 * GB, be)["ok"])         # FAT32 cannot resize
        self.assertEqual(be.calls, [])

    def test_annotate_marks_everything(self):
        ds = list(fdrives().values())
        dk.annotate(ds, lambda fs: dk.FAKE_CAN_RESIZE.get(fs, (False, 0, "")), self.which)
        by = {d["id"]: d for d in ds}
        self.assertNotEqual(by["Fake_NVMe_1TB"]["table_why"], "")
        self.assertEqual(by["Fake_USB_64GB"]["table_why"], "")
        gap = self.gap(by["Fake_HDD_8TB"])
        self.assertTrue(gap["create"]["ok"])
        self.assertEqual(gap["create"]["max"] % MIB, 0)
        for p in by["Fake_NVMe_1TB"]["partitions"]:
            if p["kind"] == "partition":
                self.assertNotEqual(p["manage"]["delete"], "")
                self.assertFalse(p["manage"]["resize"]["ok"])


class Health(unittest.TestCase):
    def test_nvme_good(self):
        h = FAKE["health"]["Fake_NVMe_1TB"]
        s = dk.health_summary("nvme", h["props"], h["attrs"])
        self.assertEqual(s["verdict"], "good")
        self.assertEqual(s["temperature_c"], 49)

    def test_ata_warning_on_pending(self):
        h = FAKE["health"]["Fake_HDD_8TB"]
        s = dk.health_summary("ata", h["props"], h["attrs"])
        self.assertEqual(s["verdict"], "warning")

    def test_ata_failing(self):
        h = FAKE["health"]["Fake_SATA_SSD_2TB"]
        s = dk.health_summary("ata", dict(h["props"], SmartFailing=True), h["attrs"])
        self.assertEqual(s["verdict"], "failing")

    def test_nvme_critical_and_wear(self):
        s = dk.health_summary("nvme", {"SmartCriticalWarning": ["spare"], "SmartTemperature": 320}, {})
        self.assertEqual(s["verdict"], "failing")
        s = dk.health_summary("nvme", {"SmartCriticalWarning": []}, {"percent_used": 95, "avail_spare": 100, "spare_thresh": 10})
        self.assertEqual(s["verdict"], "warning")

    def test_unsupported_is_unknown(self):
        s = dk.health_summary("ata", {"SmartSupported": False}, [])
        self.assertEqual(s["verdict"], "unknown")


def mk(path, size, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"x" * size)


class Scan(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="tree-", dir=TMP)
        r = self.root
        mk(r + "/a/big.bin", 400000)
        mk(r + "/a/small.txt", 10)
        mk(r + "/b/c/d.bin", 100000)
        os.link(r + "/a/big.bin", r + "/b/hardlink.bin")
        os.symlink("/usr", r + "/link-to-usr")
        os.makedirs(r + "/locked")
        mk(r + "/locked/secret.bin", 50000)
        os.chmod(r + "/locked", 0)
        self.lines = []

    def tearDown(self):
        os.chmod(self.root + "/locked", 0o755)

    def run_scan(self, root=None):
        return dk.scan(root or self.root, write=self.lines.append)

    def test_totals_hardlinks_symlinks_permissions(self):
        s = self.run_scan()
        self.assertTrue(s["ok"] and s["done"])
        c = dk.children(self.root)
        by = {e["name"]: e for e in c["entries"]}
        a, b = by["a"], by["b"]
        self.assertGreaterEqual(a["size"], 400000)
        self.assertLess(a["size"], 400000 + 3 * 4096 + 4096)
        # the hardlink is counted once (with a/big.bin), so b holds only d.bin
        self.assertLess(b["size"], 100000 + 4 * 4096)
        self.assertEqual(c["size"], s["size"])
        self.assertNotIn("usr", json.dumps(c["entries"]))    # the symlink was not followed
        if os.geteuid() != 0:
            self.assertEqual(c["errors"], 1)
            self.assertEqual(s["unreadable"], [self.root + "/locked"])
            self.assertNotIn("secret.bin", json.dumps(c))
        self.assertEqual(c["entries"][0]["name"], "a")        # sorted by size
        self.assertEqual(a["items"], 2)

    def test_stays_on_one_filesystem(self):
        # (no portable second mount to scan across here: check the skip rule and a real scan root instead)
        self.assertTrue(dk.skip_tree("/", "/proc"))
        self.assertTrue(dk.skip_tree("/home/u", "/sys"))
        self.assertFalse(dk.skip_tree("/proc/self", "/proc"))
        self.assertFalse(dk.skip_tree("/run/media/u/x", "/run"))
        s = dk.scan("/boot") if os.access("/boot", os.R_OK | os.X_OK) else None
        self.assertTrue(s is None or s["ok"])

    def test_progress_lines(self):
        for i in range(600):
            mk(self.root + "/many/f%d" % i, 1)
        self.lines.clear()
        dk.scan(self.root, write=self.lines.append, interval=0)
        self.assertTrue(self.lines and all("progress" in l and "bytes" in l and "path" in l for l in self.lines))

    def test_children_rollup(self):
        for i in range(30):
            mk(self.root + "/many/f%02d" % i, 5000 + i * 1000)
        self.run_scan()
        c = dk.children(self.root + "/many", limit=10)
        self.assertEqual(len(c["entries"]), 11)
        self.assertEqual(c["entries"][-1]["kind"], "other")
        self.assertEqual(c["entries"][-1]["name"], "20 smaller items")
        self.assertAlmostEqual(sum(e["pct"] for e in c["entries"]), 100, delta=1.5)
        self.assertTrue(c["entries"][0]["size"] >= c["entries"][1]["size"])

    def test_children_unscanned(self):
        r = dk.children(self.root + "/nowhere-scanned")
        self.assertFalse(r["ok"])

    def test_largest(self):
        self.run_scan()
        l = dk.largest(self.root, 3)
        self.assertEqual(l["files"][0]["path"], self.root + "/a/big.bin")
        self.assertEqual(l["files"][0]["dir"], self.root + "/a")

    def test_trash_refuses_outside_and_root(self):
        self.run_scan()
        calls = []
        runner = lambda *a, **k: calls.append(a) or subprocess.CompletedProcess(a, 0, "", "")
        self.assertFalse(dk.trash(self.root, runner)["ok"])
        self.assertFalse(dk.trash("/etc/hostname", runner)["ok"])
        self.assertFalse(dk.trash(self.root + "/../x", runner)["ok"])
        self.assertFalse(dk.trash(self.root + "/link-to-usr/bin", runner)["ok"])
        self.assertEqual(calls, [])

    def test_trash_updates_cache(self):
        self.run_scan()
        before = dk.children(self.root)["size"]
        calls = []
        def runner(argv, **k):
            calls.append(argv)
            os.remove(argv[-1]) if os.path.isfile(argv[-1]) else __import__("shutil").rmtree(argv[-1])
            return subprocess.CompletedProcess(argv, 0, "", "")
        r = dk.trash(self.root + "/b/c", runner)
        self.assertTrue(r["ok"], r)
        self.assertEqual(calls[0][:3], ["gio", "trash", "--"])
        after = dk.children(self.root)
        self.assertEqual(after["size"], before - r["freed"])
        self.assertIn("b", {e["name"] for e in after["entries"]})
        self.assertFalse(dk.children(self.root + "/b/c")["ok"])
        r = dk.trash(self.root + "/a/small.txt", runner)
        self.assertTrue(r["ok"])
        self.assertEqual(dk.children(self.root + "/a")["items"], 1)

    def test_trash_failure_leaves_cache(self):
        self.run_scan()
        before = dk.children(self.root)["size"]
        bad = lambda argv, **k: subprocess.CompletedProcess(argv, 1, "", "gio: nope")
        self.assertFalse(dk.trash(self.root + "/a/small.txt", bad)["ok"])
        self.assertEqual(dk.children(self.root)["size"], before)


if __name__ == "__main__":
    unittest.main()
