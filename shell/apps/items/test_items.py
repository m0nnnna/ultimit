#!/usr/bin/env python3
"""Unit tests for items.py and its drivers. Run: python3 apps/items/test_items.py
Nothing is sent to a device: items.py runs with ITEMS_FAKE=1 and writes the packets to a file."""
import json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from drivers import DRIVERS, hid, redragon_m990 as m990  # noqa: E402

TMP = tempfile.mkdtemp(prefix="items-test-")


def items(*args, stdin=""):
    env = dict(os.environ, ITEMS_FAKE="1", ITEMS_CONFIG_DIR=TMP + "/cfg", ITEMS_FAKE_OUT=TMP + "/out.txt")
    r = subprocess.run([sys.executable, os.path.join(HERE, "items.py"), *args], input=stdin,
                       capture_output=True, text=True, env=env)
    return json.loads(r.stdout)


def captured_state():
    """The settings the official app last sent in the recording redragon_m990.template was taken from."""
    c = m990.default_config()
    for p in c["profiles"]:
        p.update(effect="wave", brightness=2)
        p["buttons"]["fire"] = "raw:99810300"
    p1 = c["profiles"][0]
    p1["effect"] = "off"
    p1["buttons"].update(side1="ctrl+shift+a", side2="a", dpi_up="a", fire="raw:99810301")
    return c


class Keys(unittest.TestCase):
    def test_parse(self):
        self.assertEqual(hid.parse_key("a"), (0, 0x04))
        self.assertEqual(hid.parse_key("Ctrl + Shift + A"), (0x03, 0x04))
        self.assertEqual(hid.parse_key("kp_plus"), (0, 0x57))
        self.assertEqual(hid.parse_key("f13"), (0, 0x68))
        for bad in ("", "ctrl+", "hyper+a", "nosuchkey"):
            with self.assertRaises(ValueError):
                hid.parse_key(bad)

    def test_text_round_trip(self):
        self.assertEqual(hid.key_text(*hid.parse_key("alt+super+f5")), "alt+super+f5")


class M990(unittest.TestCase):
    def test_actions(self):
        self.assertEqual(m990.encode_action("a").hex(), "90000400")
        self.assertEqual(m990.encode_action("ctrl+shift+a").hex(), "8f030400")
        self.assertEqual(m990.encode_action("dpi_up").hex(), "8a000000")
        self.assertEqual(m990.encode_action("left").hex(), "81000000")      # the mouse button, not the arrow key
        self.assertEqual(m990.encode_action("raw:9b04").hex(), "9b040000")
        for bad in ("raw:zz", "raw:0102030405", "ctrl+nokey"):
            with self.assertRaises(ValueError):
                m990.encode_action(bad)

    def test_matches_official_app(self):
        with open(m990.TEMPLATE) as f:
            want = [l.strip() for l in f if l.strip()]
        self.assertEqual([p.hex() for p in m990.build(captured_state())], want)

    def test_side_buttons_in_order(self):
        c = m990.default_config()
        for i in range(16):
            c["profiles"][0]["buttons"][f"side{i + 1}"] = chr(ord("a") + i)
        pk = {(p[2] | p[3] << 8): p for p in m990.build(c) if p[1] == 0xF3}
        for i in range(16):
            self.assertEqual(pk[0xA2 + 4 * i][8:11].hex(), f"9000{0x04 + i:02x}")

    def test_profile_addresses(self):
        c = m990.default_config()
        c["profiles"][2]["dpi"][0] = 1200
        c["profiles"][4]["color"] = "00ff88"
        pk = {(p[2] | p[3] << 8): p for p in m990.build(c) if p[1] == 0xF3}
        self.assertEqual(pk[0x1B4][8:13].hex(), "010c000c00")
        self.assertEqual(pk[0x469][8:11].hex(), "00ff88")

    def test_invalid(self):
        for change, field in ((("color", "red"), "color"), (("effect", "disco"), "effect"),
                              (("brightness", 9), "brightness"), (("dpi", [50, 0, 0, 0, 0]), "dpi")):
            c = m990.default_config()
            c["profiles"][1][change[0]] = change[1]
            with self.assertRaisesRegex(ValueError, "profile 2: " + field):
                m990.build(c)

    def test_dpi_off(self):
        c = m990.default_config()
        c["profiles"][0]["dpi"][4] = 0
        pk = {(p[2] | p[3] << 8): p for p in m990.build(c) if p[1] == 0xF3}
        self.assertEqual(pk[0x5C][8:13].hex(), "0000000000")


class Helper(unittest.TestCase):
    def test_list_and_get(self):
        o = items("list")
        self.assertTrue(o["ok"])
        self.assertEqual([d["id"] for d in o["devices"]], [d.ID for d in DRIVERS])
        o = items("get", "redragon-m990")
        self.assertTrue(o["ok"])
        self.assertEqual(len(o["config"]["profiles"]), 5)
        self.assertIn("kp_plus", o["keys"])

    def test_set_saves_and_sends(self):
        o = items("set", "redragon-m990", stdin=json.dumps(captured_state()))
        self.assertTrue(o["ok"], o)
        with open(TMP + "/out.txt") as f, open(m990.TEMPLATE) as t:
            self.assertEqual(f.read().split(), t.read().split())
        self.assertEqual(items("get", "redragon-m990")["config"], captured_state())

    def test_set_invalid_saves_nothing(self):
        c = m990.default_config()
        c["profiles"][0]["buttons"]["side3"] = "ctrl+"
        o = items("set", "redragon-m990", stdin=json.dumps(c))
        self.assertFalse(o["ok"])
        self.assertEqual(o["kind"], "invalid")
        self.assertIn("Side 3", o["error"])

    def test_unknown(self):
        self.assertFalse(items("get", "nope")["ok"])
        self.assertFalse(items("set", "redragon-m990", stdin="not json")["ok"])


if __name__ == "__main__":
    unittest.main()
