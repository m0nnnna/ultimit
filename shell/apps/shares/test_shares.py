#!/usr/bin/env python3
"""Unit tests for shares.py. Run: python3 apps/shares/test_shares.py
Every external program goes through a fake runner; HOME is a temp dir; nothing touches Samba or the system."""
import importlib.util, json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TMP = tempfile.mkdtemp(prefix="shares-test-")
HOME = os.path.join(TMP, "home")
os.makedirs(HOME)
os.environ.update({"HOME": HOME, "XDG_STATE_HOME": HOME + "/.local/state"})
for k in ("SHARES_FAKE", "SHARES_BIN_DIR"):
    os.environ.pop(k, None)
os.environ["SHARES_ETC_GROUP"] = TMP + "/etc_group"
os.environ["SHARES_UFW_APPS"] = TMP + "/ufw-apps"
spec = importlib.util.spec_from_file_location("shares", os.path.join(HERE, "shares.py"))
shares = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shares)

INFO = """[public]
path=/home/u/Public
comment=Family photos
usershare_acl=Everyone:R,
guest_ok=n

[music]
path=/home/u/Music
comment=
usershare_acl=Everyone:F,
guest_ok=y

"""
IP_ADDR = [
    {"ifname": "lo", "flags": ["LOOPBACK", "UP"], "addr_info": [{"family": "inet", "local": "127.0.0.1", "prefixlen": 8, "scope": "host"}]},
    {"ifname": "docker0", "flags": ["UP"], "operstate": "UP", "addr_info": [{"family": "inet", "local": "172.17.0.1", "prefixlen": 16, "scope": "global"}]},
    {"ifname": "eth0", "flags": ["UP"], "operstate": "UP", "addr_info": [
        {"family": "inet6", "local": "fe80::1", "prefixlen": 64, "scope": "link"},
        {"family": "inet", "local": "10.0.5.23", "prefixlen": 22, "scope": "global"}]},
    {"ifname": "wlan0", "flags": ["UP"], "operstate": "UP", "addr_info": [{"family": "inet", "local": "192.168.1.42", "prefixlen": 24, "scope": "global"}]},
    {"ifname": "wlan1", "flags": [], "operstate": "DOWN", "addr_info": []},
]


def write(path, text):
    with open(path, "w") as f:
        f.write(text)


class Fake:
    """Records argv and answers like the real programs; `answers` maps a command prefix to (rc, out, err)."""
    def __init__(self, answers=None):
        self.calls, self.inputs = [], []
        self.answers = {
            ("net", "usershare", "info", "--long"): (0, INFO, ""),
            ("systemctl", "is-active", "smbd"): (0, "active\n", ""),
            ("systemctl", "is-active", "ufw"): (3, "inactive\n", ""),
            ("testparm", "-s", "--parameter-name=usershare path"): (0, TMP + "/usershares\n", ""),
            ("testparm", "-s", "--parameter-name=usershare max shares"): (0, "100\n", ""),
            ("testparm", "-s", "--parameter-name=usershare allow guests"): (0, "yes\n", ""),
            ("id", "-nG"): (0, "mino adm sambashare\n", ""),
            ("hostname",): (0, "ultimit-box\n", ""),
            ("ip", "-j", "addr"): (0, json.dumps(IP_ADDR), ""),
            ("ip", "-j", "route"): (0, json.dumps([{"dst": "default", "dev": "wlan0"}]), ""),
        }
        self.answers.update(answers or {})

    def __call__(self, argv, input_text=None, timeout=15):
        self.calls.append(list(argv))
        self.inputs.append(input_text)
        for n in range(len(argv), 0, -1):
            r = self.answers.get(tuple(argv[:n]))
            if r:
                return r
        return 0, "", ""


def use(fake):
    shares.runner = fake
    return fake


