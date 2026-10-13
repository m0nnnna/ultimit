#!/usr/bin/env python3
"""Unit tests for firewall.py and the root helper (distro/system/usr/libexec/ultimit/firewall-helper).
Run: python3 apps/firewall/test_firewall.py
Nothing touches the real firewall: the helper runs unprivileged against the fake ufw in fixtures/bin."""
import importlib.machinery, importlib.util, json, os, subprocess, sys, tempfile, time, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TMP = tempfile.mkdtemp(prefix="firewall-test-")
for k in ("FIREWALL_FAKE", "FIREWALL_FAKE_STATE", "FIREWALL_FAKE_CANCEL"):
    os.environ.pop(k, None)
os.environ["FIREWALL_UFW_APPS"] = TMP + "/ufw-apps"
os.makedirs(TMP + "/ufw-apps")
with open(TMP + "/ufw-apps/samba", "w") as f:
    f.write("[Samba]\ntitle=SMB\nports=137,138/udp|139,445/tcp\n")


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, path)
    spec = importlib.util.spec_from_loader(name, loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    return m


fw = load("firewall", os.path.join(HERE, "firewall.py"))
HELPER_PATH = os.path.join(fw.SYSTEM, "usr/libexec/ultimit/firewall-helper")
hp = load("firewall_helper", HELPER_PATH)
LAN = {"ip": "192.168.1.42", "subnet": "192.168.1.0/24", "addrs": ["192.168.1.42", "127.0.0.1", "fe80::1"]}
APPS = fw.app_profiles()


def rules(*lines):
    return [fw.parse_rule(l, APPS) for l in lines]


class Parse(unittest.TestCase):
    def test_simple(self):
        r = fw.parse_rule("ufw allow 22/tcp", APPS)
        self.assertEqual((r["action"], r["ports"], r["proto"], r["from"], r["custom"]), ("allow", [(22, 22)], "tcp", "any", False))
        self.assertEqual(fw.summary(r), "Allow 22 TCP from anywhere")

    def test_full_with_comment(self):
        r = fw.parse_rule("ufw allow from 192.168.0.0/24 to any port 25565 comment 'VTube Studio iPhone'", APPS)
        self.assertEqual((r["from"], r["ports"], r["proto"], r["comment"]), ("192.168.0.0/24", [(25565, 25565)], "any", "VTube Studio iPhone"))
        self.assertEqual(fw.summary(r), "Allow 25565 TCP+UDP from 192.168.0.0/24")

    def test_ranges_lists(self):
        r = fw.parse_rule("ufw allow from 10.0.0.0/8 to any port 47998:48000,48002 proto udp", APPS)
        self.assertEqual(r["ports"], [(47998, 48000), (48002, 48002)])
        self.assertEqual(fw.summary(r), "Allow 47998–48000,48002 UDP from 10.0.0.0/8")

    def test_app(self):
        r = fw.parse_rule("ufw allow from 192.168.1.0/24 to any app Samba comment 'Ultimit SHARES'", APPS)
        self.assertEqual(r["app"], "Samba")
        self.assertTrue(fw.covers(r, 445, "tcp", LAN["subnet"]))
        self.assertTrue(fw.covers(r, 137, "udp", LAN["subnet"]))
        self.assertFalse(fw.covers(r, 445, "udp", LAN["subnet"]))
        self.assertTrue(fw.parse_rule("ufw allow Nope", APPS)["custom"])

    def test_odd_forms(self):
        for line in ("ufw deny in on eth0 to any port 80", "ufw route allow in on wg0 out on eth0",
                     "ufw allow from 1.2.3.4 port 53 to any", "ufw limit log 22/tcp", "nonsense 'unclosed"):
            r = fw.parse_rule(line, APPS)
            self.assertEqual(r["line"], line)
            self.assertIsInstance(fw.summary(r), str)
        self.assertEqual(fw.parse_rule("ufw deny in on eth0 to any port 80", APPS)["iface"], "eth0")
        self.assertTrue(fw.parse_rule("ufw allow from 1.2.3.4 port 53 to any", APPS)["custom"])
        r = fw.parse_rule("ufw limit log 22/tcp", APPS)
        self.assertTrue(fw.covers(r, 22, "tcp", LAN["subnet"]))

    def test_verbose(self):
        st = fw.parse_verbose("Status: active\nLogging: on (low)\nDefault: deny (incoming), allow (outgoing), disabled (routed)\n")
        self.assertEqual(st, {"active": True, "incoming": "deny", "outgoing": "allow", "routed": "disabled", "logging": "on (low)"})
        self.assertFalse(fw.parse_verbose("Status: inactive\n")["active"])


class Coverage(unittest.TestCase):
    def test_source(self):
        self.assertTrue(fw.source_covers("any", "192.168.1.0/24"))
        self.assertTrue(fw.source_covers("192.168.0.0/16", "192.168.1.0/24"))
        self.assertFalse(fw.source_covers("192.168.1.164", "192.168.1.0/24"))
        self.assertFalse(fw.source_covers("192.168.1.0/24", ""))

    def test_not_covering(self):
        s = LAN["subnet"]
        for line in ("ufw deny 25565", "ufw allow out 25565", "ufw allow from 192.168.1.5 to any port 25565",
                     "ufw allow in on eth0 to any port 25565", "ufw allow 25565/udp"):
            self.assertFalse(fw.covers(fw.parse_rule(line, APPS), 25565, "tcp", s), line)
        self.assertTrue(fw.covers(fw.parse_rule("ufw allow from 192.168.1.0/24", APPS), 25565, "tcp", s))


class Presets(unittest.TestCase):
    def p(self, pid):
        return fw.preset_by_id(pid)

    def test_ids_unique_and_valid(self):
        self.assertEqual(len({p["id"] for p in fw.PRESETS}), len(fw.PRESETS))
        for p in fw.PRESETS:
            for e in p["ports"]:
                self.assertIsNone(hp.check_port(e["port"], e["proto"]), p["id"])
            self.assertTrue(hp.COMMENT_RE.match(p["name"]), p["name"])

    def test_states(self):
        s = LAN["subnet"]
        self.assertEqual(fw.preset_state(self.p("vtube-studio"), rules("ufw allow from 192.168.1.0/24 to any port 25565"), s), "on")
        self.assertEqual(fw.preset_state(self.p("vtube-studio"), rules("ufw allow 25565/tcp"), s), "partial")
        self.assertEqual(fw.preset_state(self.p("vtube-studio"), rules(), s), "off")
        self.assertEqual(fw.preset_state(self.p("steam"), rules("ufw allow 27031:27036/udp", "ufw allow 27036:27037/tcp"), s), "partial")

    def test_adds_only_missing(self):
        s = LAN["subnet"]
        adds = fw.preset_adds(self.p("steam"), rules("ufw allow 27031:27036/udp"), s)
        self.assertEqual(adds, [{"port": "27036:27037,27040", "proto": "tcp", "from": s, "comment": "Steam Remote Play and LAN transfers"}])
        self.assertEqual(fw.preset_adds(self.p("ifacialmocap"), rules("ufw allow 49983/udp"), s), [])

    def test_owned(self):
        rs = rules("ufw allow 22/tcp", "ufw allow from 192.168.1.0/24 to any port 25565 comment 'VTube Studio iPhone'",
                   "ufw allow from 192.168.1.0/24 to any port 1714:1800 proto tcp",
                   "ufw allow from 192.168.1.0/24 to any port 4455 proto udp comment 'OBS remote control'",
                   "ufw allow from 192.168.1.0/24 to any app Samba")
        self.assertEqual([r["line"] for r in fw.preset_owned(self.p("vtube-studio"), rs)], [rs[1]["line"]])
        self.assertEqual(fw.preset_owned(self.p("kdeconnect"), rs), [])          # wider than the preset: left alone
        self.assertEqual([r["line"] for r in fw.preset_owned(self.p("obs-websocket"), rs)], [rs[3]["line"]])   # by comment
        self.assertEqual([r["line"] for r in fw.preset_owned(self.p("ssh"), rs)], [rs[0]["line"]])

    def test_port_label(self):
        self.assertEqual(fw.port_label(49983, "udp"), ("iFacialMocap tracking", "ifacialmocap"))
        self.assertEqual(fw.port_label(49983, "tcp"), ("", ""))


class Blocked(unittest.TestCase):
    K = "host kernel: [UFW BLOCK] IN=wlan0 OUT= MAC=aa "

    def line(self, t, src, dst, proto, dpt):
        return "%.3f %sSRC=%s DST=%s LEN=60 PROTO=%s SPT=5000 DPT=%d" % (t, self.K, src, dst, proto, dpt)

    def test_grouping(self):
        now = 1000000.0
        lines = [self.line(now - 50, "192.168.1.164", "192.168.1.42", "UDP", 49983),
                 self.line(now - 10, "192.168.1.164", "192.168.1.42", "UDP", 49983),
                 self.line(now - 20, "192.168.1.9", "192.168.1.42", "UDP", 49983),
                 self.line(now - 30, "192.168.1.20", "224.0.0.251", "UDP", 5353),       # mDNS noise
                 self.line(now - 30, "fe80::1", "ff02::1", "UDP", 27036),               # our own echo
                 self.line(now - 40, "192.168.1.20", "192.168.1.255", "UDP", 1716),     # broadcast, not noise
                 self.line(now - 70, "192.168.1.164", "192.168.1.42", "TCP", 25565),
                 "%.3f %sSRC=0.0.0.0 DST=224.0.0.1 LEN=32 PROTO=2" % (now, self.K),
                 "garbage"]
        rs = rules("ufw allow from 192.168.1.0/24 to any port 25565")
        b = fw.blocked(lines, rs, LAN, now)
        self.assertEqual([(g["proto"], g["port"]) for g in b], [("udp", 49983), ("udp", 1716), ("tcp", 25565)])
        g = b[0]
        self.assertEqual((g["count"], g["sources"], g["ago"], g["label"], g["broadcast"], g["allowed"]),
                         (3, ["192.168.1.164", "192.168.1.9"], 10, "iFacialMocap tracking", False, False))
        self.assertTrue(b[1]["broadcast"])
        self.assertTrue(b[2]["allowed"])

    def test_parse_block(self):
        self.assertIsNone(fw.parse_block("123 kernel: something else"))
        e = fw.parse_block(self.line(5.5, "1.2.3.4", "192.168.1.42", "TCP", 22))
        self.assertEqual((e["t"], e["src"], e["proto"], e["port"]), (5.5, "1.2.3.4", "tcp", 22))


class CheckAllow(unittest.TestCase):
    def test_friendly(self):
        self.assertEqual(fw.check_allow("27031-27036", "udp"), ("27031:27036", None))
        self.assertEqual(fw.check_allow(" 80, 443 ", "tcp"), ("80,443", None))
        for port, proto in (("", "tcp"), ("abc", "tcp"), ("0", "tcp"), ("70000", "udp"), ("10:5", "tcp"),
                            ("80,443", "any"), ("1000:2000", "any"), ("80", "icmp"), ("5:5", "tcp")):
            self.assertIsNotNone(fw.check_allow(port, proto)[1], (port, proto))

    def test_helper_agrees(self):
        for port, proto in (("25565", "any"), ("1714:1764", "tcp"), ("47998:48000,48002,48010", "udp")):
            self.assertIsNone(hp.check_port(port, proto))
        for port, proto in (("1:1", "tcp"), ("0", "tcp"), ("65536", "tcp"), ("80;reboot", "tcp"), ("80", "any;x"),
                            ("1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16", "tcp"), ("1:2", "any")):
            self.assertIsNotNone(hp.check_port(port, proto), (port, proto))


class Helper(unittest.TestCase):
    """The real helper, unprivileged, against the fake ufw."""
    def setUp(self):
        self.d = tempfile.mkdtemp(dir=TMP)
        subprocess.run([os.path.join(HERE, "fixtures", "make-state.sh"), self.d, "ready"], check=True)
        b = os.path.join(HERE, "fixtures", "bin")
        self.env = dict(os.environ, FIREWALL_FAKE_STATE=self.d, FIREWALL_UFW=b + "/ufw", FIREWALL_JOURNALCTL=b + "/journalctl")

    def h(self, *args, stdin=None):
        p = subprocess.run([sys.executable, HELPER_PATH] + list(args), input=stdin, capture_output=True, text=True, env=self.env)
        return json.loads(p.stdout)

    def added(self):
        with open(self.d + "/added") as f:
            return f.read().splitlines()

    def test_status(self):
        o = self.h("status")
        self.assertTrue(o["ok"] and o["installed"])
        self.assertIn("ufw allow 22/tcp", o["added"])
        self.assertTrue(all("[UFW BLOCK]" in l for l in o["log"]) and len(o["log"]) == 8)

    def test_apply(self):
        o = self.h("apply", stdin=json.dumps({"add": [{"port": "49983", "proto": "udp", "from": "192.168.1.0/24", "comment": "iFacialMocap tracking"}],
                                             "remove": ["ufw allow 22/tcp"]}))
        self.assertEqual(o, {"ok": True, "done": 2})
        self.assertNotIn("ufw allow 22/tcp", self.added())
        self.assertIn("ufw allow from 192.168.1.0/24 to any port 49983 proto udp comment 'iFacialMocap tracking'", self.added())

    def test_rejects_everything_on_one_bad_item(self):
        before = self.added()
        for req in ({"add": [{"port": "80", "proto": "tcp", "from": "any"}, {"port": "80; rm -rf /", "proto": "tcp", "from": "any"}]},
                    {"add": [{"port": "80", "proto": "tcp", "from": "not-an-ip"}]},
                    {"add": [{"port": "80", "proto": "tcp", "from": "any", "comment": "x' ; reboot"}]},
                    {"remove": ["ufw allow 1/tcp"]},
                    {"remove": ["ufw allow 22/tcp; reboot"]},
                    [1, 2]):
            self.assertFalse(self.h("apply", stdin=json.dumps(req))["ok"], req)
        self.assertFalse(self.h("apply", stdin="not json")["ok"])
        self.assertEqual(self.added(), before)

    def test_usage(self):
        self.assertFalse(self.h("status", "extra")["ok"])
        self.assertFalse(self.h("frobnicate")["ok"])

    def test_enable_disable(self):
        self.assertTrue(self.h("disable")["ok"])
        self.assertFalse(os.path.exists(self.d + "/active"))
        self.assertTrue(self.h("enable")["ok"])
        self.assertTrue(os.path.exists(self.d + "/active"))

    def test_no_ufw(self):
        os.remove(self.d + "/ufw-installed")
        self.assertEqual(self.h("status"), {"ok": True, "installed": False})


class EndToEnd(unittest.TestCase):
    """firewall.py with FIREWALL_FAKE=1, as the UI runs it."""
    def setUp(self):
        self.d = tempfile.mkdtemp(dir=TMP)
        self.env = dict(os.environ, FIREWALL_FAKE="1", FIREWALL_FAKE_STATE=self.d)
        self.env.pop("FIREWALL_UFW_APPS")

    def fw(self, *args, scenario=None, env=None):
        if scenario:
            subprocess.run([os.path.join(HERE, "fixtures", "make-state.sh"), self.d, scenario], check=True)
        p = subprocess.run([sys.executable, os.path.join(HERE, "firewall.py")] + list(args), capture_output=True, text=True,
                           env=dict(self.env, **(env or {})))
        return json.loads(p.stdout)

    def test_ready(self):
        o = self.fw("state", scenario="ready")
        self.assertTrue(o["ok"] and o["helper"] and o["ufw"]["active"])
        self.assertEqual(o["subnet"], "192.168.1.0/24")
        states = {p["id"]: p["state"] for p in o["presets"]}
        self.assertEqual((states["vtube-studio"], states["ssh"], states["ifacialmocap"]), ("on", "on", "off"))
        self.assertEqual(o["blocked"][0]["port"], 1716)
        self.assertIn(49983, [b["port"] for b in o["blocked"]])

    def test_preset_roundtrip(self):
        self.fw("state", scenario="ready")
        self.assertEqual(self.fw("preset", "ifacialmocap", "on")["changed"], 1)
        st = {p["id"]: p["state"] for p in self.fw("state")["presets"]}
        self.assertEqual(st["ifacialmocap"], "on")
        self.assertEqual(self.fw("preset", "vtube-studio", "off")["changed"], 1)
        o = self.fw("state")
        self.assertEqual({p["id"]: p["state"] for p in o["presets"]}["vtube-studio"], "off")
        self.assertTrue(any(r["app"] == "Samba" for r in o["rules"]))          # other rules untouched

    def test_scenarios(self):
        self.assertFalse(self.fw("state", scenario="nohelper")["helper"])
        self.assertFalse(self.fw("state", scenario="noufw")["ufw"]["installed"])
        o = self.fw("state", scenario="off")
        self.assertFalse(o["ufw"]["active"])
        self.assertTrue(self.fw("enable")["ok"])
        self.assertTrue(self.fw("state")["ufw"]["active"])

    def test_cancel(self):
        self.fw("state", scenario="ready")
        o = self.fw("preset", "ifacialmocap", "on", env={"FIREWALL_FAKE_CANCEL": "1"})
        self.assertEqual((o["ok"], o["cancelled"]), (False, True))
        self.assertTrue(self.fw("state", env={"FIREWALL_FAKE_CANCEL": "1"})["locked"])

    def test_install_helper_into_fake_root(self):
        self.fw("state", scenario="nohelper")
        self.assertTrue(self.fw("setup", "install-helper")["ok"])
        self.assertTrue(self.fw("state")["helper"])
        self.assertTrue(os.access(self.d + "/root/usr/libexec/ultimit/firewall-helper", os.X_OK))

    def test_setup_commands(self):
        steps = {s["id"]: s for s in self.fw("setup-commands")["steps"]}
        self.assertTrue(steps["install-helper"]["display"].startswith("pkexec /bin/sh -ec"))
        self.assertIn("/usr/libexec/ultimit/firewall-helper", steps["install-helper"]["display"])


if __name__ == "__main__":
    unittest.main()
