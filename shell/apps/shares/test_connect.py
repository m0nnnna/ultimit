#!/usr/bin/env python3
"""Unit tests for connect.py. Run: python3 apps/shares/test_connect.py
Real Gio is never touched: avahi goes through a fake runner, everything else through FakeBackend (SHARES_FAKE=1 style)."""
import importlib.util, json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TMP = tempfile.mkdtemp(prefix="connect-test-")
os.environ.update({"HOME": TMP + "/home", "XDG_CONFIG_HOME": TMP + "/config"})
for k in ("SHARES_FAKE", "SHARES_BIN_DIR"):
    os.environ.pop(k, None)
sys.path.insert(0, HERE)
spec = importlib.util.spec_from_file_location("connect", os.path.join(HERE, "connect.py"))
connect = importlib.util.module_from_spec(spec)
spec.loader.exec_module(connect)
S = connect.S

AVAHI = r"""+;eth0;IPv4;FAMILY\032NAS;_smb._tcp;local
+;eth0;IPv6;FAMILY\032NAS;_smb._tcp;local
=;eth0;IPv6;FAMILY\032NAS;_smb._tcp;local;family-nas.local;fe80::1234;445;
=;eth0;IPv4;FAMILY\032NAS;_smb._tcp;local;family-nas.local;192.168.1.20;445;
=;eth0;IPv4;ultimit-box;_smb._tcp;local;ultimit-box.local;192.168.1.42;445;
=;wlan0;IPv4;Anna's MacBook;_smb._tcp;local;annas-macbook.local;192.168.1.31;445;"model=Mac"
=;eth0;IPv4;broken;_smb._tcp;local
"""


def put(path, text):
    with open(path, "w") as f:
        f.write(text)


def fake_runner(answers):
    def r(argv, input_text=None, timeout=15):
        for n in range(len(argv), 0, -1):
            a = answers.get(tuple(argv[:n]))
            if a:
                return a
        return 0, "", ""
    return r


class Normalize(unittest.TestCase):
    def check(self, text, uri, kind, **kw):
        n = connect.normalize(text)
        self.assertTrue(n["ok"], (text, n))
        self.assertEqual((n["uri"], n["kind"]), (uri, kind), text)
        for k, v in kw.items():
            self.assertEqual(n[k], v, (text, k))

    def test_forms(self):
        self.check(r"\\host\share", "smb://host/share", "share", host="host", share="share")
        self.check(r"\\host\share\sub dir\x", "smb://host/share/sub%20dir/x", "share")
        self.check("//host/share", "smb://host/share", "share")
        self.check("smb://host/share", "smb://host/share", "share")
        self.check("SMB://Host/Share/", "smb://Host/Share", "share")
        self.check("host/share", "smb://host/share", "share")
        self.check("192.168.1.20/media", "smb://192.168.1.20/media", "share")
        self.check("host", "smb://host/", "server")
        self.check(r"\\host", "smb://host/", "server")
        self.check("smb://host", "smb://host/", "server")
        self.check("192.168.1.20", "smb://192.168.1.20/", "server")
        self.check("  smb://nas.local/My%20Files  ", "smb://nas.local/My%20Files", "share", path="My Files")

    def test_user_in_address(self):
        self.check("smb://bob@host/docs", "smb://host/docs", "share", user="bob")
        self.check("smb://ACME;bob@host/docs", "smb://host/docs", "share", user="bob", domain="ACME")

    def test_other_schemes(self):
        self.check("sftp://me@box/home/me", "sftp://box/home/me", "other", user="me")
        self.check("dav://box/x", "dav://box/x", "other")

    def test_bad(self):
        for t in ("", "   ", "http://x/y", "smb://", "a b c", r"\\\\", "//", "host name/share", "ho$t/x"):
            n = connect.normalize(t)
            self.assertFalse(n["ok"], t)
            self.assertEqual(n["code"], "bad_address")

    def test_uri_helpers(self):
        self.assertEqual(connect.uri_key("SMB://Host/Share/"), connect.uri_key("smb://host/Share"))
        self.assertEqual(connect.uri_label("smb://nas/media"), "media on nas")
        self.assertEqual(connect.uri_label("smb://nas/"), "nas")