class Base(unittest.TestCase):
    def setUp(self):
        for d in (TMP + "/usershares",):
            os.makedirs(d, exist_ok=True)
        for f in (TMP + "/etc_group",):
            if os.path.exists(f):
                os.remove(f)
        subprocess.run(["rm", "-rf", HOME + "/.local"])
        self.fake = use(Fake())
        self.dir = os.path.join(HOME, "Docs")
        os.makedirs(self.dir, exist_ok=True)

    def tearDown(self):
        shares.runner = shares.default_runner


class Names(Base):
    def test_valid(self):
        for n in ("Photos", "my share", "a" * 80, "Музыка", "x.y-z_1"):
            self.assertIsNone(shares.validate_name(n), n)

    def test_invalid(self):
        for n in ("", "  ", " lead", "trail ", "a" * 81, "a/b", "a\\b", "a[b]", "a:b", "a|b", "a<b", "a>b", "a+b", "a=b",
                  "a;b", "a,b", "a*b", "a?b", 'a"b', "100%", "hidden$", "tab\tname", ".dot"):
            self.assertIsNotNone(shares.validate_name(n), repr(n))

    def test_reserved(self):
        for n in ("global", "Global", "HOMES", "printers", "IPC$", "print$"):
            self.assertIsNotNone(shares.validate_name(n), n)

    def test_sanitize_and_suggest(self):
        self.assertEqual(shares.sanitize_name("My: Photos/2024"), "My- Photos-2024")
        self.assertEqual(shares.sanitize_name("global"), "global share")
        self.assertEqual(shares.sanitize_name("///"), "share")
        self.assertIsNone(shares.validate_name(shares.sanitize_name("a<b>c$")))
        self.assertEqual(shares.suggest_name(self.dir), "Docs")
        self.assertEqual(shares.suggest_name(HOME), "home")
        self.assertEqual(shares.suggest_name("/"), "share")


class Paths(Base):
    def test_missing_file_and_dir(self):
        self.assertIn("does not exist", shares.inspect_path(self.dir + "/nope")[1])
        f = os.path.join(self.dir, "f.txt")
        open(f, "w").close()
        self.assertIn("only folders", shares.inspect_path(f)[1])
        self.assertIsNone(shares.inspect_path(self.dir)[1])
        self.assertIn("Choose a folder", shares.inspect_path("  ")[1])

    def test_forbidden(self):
        for p in ("/", "/etc", "/usr", "/var", "/proc", "/root"):
            self.assertIsNotNone(shares.inspect_path(p)[1], p)

    def test_forbidden_via_symlink(self):
        ln = os.path.join(self.dir, "etc-link")
        if not os.path.islink(ln):
            os.symlink("/etc", ln)
        self.assertIsNotNone(shares.inspect_path(ln)[1])

    def test_sensitive(self):
        os.makedirs(HOME + "/.ssh", exist_ok=True)
        os.makedirs(HOME + "/.ssh/sub", exist_ok=True)
        self.assertIn("private", shares.inspect_path(HOME + "/.ssh")[1])
        self.assertIn("private", shares.inspect_path(HOME + "/.ssh/sub")[1])

    def test_home_is_wide_warning(self):
        p, err, warns = shares.inspect_path(HOME)
        self.assertIsNone(err)
        self.assertEqual([w["code"] for w in warns], ["wide"])
        self.assertEqual(shares.inspect_path(self.dir)[2], [])

    def test_tilde(self):
        self.assertEqual(shares.inspect_path("~/Docs")[0], self.dir)

    def test_unreadable(self):
        d = os.path.join(HOME, "locked")
        os.makedirs(d, exist_ok=True)
        os.chmod(d, 0)
        try:
            if os.access(d, os.R_OK):
                self.skipTest("running as root")
            self.assertIn("permission", shares.inspect_path(d)[1])
        finally:
            os.chmod(d, 0o700)


