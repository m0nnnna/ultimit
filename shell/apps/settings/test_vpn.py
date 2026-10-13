#!/usr/bin/python3 -I
"""Tests for vpn.py (Settings > Network > VPN) with a fake nmcli: python3 apps/settings/test_vpn.py"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import vpn  # noqa: E402

WG = "[Interface]\nPrivateKey = abc=\nAddress = 10.0.0.2/32\n\n[Peer]\nPublicKey = def=\nAllowedIPs = 0.0.0.0/0\nEndpoint = 1.2.3.4:51820\n"
OVPN = "client\ndev tun\nproto udp\nremote us-east.example.com 1198\nauth-user-pass\n<ca>\nX\n</ca>\n"


class Parse(unittest.TestCase):
    def test_kind(self):
        self.assertEqual(vpn.kind_of(WG), "wireguard")
        self.assertEqual(vpn.kind_of(OVPN), "openvpn")
        self.assertEqual(vpn.kind_of("hello"), "")

    def test_iface_and_fields(self):
        self.assertEqual(vpn.iface_name("My Home VPN!"), "wg-my-home-vpn")
        self.assertLessEqual(len(vpn.iface_name("a very long name for a tunnel")), 15)
        self.assertEqual(vpn.split_fields(r"Home Wi\:Fi:uuid:vpn:yes"), ["Home Wi:Fi", "uuid", "vpn", "yes"])


class WithFakeNmcli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.log = os.path.join(self.tmp.name, "calls")

    def tearDown(self):
        self.tmp.cleanup()

    def run_vpn(self, *args, stdin=""):
        env = dict(os.environ, VPN_NMCLI=os.path.join(HERE, "fixtures/fake-nmcli"), VPN_TEST_LOG=self.log)
        p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "vpn.py")] + list(args), input=stdin,
                           capture_output=True, text=True, env=env)
        return json.loads(p.stdout)

    def calls(self):
        with open(self.log) as f:
            return f.read().splitlines()

    def test_import_wireguard(self):
        f = os.path.join(self.tmp.name, "Home Office.conf")
        with open(f, "w") as fh:
            fh.write(WG)
        o = self.run_vpn("import", f)
        self.assertEqual((o["kind"], o["name"], o["needsLogin"]), ("wireguard", "Home Office", False))
        c = self.calls()
        self.assertTrue(c[0].startswith("connection import type wireguard file ") and c[0].endswith("/wg-home-office.conf"))
        self.assertIn("connection modify 11111111-2222-3333-4444-555555555555 connection.id Home Office connection.autoconnect no", c)
        self.assertIn("connection down 11111111-2222-3333-4444-555555555555", c)   # not left connected

    def test_import_openvpn_and_paste(self):
        f = os.path.join(self.tmp.name, "us_east.ovpn")
        with open(f, "w") as fh:
            fh.write(OVPN)
        o = self.run_vpn("import", f, "PIA US East")
        self.assertEqual((o["kind"], o["needsLogin"]), ("openvpn", True))
        self.assertFalse(self.run_vpn("import", os.path.join(self.tmp.name, "nothing.conf"))["ok"])
        self.assertFalse(self.run_vpn("paste", "X", stdin="not a config")["ok"])
        self.assertTrue(self.run_vpn("paste", "Pasted", stdin=WG)["ok"])

    def test_list_skips_non_vpn(self):
        o = self.run_vpn("list")
        self.assertEqual([v["name"] for v in o["vpns"]], ["Office"])


if __name__ == "__main__":
    unittest.main()
