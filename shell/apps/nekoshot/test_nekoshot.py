#!/usr/bin/env python3
"""Tests for nekoshot.py (run: python3 apps/nekoshot/test_nekoshot.py)."""
import io, json, os, sys, tempfile, unittest, contextlib

os.environ["HOME"] = tempfile.mkdtemp()
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import nekoshot as n


def call(*argv):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        n.main(list(argv))
    return json.loads(buf.getvalue())


class T(unittest.TestCase):
    def setUp(self):
        for p in (n.SETTINGS, n.PASSFILE):
            if os.path.exists(p): os.remove(p)
        self.calls = []
        n.runner = lambda argv, timeout=60: (self.calls.append(argv) or (0, "{}", ""))

    def test_set_validates(self):
        self.assertTrue(call("set", "keep", "5")["ok"])
        self.assertFalse(call("set", "keep", "0")["ok"])
        self.assertFalse(call("set", "output_dir", "relative")["ok"])
        self.assertFalse(call("set", "output_dir", "/a/../b")["ok"])
        self.assertFalse(call("set", "output_dir", "/a b")["ok"])
        self.assertFalse(call("set", "bogus", "1")["ok"])
        self.assertEqual(n.load_settings()["keep"], 5)

    def test_passphrase_private(self):
        o = call("passphrase", "--generate")
        self.assertTrue(o["exists"] and len(o["passphrase"]) >= 24)
        self.assertEqual(os.stat(n.PASSFILE).st_mode & 0o777, 0o600)
        self.assertEqual(call("passphrase", "--generate")["passphrase"], o["passphrase"])  # never overwritten

    def test_backup_needs_passphrase_when_encrypting(self):
        call("set", "encrypt", "on")
        self.assertFalse(call("backup")["ok"])
        self.assertEqual(self.calls, [])

    def test_backup_uses_pkexec_helper(self):
        call("backup")
        argv = self.calls[0]
        self.assertEqual(argv[:2], ["pkexec", n.HELPER])
        self.assertIn("--profile", argv)

    def test_cancelled(self):
        n.runner = lambda argv, timeout=60: (126, "", "")
        self.assertTrue(call("backup").get("cancelled"))

    def test_schedule_rejects_junk(self):
        self.assertFalse(call("schedule-add", "ultimit-backup", "0 2 * * * ; rm -rf /")["ok"])
        self.assertFalse(call("schedule-add", "other", "0 2 * * *")["ok"])
        self.assertEqual(self.calls, [])

    def test_verify_only_known_snapshots(self):
        n.cli_json = lambda a: [{"path": "/b/x.tar.zst"}] if a[0] == "list" else {"verified": True}
        self.assertFalse(call("verify", "/etc/shadow")["ok"])
        self.assertTrue(call("verify", "/b/x.tar.zst")["ok"])

    def test_recovery_mentions_passphrase_when_encrypted(self):
        call("set", "encrypt", "on")
        self.assertTrue(call("recovery")["passphrase_file"])


if __name__ == "__main__":
    unittest.main()