class Discover(unittest.TestCase):
    def tearDown(self):
        S.runner = S.default_runner

    def test_parse(self):
        got = connect.parse_avahi(AVAHI, "ultimit-box")
        self.assertEqual([g["name"] for g in got], ["Anna's MacBook", "FAMILY NAS", "ultimit-box"])
        nas = got[1]
        self.assertEqual((nas["host"], nas["address"], nas["source"]), ("family-nas.local", "192.168.1.20", "avahi"))   # IPv4 beats IPv6
        self.assertTrue(got[2]["self"] and not nas["self"])

    def test_parse_empty(self):
        self.assertEqual(connect.parse_avahi(""), [])
        self.assertEqual(connect.parse_avahi("garbage\n=;x\n"), [])

    def test_discover_uses_name_only_when_it_resolves(self):
        S.runner = fake_runner({("avahi-browse", "-ptr", "_smb._tcp"): (0, AVAHI, ""), ("hostname",): (0, "ultimit-box\n", "")})
        r = connect.discover(resolve=lambda n: n == "family-nas.local")
        hosts = {s["name"]: s["host"] for s in r["servers"]}
        self.assertEqual(hosts["FAMILY NAS"], "family-nas.local")
        self.assertEqual(hosts["Anna's MacBook"], "192.168.1.31")      # does not resolve: fall back to the address

    def test_discover_missing_tool_and_failure(self):
        S.runner = fake_runner({("avahi-browse",): (127, "", "not found")})
        r = connect.discover()
        self.assertTrue(r["ok"] and r["servers"] == [] and "not installed" in r["err"])
        S.runner = fake_runner({("avahi-browse",): (1, "", "Failed to create client object: Daemon not running")})
        self.assertIn("Daemon", connect.discover()["err"])

    def test_argv(self):
        calls = []
        def rec(argv, i=None, t=15):
            calls.append(argv)
            return 0, "", ""
        S.runner = rec
        connect.discover()
        self.assertEqual(calls[0], ["avahi-browse", "-ptr", "_smb._tcp"])


class Saved(unittest.TestCase):
    def setUp(self):
        os.environ["XDG_CONFIG_HOME"] = TMP + "/config"
        subprocess.run(["rm", "-rf", TMP + "/config"])

    def test_empty_and_corrupt(self):
        self.assertEqual(connect.load_saved(), [])
        os.makedirs(connect.config_dir())
        put(connect.saved_path(), "{not json")
        self.assertEqual(connect.load_saved(), [])
        put(connect.saved_path(), json.dumps([{"uri": "smb://a/b"}, "junk", {"nouri": 1}]))
        self.assertEqual([c["uri"] for c in connect.load_saved()], ["smb://a/b"])

    def test_save_upsert_remove(self):
        r = connect.save_connection(r"\\nas\media", user="bob", remember=True, reconnect=True)
        self.assertTrue(r["ok"])
        c = connect.load_saved()
        self.assertEqual(c, [{"name": "media on nas", "uri": "smb://nas/media", "user": "bob", "domain": "", "remember": True, "reconnectAtLogin": True}])
        connect.save_connection("smb://NAS/media/", name="Media")           # same share: updated, not duplicated; reconnect stays on
        c = connect.load_saved()
        self.assertEqual((len(c), c[0]["name"], c[0]["reconnectAtLogin"]), (1, "Media", True))
        connect.save_connection("smb://nas/backup")
        self.assertEqual(len(connect.load_saved()), 2)
        self.assertTrue(connect.set_reconnect("smb://nas/backup", True)["ok"])
        self.assertTrue(connect.load_saved()[1]["reconnectAtLogin"])
        self.assertFalse(connect.set_reconnect("smb://nope/x", True)["ok"])
        connect.unsave_connection(r"\\nas\media")
        self.assertEqual([c["uri"] for c in connect.load_saved()], ["smb://nas/backup"])

    def test_no_password_ever_in_file_and_private_mode(self):
        connect.save_connection("smb://nas/media", user="bob", remember=True)
        with open(connect.saved_path()) as f:
            raw = f.read()
        self.assertNotIn("password", raw.lower().replace('"remember"', ""))
        self.assertEqual(os.stat(connect.saved_path()).st_mode & 0o777, 0o600)

    def test_bad_address_not_saved(self):
        self.assertFalse(connect.save_connection("http://x")["ok"])
        self.assertEqual(connect.load_saved(), [])