class Parse(Base):
    def test_info(self):
        got = shares.parse_usershares(INFO)
        self.assertEqual([s["name"] for s in got], ["public", "music"])
        self.assertEqual(got[0], {"name": "public", "path": "/home/u/Public", "comment": "Family photos",
                                  "acl": "Everyone:R,", "guest": False, "writable": False})
        self.assertTrue(got[1]["writable"] and got[1]["guest"])
        self.assertEqual(got[1]["comment"], "")

    def test_empty_and_noise(self):
        self.assertEqual(shares.parse_usershares(""), [])
        self.assertEqual(shares.parse_usershares("garbage\nkey=value\n"), [])

    def test_path_with_equals_and_user_acl(self):
        got = shares.parse_usershares("[x]\npath=/a=b/c\ncomment=a=b\nusershare_acl=ACME\\bob:F,Everyone:R,\nguest_ok=n\n")
        self.assertEqual(got[0]["path"], "/a=b/c")
        self.assertEqual(got[0]["comment"], "a=b")
        self.assertTrue(got[0]["writable"])

    def test_crlf(self):
        got = shares.parse_usershares("[x]\r\npath=/p\r\nusershare_acl=Everyone:R,\r\nguest_ok=y\r\n")
        self.assertEqual((got[0]["path"], got[0]["guest"]), ("/p", True))

    def test_list_command_and_errors(self):
        self.assertEqual(len(shares.list_shares()["shares"]), 2)
        self.assertEqual(self.fake.calls[-1], ["net", "usershare", "info", "--long"])
        use(Fake({("net", "usershare", "info", "--long"): (255, "", "net usershare: usershares are currently disabled\n")}))
        r = shares.list_shares()
        self.assertFalse(r["ok"])
        self.assertIn("disabled", r["err"])
        use(Fake({("net", "usershare", "info", "--long"): (127, "", "net: not found")}))
        self.assertEqual(shares.list_shares()["shares"], [])


