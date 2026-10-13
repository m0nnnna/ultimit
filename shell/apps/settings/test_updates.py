#!/usr/bin/python3 -I
"""Tests for updates.py's parsers and its fake-data mode: python3 apps/settings/test_updates.py"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import updates  # noqa: E402

SIM = """NOTE: This is only a simulation!
Calculating upgrade...
The following upgrades have been deferred due to phasing:
  gnome-foo libbar1
The following packages have been kept back:
  linux-generic
7 upgraded, 1 newly installed, 0 to remove and 1 not upgraded.
Inst libx11-6:i386 [2:1.8.13-1] (2:1.8.13-1ubuntu0.1 Ubuntu:26.04/resolute-security [i386]) [libx11-6:amd64 on libx11-6:i386]
Inst libx11-6 [2:1.8.13-1] (2:1.8.13-1ubuntu0.1 Ubuntu:26.04/resolute-security [amd64])
Inst mesa-vulkan-drivers [25.2.0-1] (25.2.1-1 Ubuntu:26.04/resolute-updates [amd64])
Inst linux-image-7.0.0-40-generic (7.0.0-40.40 Ubuntu:26.04/resolute-updates [amd64])
Conf libx11-6 (2:1.8.13-1ubuntu0.1 Ubuntu:26.04/resolute-security [amd64])
"""

UU = """2026-10-11 06:10:01,000 INFO Starting unattended upgrades script
2026-10-11 06:10:05,000 INFO All upgrades installed
2026-10-12 11:31:22,071 INFO Starting unattended upgrades script
2026-10-12 11:31:22,073 INFO Allowed origins are: o=Ubuntu,a=resolute
2026-10-12 11:31:30,000 INFO No packages found that can be upgraded unattended and no pending auto-removals
"""


class Parsers(unittest.TestCase):
    def test_apt_sim(self):
        pkgs, held = updates.parse_apt_sim(SIM)
        self.assertEqual([p["name"] for p in pkgs], ["libx11-6", "mesa-vulkan-drivers", "linux-image-7.0.0-40-generic"])
        x11 = pkgs[0]
        self.assertEqual(x11["archs"], ["i386", "amd64"])
        self.assertTrue(x11["security"])
        self.assertEqual((x11["from"], x11["to"]), ("2:1.8.13-1", "2:1.8.13-1ubuntu0.1"))
        self.assertFalse(pkgs[1]["security"])
        self.assertTrue(pkgs[2]["new"])
        self.assertEqual(held, ["gnome-foo", "libbar1", "linux-generic"])

    def test_flatpak(self):
        out = updates.parse_flatpak("org.mozilla.firefox\tFirefox\tstable\t131.0\nbad line\n")
        self.assertEqual(out, [{"id": "org.mozilla.firefox", "name": "Firefox", "branch": "stable", "version": "131.0"}])

    def test_fwupd(self):
        d = {"Devices": [
            {"Name": "UEFI dbx", "Version": "20230501", "Flags": ["needs-reboot"],
             "Releases": [{"Version": "20260402", "Summary": "Forbidden list"}, {"Version": "20250902"}]},
            {"Name": "Touchpad", "Version": "1.0", "Releases": []}]}
        out = updates.parse_fwupd(json.dumps(d))
        self.assertEqual(len(out), 1)
        self.assertEqual((out[0]["to"], out[0]["reboot"]), ("20260402", True))
        self.assertEqual(updates.parse_fwupd("No updatable devices"), [])

    def test_uu_log(self):
        self.assertEqual(updates.parse_uu_log(UU), {"time": "2026-10-12 11:31:22",
                         "text": "No packages found that can be upgraded unattended and no pending auto-removals"})
        self.assertIsNone(updates.parse_uu_log(""))


class FakeMode(unittest.TestCase):
    def test_status(self):
        with tempfile.TemporaryDirectory() as d:
            for name, text in (("apt-sim.txt", SIM), ("unattended.log", UU), ("reboot-required", ""),
                               ("reboot-required.pkgs", "linux-base\nlinux-base\nlibc6\n")):
                with open(os.path.join(d, name), "w") as f:
                    f.write(text)
            p = subprocess.run([sys.executable, "-I", updates.__file__, "status"], capture_output=True, text=True,
                               env=dict(os.environ, UPDATES_FAKE_DIR=d))
            o = json.loads(p.stdout)
            self.assertEqual(len(o["apt"]), 3)
            self.assertTrue(o["reboot"])
            self.assertEqual(o["rebootPkgs"], ["libc6", "linux-base"])
            self.assertEqual(o["firmware"], [])


if __name__ == "__main__":
    unittest.main()
