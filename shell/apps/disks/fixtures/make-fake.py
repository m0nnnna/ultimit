#!/usr/bin/env python3
"""Writes fake-objects.json: a GetManagedObjects-style snapshot of four pretend drives (an NVMe system disk, a SATA SSD
with NTFS, an 8 TB HDD, a USB stick) for DISKS_FAKE=1, plus pretend usage and SMART data. Run: python3 make-fake.py"""
import json, os
UD = "org.freedesktop.UDisks2"
GB = 10**9
GPT_ESP, GPT_LINUX, GPT_SWAP, GPT_DATA = ("c12a7328-f81f-11d2-ba4b-00a0c93ec93b", "0fc63daf-8483-4772-8e79-3d69d8477de4",
                                          "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f", "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7")
objs, usage, health = {}, {}, {}


def drive(did, model, vendor, size, bus, rot, removable=False, ejectable=False, power=False, ata=False, nvme=False, sort=""):
    objs["/org/freedesktop/UDisks2/drives/" + did] = {UD + ".Drive": {
        "Model": model, "Vendor": vendor, "Size": size, "ConnectionBus": bus, "RotationRate": rot, "Removable": removable,
        "MediaRemovable": removable, "Ejectable": ejectable, "CanPowerOff": power, "Media": "", "MediaAvailable": True,
        "Optical": False, "SortKey": sort}}
    if ata:
        objs["/org/freedesktop/UDisks2/drives/" + did][UD + ".Drive.Ata"] = {"SmartSupported": True, "SmartEnabled": True}
    if nvme:
        objs["/org/freedesktop/UDisks2/drives/" + did][UD + ".NVMe.Controller"] = {}


def disk(name, did, size, table="gpt"):
    objs["/org/freedesktop/UDisks2/block_devices/" + name] = {UD + ".Block": {
        "Device": "/dev/" + name, "Drive": "/org/freedesktop/UDisks2/drives/" + did, "Size": size, "IdType": "", "IdLabel": "",
        "IdUUID": "", "CryptoBackingDevice": "/", "ReadOnly": False}}
    if table:
        objs["/org/freedesktop/UDisks2/block_devices/" + name][UD + ".PartitionTable"] = {"Type": table}


def part(disk_name, did, n, offset, size, ptype, fs, label, mounts, used=0, pname="", sep="p"):
    name = disk_name + (sep if disk_name[-1].isdigit() else "") + str(n)
    o = {UD + ".Block": {"Device": "/dev/" + name, "Drive": "/org/freedesktop/UDisks2/drives/" + did, "Size": size,
                         "IdType": fs, "IdLabel": label, "IdUUID": "%08X-%04X" % (hash(name) & 0xffffffff, n), "CryptoBackingDevice": "/",
                         "ReadOnly": False},
         UD + ".Partition": {"Number": n, "Offset": offset, "Size": size, "Type": ptype, "Name": pname,
                             "Table": "/org/freedesktop/UDisks2/block_devices/" + disk_name, "IsContainer": False, "IsContained": False}}
    if fs not in ("", "swap"):
        o[UD + ".Filesystem"] = {"MountPoints": mounts}
    if fs == "swap":
        o[UD + ".Swapspace"] = {"Active": True}
    objs["/org/freedesktop/UDisks2/block_devices/" + name] = o
    if mounts or used:
        usage["/dev/" + name] = [size, used]


MB = 1 << 20
drive("Fake_NVMe_1TB", "Fake NVMe 1TB", "", 1000 * GB, "", 0, nvme=True, sort="00coldplug/00fixed/nvme0")
disk("nvme0n1", "Fake_NVMe_1TB", 1000 * GB)
part("nvme0n1", "Fake_NVMe_1TB", 1, MB, 512 * MB, GPT_ESP, "vfat", "", ["/boot/efi"], 40 * MB, "EFI system partition")
part("nvme0n1", "Fake_NVMe_1TB", 2, 513 * MB, 400 * GB, GPT_LINUX, "ext4", "", ["/"], 160 * GB)
part("nvme0n1", "Fake_NVMe_1TB", 3, 513 * MB + 400 * GB, 300 * GB, GPT_LINUX, "ext4", "home", ["/home"], 120 * GB)
part("nvme0n1", "Fake_NVMe_1TB", 4, 513 * MB + 700 * GB, 16 * GB, "0657fd6d-a4ab-43c4-84e5-0933c84b4f4f", "swap", "", [], 0)
# the last ~280 GB are left unallocated

drive("Fake_SATA_SSD_2TB", "Fake SATA SSD 2TB", "", 2000 * GB, "", 0, ata=True, sort="00coldplug/00fixed/sd____a")
disk("sda", "Fake_SATA_SSD_2TB", 2000 * GB)
part("sda", "Fake_SATA_SSD_2TB", 1, MB, 2000 * GB - 2 * MB, GPT_DATA, "ntfs", "Games", ["/run/media/fake/Games"], 1210 * GB)

drive("Fake_HDD_8TB", "Fake HDD 8TB", "", 8000 * GB, "", -1, ata=True, sort="00coldplug/00fixed/sd____b")
disk("sdb", "Fake_HDD_8TB", 8000 * GB)
part("sdb", "Fake_HDD_8TB", 1, MB, 6000 * GB, GPT_DATA, "ntfs", "Archive", [], 4300 * GB)
part("sdb", "Fake_HDD_8TB", 2, 6000 * GB + MB, 1500 * GB, GPT_LINUX, "ext4", "Backups", [], 900 * GB)

drive("Fake_USB_64GB", "Cruzer Blade", "SanDisk", 64 * GB, "usb", 0, removable=True, ejectable=True, power=True,
      sort="01hotplug/usb1")
disk("sdc", "Fake_USB_64GB", 64 * GB, table="dos")
part("sdc", "Fake_USB_64GB", 1, MB, 64 * GB - MB, "0x0c", "vfat", "STICK", [], 8 * GB)

nv = {"SmartCriticalWarning": [], "SmartPowerOnHours": 7908, "SmartTemperature": 322, "SmartSelftestStatus": "success", "SmartUpdated": 1}
health["Fake_NVMe_1TB"] = {"props": nv, "attrs": {"percent_used": 4, "avail_spare": 100, "spare_thresh": 10, "media_errors": 0}}
ok = {"SmartSupported": True, "SmartEnabled": True, "SmartFailing": False, "SmartNumAttributesFailing": 0, "SmartNumBadSectors": 0,
      "SmartPowerOnSeconds": 3600 * 12000, "SmartTemperature": 306.0, "SmartSelftestStatus": "success", "SmartUpdated": 1}
health["Fake_SATA_SSD_2TB"] = {"props": ok, "attrs": [[5, "reallocated-sector-count", 0, 100, 100, 10, 0, 1, {}],
                                                       [197, "current-pending-sector", 0, 100, 100, 0, 0, 1, {}]]}
health["Fake_HDD_8TB"] = {"props": dict(ok, SmartPowerOnSeconds=3600 * 41000, SmartTemperature=315.0, SmartNumBadSectors=10),
                          "attrs": [[5, "reallocated-sector-count", 0, 98, 98, 36, 8, 1, {}],
                                    [197, "current-pending-sector", 0, 100, 100, 0, 2, 1, {}]]}
json.dump({"objects": objs, "usage": usage, "health": health}, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "fake-objects.json"), "w"), indent=1, sort_keys=True)
