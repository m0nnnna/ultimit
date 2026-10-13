#!/usr/bin/python3 -I
"""Tests for store.py against a tiny fake catalogue: python3 apps/store/test_store.py"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")


class Store(unittest.TestCase):
    def setUp(self):
        self.cache = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.cache.cleanup()

    def run_store(self, *args):
        env = dict(os.environ, STORE_APPSTREAM=os.path.join(FIX, "appstream.xml"), STORE_ICONS=os.path.join(FIX, "icons"),
                   STORE_CACHE=self.cache.name, STORE_FLATPAK=os.path.join(FIX, "fake-flatpak"))
        p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "store.py")] + list(args),
                           capture_output=True, text=True, env=env)
        return json.loads(p.stdout)

    def test_index_skips_runtimes_and_eol(self):
        o = self.run_store("home")
        self.assertTrue(o["ok"])
        self.assertEqual(o["total"], 2)
        self.assertEqual([p["id"] for p in o["picks"]], ["com.discordapp.Discord", "org.gimp.GIMP"])
        self.assertEqual(o["installed"], ["com.discordapp.Discord"])

    def test_app_details(self):
        a = self.run_store("app", "org.gimp.GIMP")["app"]
        self.assertEqual(a["name"], "GNU Image Manipulation Program")      # untranslated name
        self.assertEqual(a["developer"], "The GIMP team")                  # untranslated developer
        self.assertEqual(a["keywords"], ["paint"])
        self.assertEqual(a["description"], "GIMP is a photo retouching program.\n\n• Layers\n• Brushes")
        self.assertTrue(a["verified"] and a["icon"].endswith("org.gimp.GIMP.png"))
        self.assertEqual((a["version"], a["homepage"], a["screenshots"]), ("3.2.6", "https://www.gimp.org/", ["https://example.org/gimp.png"]))
        self.assertFalse(a["installed"])
        d = self.run_store("app", "com.discordapp.Discord")["app"]   # ".desktop" suffix dropped
        self.assertTrue(d["installed"])

    def test_search(self):
        names = lambda o: [a["name"] for a in o["apps"]]
        self.assertEqual(names(self.run_store("search", "photo editor")), ["GNU Image Manipulation Program"])
        self.assertEqual(names(self.run_store("search", "voice")), ["Discord"])
        self.assertEqual(names(self.run_store("search", "", "Graphics")), ["GNU Image Manipulation Program"])
        self.assertEqual(self.run_store("search", "zzzz")["count"], 0)

    def test_cache_reused(self):
        self.run_store("home")
        path = os.path.join(self.cache.name, "index.json")
        before = os.stat(path).st_mtime_ns
        self.run_store("search", "gimp")
        self.assertEqual(os.stat(path).st_mtime_ns, before)


if __name__ == "__main__":
    unittest.main()