class Status(Base):
    def test_all_good(self):
        shares.write_marker(shares.pw_marker())
        s = shares.status()
        self.assertEqual(s["host"], "ultimit-box")
        self.assertEqual(s["hostUpper"], "ULTIMIT-BOX")
        self.assertTrue(s["active"])
        self.assertTrue(s["usershare"]["enabled"])
        self.assertEqual(s["usershare"]["max"], 100)
        self.assertTrue(s["usershare"]["dir"]["ok"])
        self.assertTrue(s["usershare"]["guests"])
        self.assertTrue(s["group"]["member"])
        self.assertFalse(s["group"]["reloginNeeded"])
        self.assertEqual(s["password"], "set")
        self.assertEqual(s["firewall"]["state"], "inactive")

    def test_addresses(self):
        a = shares.status()["addresses"]
        self.assertEqual([x["ip"] for x in a], ["192.168.1.42", "10.0.5.23"])     # docker0/lo skipped, default route first
        self.assertEqual(a[0]["subnet"], "192.168.1.0/24")
        self.assertEqual(a[1]["subnet"], "10.0.4.0/22")
        self.assertTrue(a[0]["primary"] and not a[1]["primary"])

    def test_relogin_needed(self):
        write(TMP + "/etc_group", "adm:x:4:mino\nsambashare:x:123:mino,other\n")
        use(Fake({("id", "-nG"): (0, "mino adm\n", "")}))
        g = shares.status()["group"]
        self.assertTrue(g["reloginNeeded"] and not g["member"] and g["inFile"])
        self.assertFalse(shares.status()["ready"])

    def test_not_in_group_at_all(self):
        write(TMP + "/etc_group", "sambashare:x:123:\n")
        use(Fake({("id", "-nG"): (0, "mino adm\n", "")}))
        g = shares.status()["group"]
        self.assertEqual((g["exists"], g["inFile"], g["reloginNeeded"], g["member"]), (True, False, False, False))

    def test_usershares_disabled(self):
        use(Fake({("testparm", "-s", "--parameter-name=usershare max shares"): (0, "0\n", "")}))
        self.assertFalse(shares.status()["usershare"]["enabled"])
        use(Fake({("testparm", "-s", "--parameter-name=usershare path"): (0, "\n", "")}))
        self.assertFalse(shares.status()["usershare"]["enabled"])

    def test_dir_missing(self):
        use(Fake({("testparm", "-s", "--parameter-name=usershare path"): (0, TMP + "/nope\n", "")}))
        d = shares.status()["usershare"]["dir"]
        self.assertFalse(d["exists"] or d["ok"])

    def test_service_inactive(self):
        use(Fake({("systemctl", "is-active", "smbd"): (3, "inactive\n", "")}))
        self.assertFalse(shares.status()["active"])

    def test_password_marker(self):
        self.assertEqual(shares.status()["password"], "unknown")

    def test_firewall_states(self):
        act = {("systemctl", "is-active", "ufw"): (0, "active\n", "")}
        use(Fake(act | {("ufw", "status"): (1, "", "ERROR: You need to be root")}))
        self.assertEqual(shares.status()["firewall"]["state"], "unknown")
        shares.write_marker(shares.fw_marker(), "192.168.1.0/24")
        f = shares.status()["firewall"]
        self.assertEqual((f["state"], f["subnet"]), ("allowed", "192.168.1.0/24"))
        use(Fake(act | {("ufw", "status"): (0, "Status: active\n\nTo   Action  From\n--   ------  ----\nSamba  ALLOW  192.168.1.0/24\n", "")}))
        self.assertEqual(shares.status()["firewall"]["state"], "allowed")
        use(Fake(act | {("ufw", "status"): (0, "Status: active\n\nTo   Action  From\n22/tcp  ALLOW  Anywhere\n", "")}))
        self.assertEqual(shares.status()["firewall"]["state"], "blocked")
        use(Fake({("systemctl", "is-active", "ufw"): (127, "", "not found")}))
        self.assertEqual(shares.status()["firewall"]["state"], "none")

    def test_ufw_profile(self):
        self.assertFalse(shares.ufw_has_samba_profile())
        os.makedirs(TMP + "/ufw-apps", exist_ok=True)
        write(TMP + "/ufw-apps/samba", "[Samba]\ntitle=SMB\nports=139,445/tcp\n")
        self.assertTrue(shares.ufw_has_samba_profile())
        os.remove(TMP + "/ufw-apps/samba")

    def test_smbd_missing_means_not_installed(self):
        self.assertEqual(shares.smbd_present(), os.path.exists("/usr/sbin/smbd"))


