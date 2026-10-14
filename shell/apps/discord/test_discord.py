#!/usr/bin/python3 -I
"""Tests for ultimit-discord (discord.py): accounts, launcher entries, data dirs and the theme,
against a temporary home and a fake flatpak. python3 apps/discord/test_discord.py"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "discord.py")
FAKE = os.path.join(HERE, "fixtures", "fake-flatpak")
APP = "dev.vencord.Vesktop"


class Discord(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.log = os.path.join(self.home, "calls")
        self.var = os.path.join(self.home, ".var/app", APP, "config")
        self.apps = os.path.join(self.home, ".local/share/applications")

    def tearDown(self):
        self.tmp.cleanup()

    def run_(self, *args, installed=True, skin=None):
        env = {k: v for k, v in os.environ.items() if not k.startswith("XDG_") and k != "ULTIMIT_SKIN"}
        env.update(HOME=self.home, ULTIMIT_DISCORD_FLATPAK=FAKE, DISCORD_TEST_LOG=self.log,
                   DISCORD_TEST_INSTALLED="1" if installed else "0")
        if skin:
            env["ULTIMIT_SKIN"] = skin
        p = subprocess.run([sys.executable, "-I", SCRIPT] + list(args), capture_output=True, text=True, env=env)
        return json.loads(p.stdout) if p.stdout.strip() else {"rc": p.returncode}

    def read(self, *parts):
        with open(os.path.join(*parts)) as f:
            return f.read()

    def calls(self):
        try:
            return [l for l in self.read(self.log).splitlines() if not l.startswith("info ")]
        except OSError:
            return []

    def test_setup_three_accounts(self):
        self.assertTrue(self.run_("setup")["ok"])
        accs = self.run_("list")["accounts"]
        self.assertEqual([(a["id"], a["name"]) for a in accs], [("1", "Discord"), ("2", "Discord 2"), ("3", "Discord 3")])
        self.assertEqual(accs[0]["dir"], os.path.join(self.var, "vesktop"))
        self.assertEqual(accs[2]["dir"], os.path.join(self.var, "vesktop-3"))
        # account 1 overrides the Flatpak's entry (and takes discord:// links); the others get their own
        one = self.read(self.apps, APP + ".desktop")
        self.assertIn("Name=Discord\n", one)
        self.assertIn("ultimit-discord open 1 %U", one)
        self.assertIn("MimeType=x-scheme-handler/discord;", one)
        three = self.read(self.apps, "ultimit-discord-3.desktop")
        self.assertIn("Name=Discord 3\n", three)
        self.assertIn("ultimit-discord open 3\n", three)
        self.assertNotIn("MimeType", three)
        # new data dirs: Ultimit frame, no tour, theme on, Rich Presence on account 1 only
        for i, d in (("1", "vesktop"), ("2", "vesktop-2")):
            s = json.loads(self.read(self.var, d, "settings.json"))
            self.assertTrue(s["nativeTitleBar"])
            self.assertEqual(s["arRPC"], i == "1")
            self.assertEqual(json.loads(self.read(self.var, d, "state.json")), {"firstLaunch": False})
            self.assertEqual(json.loads(self.read(self.var, d, "settings", "settings.json"))["enabledThemes"], ["ultimit.css"])
            self.assertIn("@name Ultimit", self.read(self.var, d, "themes", "ultimit.css"))

    def test_existing_settings_kept(self):
        d = os.path.join(self.var, "vesktop")
        os.makedirs(os.path.join(d, "settings"))
        with open(os.path.join(d, "settings.json"), "w") as f:
            f.write('{"nativeTitleBar": false}')
        with open(os.path.join(d, "settings", "settings.json"), "w") as f:
            f.write('{"enabledThemes": []}')
        self.run_("setup")
        self.assertEqual(self.read(d, "settings.json"), '{"nativeTitleBar": false}')
        self.assertEqual(self.read(d, "settings", "settings.json"), '{"enabledThemes": []}')
        self.assertTrue(os.path.exists(os.path.join(d, "themes", "ultimit.css")))   # available to turn on

    def test_not_installed(self):
        self.run_("setup")
        self.assertTrue(os.path.exists(os.path.join(self.apps, "ultimit-discord-2.desktop")))
        r = self.run_("setup", installed=False)
        self.assertFalse(r["installed"])
        self.assertEqual(os.listdir(self.apps), [])   # no entries that would not start
        r = self.run_("open", "2", installed=False)
        self.assertFalse(r["ok"])

    def test_open(self):
        self.run_("setup")
        self.run_("open", "1", "discord://-/channels/1/2")
        self.run_("open", "2", "https://not-a-discord-link")
        self.assertEqual(self.calls(), [
            "run %s discord://-/channels/1/2" % APP,
            "run %s --user-data-dir=%s" % (APP, os.path.join(self.var, "vesktop-2")),
        ])
        self.assertFalse(self.run_("open", "9")["ok"])

    def test_add_rename_remove(self):
        self.run_("setup")
        r = self.run_("add", "Alt", "account")
        self.assertEqual(r, {"ok": True, "id": "4"})
        self.assertIn("Name=Alt account\n", self.read(self.apps, "ultimit-discord-4.desktop"))
        self.assertTrue(os.path.isfile(os.path.join(self.var, "vesktop-4", "themes", "ultimit.css")))
        self.assertEqual(self.run_("add")["id"], "5")
        self.assertTrue(self.run_("rename", "2", "Work")["ok"])
        self.assertIn("Name=Work\n", self.read(self.apps, "ultimit-discord-2.desktop"))
        self.assertFalse(self.run_("rename", "2", "  ")["ok"])
        self.assertFalse(self.run_("remove", "1")["ok"])
        os.symlink("host-123", os.path.join(self.var, "vesktop-3", "SingletonLock"))
        self.assertTrue([a for a in self.run_("list")["accounts"] if a["id"] == "3"][0]["running"])
        self.assertFalse(self.run_("remove", "3")["ok"])
        self.assertTrue(self.run_("remove", "4")["ok"])
        self.assertFalse(os.path.exists(os.path.join(self.apps, "ultimit-discord-4.desktop")))
        self.assertFalse(os.path.exists(os.path.join(self.var, "vesktop-4")))
        self.assertEqual([a["id"] for a in self.run_("list")["accounts"]], ["1", "2", "3", "5"])
        self.assertEqual(self.run_("add")["id"], "6")   # numbers are not reused

    def test_theme_follows_skin(self):
        self.run_("setup", skin="amber")
        css = self.read(self.var, "vesktop-2", "themes", "ultimit.css")
        self.assertIn("Amber", css)
        self.assertIn("--brand-500: #ffb04a", css)
        self.run_("theme", skin="silver")
        css = self.read(self.var, "vesktop-2", "themes", "ultimit.css")
        self.assertIn("--brand-500: #2c5b88", css)
        self.assertNotIn("%(", css)

    def test_users_own_entry_left_alone(self):
        os.makedirs(self.apps)
        with open(os.path.join(self.apps, "ultimit-discord-2.desktop"), "w") as f:
            f.write("[Desktop Entry]\nName=Mine\n")
        self.run_("setup")
        self.assertEqual(self.read(self.apps, "ultimit-discord-2.desktop"), "[Desktop Entry]\nName=Mine\n")


if __name__ == "__main__":
    unittest.main()
