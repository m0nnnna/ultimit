#!/usr/bin/python3 -I
"""Tests for Settings > Users: users.py (own password through passwd) and the root helper's checks,
run as a normal user against fake account tools. python3 apps/settings/test_users.py"""
import json
import os
import pwd
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
HELPER = os.path.normpath(os.path.join(HERE, "../../../distro/system/usr/libexec/ultimit/users-helper"))
FIX = os.path.join(HERE, "fixtures")
ME = pwd.getpwuid(os.getuid()).pw_name


class Users(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.log = os.path.join(self.tmp.name, "calls")
        self.tools = {}
        for n in ("useradd", "usermod", "userdel", "chpasswd", "gpasswd"):   # same script under each name
            path = os.path.join(self.tmp.name, n)
            os.symlink(os.path.join(FIX, "fake-account-tool"), path)
            self.tools["USERS_" + n.upper()] = path

    def tearDown(self):
        self.tmp.cleanup()

    def helper(self, *args, stdin="", **env):
        e = dict(os.environ, USERS_TEST_LOG=self.log, **self.tools, **env)
        p = subprocess.run([sys.executable, "-I", HELPER] + list(args), input=stdin, capture_output=True, text=True, env=e)
        return json.loads(p.stdout)

    def calls(self):
        try:
            with open(self.log) as f:
                return f.read()
        except OSError:
            return ""

    def test_create(self):
        self.assertTrue(self.helper("create", "alex", "Alex Doe", "admin", stdin="secret123\n")["ok"])
        c = self.calls()
        self.assertIn("useradd --create-home --shell /bin/bash --comment Alex Doe alex", c)
        self.assertIn("chpasswd \nalex:secret123", c)
        self.assertIn("usermod --append --groups sudo alex", c)

    def test_refusals(self):
        self.assertFalse(self.helper("create", "Bad.Name", "X", "standard", stdin="secret123\n")["ok"])
        self.assertFalse(self.helper("create", "alex", "A:B", "standard", stdin="secret123\n")["ok"])
        self.assertFalse(self.helper("create", "alex", "Alex", "standard", stdin="\n")["ok"])
        self.assertFalse(self.helper("create", ME, "Me", "standard", stdin="secret123\n")["ok"])   # exists
        self.assertFalse(self.helper("delete", "root", "keep")["ok"])                            # not a person
        self.assertFalse(self.helper("password", "root", stdin="x\n")["ok"])
        self.assertFalse(self.helper("delete", ME, "keep", PKEXEC_UID=str(os.getuid()))["ok"])   # yourself
        self.assertFalse(self.helper("admin", ME, "off", PKEXEC_UID=str(os.getuid()))["ok"])
        self.assertEqual(self.calls(), "")   # nothing ran

    def test_own_password(self):
        def mine(stdin):
            p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "users.py"), "mypassword"], input=stdin,
                               capture_output=True, text=True, env=dict(os.environ, USERS_PASSWD=os.path.join(FIX, "fake-passwd")))
            return json.loads(p.stdout)
        self.assertTrue(mine("old1\nnewpassword1\n")["ok"])
        self.assertEqual(mine("wrong\nnewpassword1\n")["error"], "The current password isn't right.")
        self.assertIn("shorter than 8", mine("old1\nshort\n")["error"])

    def test_list(self):
        p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "users.py"), "list"], capture_output=True, text=True)
        o = json.loads(p.stdout)
        self.assertTrue(o["users"][0]["you"])


if __name__ == "__main__":
    unittest.main()