class AddRemove(Base):
    def add_call(self):
        return [c for c in self.fake.calls if c[:3] == ["net", "usershare", "add"]]

    def test_add_readonly(self):
        r = shares.add("Docs", self.dir)
        self.assertTrue(r["ok"], r)
        self.assertEqual(self.add_call(), [["net", "usershare", "add", "Docs", self.dir, "", "Everyone:R", "guest_ok=n"]])

    def test_add_writable_guest_comment(self):
        os.chmod(self.dir, 0o777)
        r = shares.add("Docs", self.dir, writable=True, guest=True, comment="line1\nline2")
        self.assertTrue(r["ok"], r)
        self.assertEqual(self.add_call()[0], ["net", "usershare", "add", "Docs", self.dir, "line1 line2", "Everyone:F", "guest_ok=y"])
        self.assertEqual([w["code"] for w in r["warnings"]], ["guest"])

    def test_guest_writable_warns_about_perms(self):
        os.chmod(self.dir, 0o755)
        r = shares.check("Docs", self.dir, writable=True, guest=True)
        codes = [w["code"] for w in r["warnings"]]
        self.assertIn("guest_perms", codes)
        self.assertEqual([w for w in r["warnings"] if w["code"] == "guest_perms"][0]["fix"], "chmod-ow")
        os.chmod(self.dir, 0o757)
        self.assertNotIn("guest_perms", [w["code"] for w in shares.check("Docs", self.dir, True, True)["warnings"]])
        self.assertNotIn("guest_perms", [w["code"] for w in shares.check("Docs", self.dir, False, True)["warnings"]])

    def test_chmod_ow(self):
        os.chmod(self.dir, 0o755)
        self.assertTrue(shares.chmod_ow(self.dir)["ok"])
        self.assertEqual(os.stat(self.dir).st_mode & 0o777, 0o757)
        self.assertFalse(shares.chmod_ow("/etc")["ok"])

    def test_invalid_does_not_call_net(self):
        r = shares.add("a/b", self.dir)
        self.assertFalse(r["ok"])
        self.assertIn("name", r["errors"])
        r = shares.add("ok", self.dir + "/missing")
        self.assertIn("path", r["errors"])
        self.assertEqual(self.add_call(), [])

    def test_duplicate_name_case_insensitive(self):
        r = shares.add("PUBLIC", self.dir)
        self.assertFalse(r["ok"])
        self.assertIn("already exists", r["error"])
        self.assertEqual(self.add_call(), [])

    def test_duplicate_path_warns(self):
        use(Fake({("net", "usershare", "info", "--long"): (0, "[old]\npath=%s\ncomment=\nusershare_acl=Everyone:R,\nguest_ok=n\n" % self.dir, "")}))
        r = shares.check("new", self.dir)
        self.assertTrue(r["ok"])
        self.assertIn("dup_path", [w["code"] for w in r["warnings"]])

    def test_samba_error_surfaced(self):
        use(Fake({("net", "usershare", "add"): (255, "", "net usershare add: cannot share path /x as we are not the owner.\n")}))
        r = shares.add("Docs", self.dir)
        self.assertFalse(r["ok"])
        self.assertIn("not the owner", r["error"])

    def test_samba_missing(self):
        use(Fake({("net", "usershare", "add"): (127, "", "net: not found")}))
        self.assertEqual(shares.add("Docs", self.dir)["error"], "Samba is not installed.")

    def test_home_gets_wide_warning(self):
        r = shares.add("home", HOME)
        self.assertTrue(r["ok"])
        self.assertIn("wide", [w["code"] for w in r["warnings"]])

    def test_remove(self):
        self.assertTrue(shares.remove("public")["ok"])
        self.assertIn(["net", "usershare", "delete", "public"], self.fake.calls)
        use(Fake({("net", "usershare", "delete"): (255, "", "net usershare delete: usershare nope does not exist.\n")}))
        r = shares.remove("nope")
        self.assertFalse(r["ok"])
        self.assertIn("does not exist", r["error"])
        self.assertFalse(shares.remove("")["ok"])