class Fakes(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(dir=TMP)
        subprocess.run(["sh", os.path.join(HERE, "fixtures", "make-state.sh"), self.d, "fresh"], check=True)
        self.be = connect.FakeBackend(self.d + "/connect-fake.json")
        os.environ["XDG_CONFIG_HOME"] = self.d + "/config"
        os.environ.pop("SHARES_FAKE_KEYRING", None)

    def test_browse_flow(self):
        self.assertEqual(connect.do_browse(self.be, "family-nas.local", None)["shares"], ["backup", "media", "photos", "public"])
        r = connect.do_browse(self.be, r"\\annas-macbook.local", None)
        self.assertEqual(r["code"], "needs_password")
        r = connect.do_browse(self.be, "annas-macbook.local", {"user": "anna", "password": "bad"})
        self.assertEqual(r["code"], "denied")
        self.assertTrue(connect.do_browse(self.be, "annas-macbook.local", {"user": "anna", "password": "pw"})["ok"])
        self.assertEqual(connect.do_browse(self.be, "nowhere", None)["code"], "not_found")
        self.assertEqual(connect.do_browse(self.be, "sftp://x/", None)["code"], "bad_address")

    def test_connect_mounts_disconnect(self):
        r = connect.do_connect(self.be, "//family-nas.local/media", None, False)
        self.assertTrue(r["ok"], r)
        self.assertTrue(os.path.isdir(r["path"]))
        self.assertEqual([m["uri"] for m in self.be.mounts()], ["smb://family-nas.local/media"])
        self.assertTrue(connect.do_connect(self.be, "smb://family-nas.local/media", None, False)["ok"])     # already mounted: success
        self.assertEqual(len(self.be.mounts()), 1)
        self.assertTrue(self.be.disconnect("smb://family-nas.local/media")["ok"])
        self.assertEqual(self.be.mounts(), [])

    def test_connect_errors(self):
        self.assertEqual(connect.do_connect(self.be, "family-nas.local", None, False)["code"], "bad_address")     # a server, not a share
        self.assertEqual(connect.do_connect(self.be, "family-nas.local/nope", None, False)["code"], "not_found")
        self.assertEqual(connect.do_connect(self.be, "office-pc/docs", None, False)["code"], "needs_password")
        self.assertEqual(connect.do_connect(self.be, "office-pc/docs", {"user": "bob", "password": "x"}, False)["code"], "denied")

    def test_user_from_address_without_password_still_asks(self):
        self.assertEqual(connect.do_connect(self.be, "smb://bob@office-pc/docs", None, False)["code"], "needs_password")

    def test_remember_and_locked_keyring(self):
        c = {"user": "bob", "password": "pw"}
        r = connect.do_connect(self.be, "office-pc/docs", c, True)
        self.assertTrue(r["ok"] and r["passwordSaved"])
        self.be.disconnect("smb://office-pc/docs")
        os.environ["SHARES_FAKE_KEYRING"] = "locked"
        r = connect.do_connect(self.be, "office-pc/docs", c, True)
        self.assertTrue(r["ok"])
        self.assertFalse(r["passwordSaved"])
        self.assertIn("not saved", r["note"])
        self.assertNotIn("pw", json.dumps(r).replace("passwordSaved", ""))

    def test_reconnect_skips_mounted_and_password_needed(self):
        connect.save_connection("smb://family-nas.local/media", reconnect=True)
        connect.save_connection("smb://office-pc/docs", user="bob", reconnect=True)       # needs a password: skipped quietly
        connect.save_connection("smb://family-nas.local/photos")                          # not marked
        r = connect.do_reconnect(self.be)
        self.assertEqual([(x["uri"], x["ok"]) for x in r["results"]], [("smb://family-nas.local/media", True), ("smb://office-pc/docs", False)])
        self.assertEqual(r["results"][1]["code"], "needs_password")
        self.assertEqual(connect.do_reconnect(self.be)["results"][0]["uri"], "smb://office-pc/docs")   # media is mounted now


class Cli(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(dir=TMP)
        subprocess.run(["sh", os.path.join(HERE, "fixtures", "make-state.sh"), self.d, "ready"], check=True)
        self.env = dict(os.environ, SHARES_FAKE="1", SHARES_FAKE_STATE=self.d, XDG_CONFIG_HOME=self.d + "/config")

    def sh(self, *args, stdin=None):
        p = subprocess.run([sys.executable, os.path.join(HERE, "connect.py")] + list(args), env=self.env, input=stdin,
                           capture_output=True, text=True)
        return json.loads(p.stdout)

    def test_state_and_lists(self):
        self.assertEqual(len(self.sh("discover")["servers"]), 3)
        self.assertEqual(len(self.sh("mounts")["mounts"]), 1)
        self.assertEqual(len(self.sh("saved")["saved"]), 2)
        self.assertTrue(self.sh("caps")["caps"]["smb"])

    def test_password_stdin(self):
        self.assertEqual(self.sh("browse", "annas-macbook.local")["code"], "needs_password")
        r = self.sh("browse", "annas-macbook.local", "--user", "anna", "--password-stdin", stdin="pw\n")
        self.assertEqual(r["shares"], ["Public", "anna"])
        r = self.sh("connect", r"\\annas-macbook.local\anna", "--user", "anna", "--password-stdin", "--remember", stdin="pw\n")
        self.assertTrue(r["ok"] and r["passwordSaved"])
        self.assertEqual(len(self.sh("mounts")["mounts"]), 2)
        self.assertNotIn("pw", [str(v) for v in r.values() if isinstance(v, str)])

    def test_save_cli_and_disconnect(self):
        self.assertEqual(len(self.sh("save", "smb://x/y", "--name", "Why", "--reconnect")["saved"]), 3)
        self.assertEqual(len(self.sh("set-reconnect", "smb://x/y", "off")["saved"]), 3)
        self.assertEqual(len(self.sh("unsave", "smb://x/y")["saved"]), 2)
        self.assertTrue(self.sh("disconnect", "smb://family-nas.local/media")["ok"])
        self.assertEqual(self.sh("mounts")["mounts"], [])

    def test_bad(self):
        self.assertFalse(self.sh("bogus")["ok"])
        self.assertEqual(self.sh("normalize", "not valid")["code"], "bad_address")
        self.assertEqual(self.sh("normalize", r"\\h\s")["uri"], "smb://h/s")


class ErrorMapping(unittest.TestCase):
    def test_map(self):
        self.assertEqual(connect.map_error("PERMISSION_DENIED")[0], "denied")
        self.assertEqual(connect.map_error("HOST_NOT_FOUND")[0], "not_found")
        self.assertEqual(connect.map_error("TIMED_OUT")[0], "timeout")
        self.assertEqual(connect.map_error("WHATEVER")[0], "failed")


if __name__ == "__main__":
    try:
        unittest.main()
    finally:
        subprocess.run(["rm", "-rf", TMP])
