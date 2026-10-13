#!/usr/bin/python3 -I
"""Tests for clip.py (clipboard history) with fake wl-paste/wl-copy: python3 apps/clipboard/test_clip.py"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


class Clip(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.env = dict(os.environ, CLIP_DIR=self.tmp.name, XDG_SESSION_ID="s1",
                        CLIP_WL_PASTE=os.path.join(HERE, "fixtures/fake-wl-paste"),
                        CLIP_WL_COPY=os.path.join(HERE, "fixtures/fake-wl-copy"))

    def tearDown(self):
        self.tmp.cleanup()

    def clip(self, *args, **env):
        e = dict(self.env, **env)
        p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "clip.py")] + list(args),
                           capture_output=True, text=True, env=e, input="")
        return json.loads(p.stdout) if p.stdout else None

    def copy_text(self, text, types="text/plain;charset=utf-8 TEXT", **env):
        self.clip("add", CLIP_FAKE_TYPES=types, CLIP_FAKE_DATA=text, **env)

    def items(self):
        return self.clip("list")["items"]

    def test_text_newest_first_and_dedup(self):
        for t in ("one", "two", "one"):
            self.copy_text(t)
        self.assertEqual([i["text"] for i in self.items()], ["one", "two"])

    def test_secrets_and_blank_skipped(self):
        self.copy_text("hunter2", CLIPBOARD_STATE="sensitive")
        self.copy_text("hunter3", types="text/plain x-kde-passwordManagerHint")
        self.copy_text("   ")
        self.assertEqual(self.items(), [])

    def test_keep_limit_spares_pinned(self):
        self.copy_text("keep me")
        self.clip("pin", self.items()[0]["id"], "on")
        for n in range(55):
            self.copy_text("item %d" % n)
        its = self.items()
        self.assertEqual(len([i for i in its if not i.get("pinned")]), 50)
        self.assertIn("keep me", [i["text"] for i in its])

    def test_long_text_kept_whole(self):
        long = "x" * 5000
        self.copy_text(long)
        it = self.items()[0]
        self.assertEqual(len(it["text"]), 4000)
        self.clip("copy", it["id"])
        with open(os.path.join(self.tmp.name, "copied")) as f:
            self.assertEqual(f.read(), long)

    def test_copy_pin_delete_clear_and_new_login(self):
        self.copy_text("a")
        self.copy_text("b")
        a = [i for i in self.items() if i["text"] == "a"][0]
        self.assertTrue(self.clip("copy", a["id"])["ok"])
        self.assertEqual(self.items()[0]["text"], "a")          # moved to the top
        self.clip("pin", a["id"], "on")
        self.clip("clear")
        self.assertEqual([i["text"] for i in self.items()], ["a"])
        self.copy_text("c")
        self.clip("list", XDG_SESSION_ID="s2")                   # list alone doesn't reset
        subprocess.run([sys.executable, "-I", os.path.join(HERE, "clip.py"), "watch"],   # wl-paste: `true`
                           env=dict(self.env, XDG_SESSION_ID="s2", CLIP_WL_PASTE="true"), timeout=10)
        self.assertEqual([i["text"] for i in self.items()], ["a"])  # a new login keeps only pinned
        self.clip("delete", a["id"])
        self.assertEqual(self.items(), [])


if __name__ == "__main__":
    unittest.main()