class Setup(Base):
    def test_commands(self):
        c = shares.setup_commands()
        self.assertEqual(c["subnet"], "192.168.1.0/24")
        steps = {s["id"]: s for s in c["steps"]}
        self.assertEqual(steps["install"]["argv"][0], ["pkexec", "env", "DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y", "samba"])
        self.assertEqual(steps["group"]["argv"][0][:4], ["pkexec", "usermod", "-aG", "sambashare"])
        self.assertEqual(steps["password"]["argv"][0][:4], ["pkexec", "smbpasswd", "-a", "-s"])
        self.assertNotIn("password", " ".join(steps["password"]["argv"][0]))
        self.assertEqual(steps["firewall-allow"]["argv"][0][:5], ["pkexec", "ufw", "allow", "from", "192.168.1.0/24"])
        self.assertIn("Ultimit SHARES", steps["firewall-allow"]["display"])

    def test_firewall_argvs(self):
        self.assertEqual(shares.firewall_argvs("10.0.0.0/24", True, True),
                         [["pkexec", "ufw", "allow", "from", "10.0.0.0/24", "to", "any", "app", "Samba", "comment", "Ultimit SHARES"]])
        self.assertEqual(shares.firewall_argvs("10.0.0.0/24", False, True),
                         [["pkexec", "ufw", "delete", "allow", "from", "10.0.0.0/24", "to", "any", "app", "Samba"]])
        ports = shares.firewall_argvs("10.0.0.0/24", True, False)
        self.assertEqual(len(ports), 2)
        self.assertIn("139,445", ports[0])
        self.assertIn("udp", ports[1])

    def test_subnet_validation(self):
        self.assertEqual(shares.valid_subnet("192.168.1.0/24"), "192.168.1.0/24")
        self.assertEqual(shares.valid_subnet("192.168.1.42/24"), "192.168.1.0/24")
        for bad in ("0.0.0.0/0", "8.8.8.0/24", "foo", "192.168.1.0/24; rm -rf /", "10.0.0.0/4", "fe80::/64"):
            self.assertIsNone(shares.valid_subnet(bad), bad)

    def test_install_and_service_group(self):
        self.assertTrue(shares.setup("install")["ok"])
        self.assertEqual(self.fake.calls[-1], ["pkexec", "env", "DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y", "samba"])
        shares.setup("service")
        self.assertEqual(self.fake.calls[-1], ["pkexec", "systemctl", "enable", "--now", "smbd"])
        r = shares.setup("group")
        self.assertTrue(r["reloginNeeded"])
        self.assertEqual(self.fake.calls[-1], ["pkexec", "usermod", "-aG", "sambashare", shares.username()])

    def test_password_via_stdin_only(self):
        r = shares.setup("password", password="s3cret pass")
        self.assertTrue(r["ok"], r)
        call = self.fake.calls[-1]
        self.assertEqual(call, ["pkexec", "smbpasswd", "-a", "-s", shares.username()])
        self.assertNotIn("s3cret", " ".join(call))
        self.assertEqual(self.fake.inputs[-1], "s3cret pass\ns3cret pass\n")
        self.assertNotIn("s3cret", json.dumps(r))
        self.assertTrue(os.path.exists(shares.pw_marker()))

    def test_password_rejects_empty_and_newlines(self):
        for pw in ("", None, "a\nb"):
            self.assertFalse(shares.setup("password", password=pw)["ok"])
        self.assertFalse(os.path.exists(shares.pw_marker()))

    def test_password_failure_keeps_marker_absent(self):
        use(Fake({("pkexec", "smbpasswd"): (1, "", "Failed to add entry for user mino.\n")}))
        r = shares.setup("password", password="x")
        self.assertFalse(r["ok"] or r["cancelled"])
        self.assertIn("Failed to add", r["error"])
        self.assertFalse(os.path.exists(shares.pw_marker()))

    def test_cancelled_is_calm(self):
        use(Fake({("pkexec",): (126, "", "Error executing command as another user: Request dismissed\n")}))
        r = shares.setup("group")
        self.assertEqual((r["ok"], r["cancelled"]), (False, True))
        self.assertNotIn("reloginNeeded", r)
        use(Fake({("pkexec",): (127, "", "Error executing command as another user: Not authorized\n")}))
        self.assertTrue(shares.setup("install")["cancelled"])
        r = shares.setup("password", password="x")
        self.assertTrue(r["cancelled"])
        self.assertFalse(os.path.exists(shares.pw_marker()))

    def test_firewall_allow_block_markers(self):
        r = shares.setup("firewall-allow", subnet="192.168.1.0/24")
        self.assertTrue(r["ok"])
        self.assertEqual(shares.read_marker(shares.fw_marker()), "192.168.1.0/24")
        self.assertEqual(self.fake.calls[-1][:3], ["pkexec", "ufw", "allow"])
        shares.setup("firewall-block", subnet="192.168.1.0/24")
        self.assertEqual(self.fake.calls[-1][:4], ["pkexec", "ufw", "delete", "allow"])
        self.assertIsNone(shares.read_marker(shares.fw_marker()))

    def test_firewall_refuses_public_ranges(self):
        n = len(self.fake.calls)
        self.assertFalse(shares.setup("firewall-allow", subnet="0.0.0.0/0")["ok"])
        self.assertFalse(shares.setup("firewall-allow", subnet="x; reboot")["ok"])
        self.assertEqual(len(self.fake.calls), n)

    def test_firewall_cancel_leaves_no_marker(self):
        use(Fake({("pkexec",): (126, "", "Request dismissed\n")}))
        self.assertTrue(shares.setup("firewall-allow", subnet="192.168.1.0/24")["cancelled"])
        self.assertIsNone(shares.read_marker(shares.fw_marker()))

    def test_mark(self):
        self.assertTrue(shares.mark("password")["ok"])
        self.assertEqual(shares.status()["password"], "set")
        self.assertTrue(shares.mark("firewall", "192.168.1.9/24")["ok"])
        self.assertEqual(shares.read_marker(shares.fw_marker()), "192.168.1.0/24")
        self.assertFalse(shares.mark("x")["ok"])

    def test_unknown_step(self):
        self.assertFalse(shares.setup("rm -rf")["ok"])


