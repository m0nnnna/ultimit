#!/usr/bin/python3 -I
"""Tests for image.py (IMAGE's file helper): python3 apps/image/test_image.py"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


class ImageHelper(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = os.path.join(self.tmp.name, "pics")
        os.mkdir(self.d)
        for n in ("img10.png", "img2.JPG", "img1.webp", "notes.txt", ".hidden.png", "Anim.gif"):
            with open(os.path.join(self.d, n), "wb") as f:
                f.write(b"x")
        os.mkdir(os.path.join(self.d, "folder.png"))
        self.env = dict(os.environ, XDG_DATA_HOME=os.path.join(self.tmp.name, "share"))

    def tearDown(self):
        self.tmp.cleanup()

    def run_helper(self, *args):
        p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "image.py")] + list(args),
                           capture_output=True, text=True, env=self.env)
        return json.loads(p.stdout)

    def p(self, n):
        return os.path.join(self.d, n)

    def test_list_natural_order_images_only(self):
        o = self.run_helper("list", self.p("img2.JPG"))
        self.assertTrue(o["ok"])
        self.assertEqual([f["n"] for f in o["files"]], ["Anim.gif", "img1.webp", "img2.JPG", "img10.png"])
        self.assertEqual(o["index"], 2)
        self.assertEqual(o["dir"], self.d)

    def test_hidden_file_shows_hidden_siblings(self):
        o = self.run_helper("list", self.p(".hidden.png"))
        self.assertIn(".hidden.png", [f["n"] for f in o["files"]])
        self.assertEqual(o["files"][o["index"]]["n"], ".hidden.png")

    def test_unknown_extension_still_opens(self):
        o = self.run_helper("list", self.p("notes.txt"))
        self.assertEqual(o["files"][o["index"]]["n"], "notes.txt")

    def test_missing_file(self):
        for p in (self.p("gone.png"), os.path.join(self.tmp.name, "nowhere", "x.png"), self.p("folder.png")):
            o = self.run_helper("list", p)
            self.assertFalse(o["ok"])
            self.assertEqual(o["files"], [])
            self.assertTrue(o["err"])

    def test_set_keeps_order_and_drops_missing(self):
        o = self.run_helper("set", self.p("img10.png"), self.p("gone.png"), self.p("img1.webp"), self.p("img10.png"))
        self.assertEqual([f["n"] for f in o["files"]], ["img10.png", "img1.webp"])
        self.assertEqual(o["index"], 0)

    def test_trash_goes_to_data_trash(self):
        o = self.run_helper("trash", self.p("img1.webp"))
        self.assertTrue(o["ok"])
        self.assertFalse(os.path.exists(self.p("img1.webp")))
        trash = os.path.join(self.tmp.name, "share", "Trash")
        self.assertTrue(os.path.exists(os.path.join(trash, "files", "img1.webp")))
        self.assertTrue(os.path.exists(os.path.join(trash, "info", "img1.webp.trashinfo")))

    def test_trash_missing_reports_error(self):
        o = self.run_helper("trash", self.p("gone.png"))
        self.assertFalse(o["ok"])
        self.assertTrue(o["err"])


if __name__ == "__main__":
    unittest.main()