class Cli(unittest.TestCase):
    """End to end through the fixtures/bin fake programs (SHARES_FAKE=1)."""
    def setUp(self):
        self.state = os.path.join(TMP, "fake-state")
        subprocess.run(["sh", os.path.join(HERE, "fixtures", "make-state.sh"), self.state, "ready"], check=True)
        self.env = dict(os.environ, SHARES_FAKE="1", SHARES_FAKE_STATE=self.state, HOME=self.state + "/home",
                        XDG_STATE_HOME="", SHARES_FAKE_DELAY="0")
        self.env.pop("SHARES_ETC_GROUP", None)
        self.env.pop("SHARES_UFW_APPS", None)

    def sh(self, *args, stdin=None):
        p = subprocess.run([sys.executable, os.path.join(HERE, "shares.py")] + list(args), env=self.env,
                           input=stdin, capture_output=True, text=True)
        return json.loads(p.stdout)

    def test_state(self):
        s = self.sh("state")
        self.assertTrue(s["status"]["ready"])
        self.assertEqual([x["name"] for x in s["shares"]["shares"]], ["music", "public"])

    def test_add_then_remove(self):
        d = self.state + "/home/New"
        os.makedirs(d)
        self.assertTrue(self.sh("add", "New Stuff", d, "--writable", "--comment", "hi")["ok"])
        got = {x["name"]: x for x in self.sh("list")["shares"]}
        self.assertEqual((got["new stuff"]["writable"], got["new stuff"]["comment"]), (True, "hi"))
        self.assertTrue(self.sh("remove", "New Stuff")["ok"])
        self.assertNotIn("new stuff", [x["name"] for x in self.sh("list")["shares"]])

    def test_setup_flow_fresh(self):
        subprocess.run(["sh", os.path.join(HERE, "fixtures", "make-state.sh"), self.state, "fresh"], check=True)
        self.assertFalse(self.sh("status")["installed"])
        self.assertTrue(self.sh("setup", "install")["ok"])
        self.assertTrue(self.sh("setup", "group")["reloginNeeded"])
        st = self.sh("status")
        self.assertTrue(st["installed"] and st["active"] and st["group"]["reloginNeeded"] and not st["ready"])
        self.assertTrue(self.sh("setup", "password", stdin="pw\n")["ok"])
        self.assertEqual(self.sh("status")["password"], "set")

    def test_cancel(self):
        self.env["SHARES_FAKE_CANCEL"] = "1"
        r = self.sh("setup", "group")
        self.assertEqual((r["ok"], r["cancelled"]), (False, True))

    def test_cli_errors_are_json(self):
        self.assertFalse(self.sh("bogus")["ok"])
        self.assertFalse(self.sh("add", "x")["ok"])


if __name__ == "__main__":
    try:
        unittest.main()
    finally:
        subprocess.run(["rm", "-rf", TMP])
