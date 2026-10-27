#!/usr/bin/python3 -I
"""Tests for Game Mode: gamemode.py (power profile + game-run markers) against a fake daemon, and
detect.js under node. python3 apps/gamemode/test_gamemode.py   Nothing touches the real power settings."""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
HELPER = os.path.join(HERE, "gamemode.py")


class Helper(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="gamemode-test-")
        self.ppd = os.path.join(self.tmp, "ppd")
        self.env = dict(os.environ, ULTIMIT_STATE_DIR=os.path.join(self.tmp, "state"), ULTIMIT_FAKE_PPD=self.ppd,
                        PATH="/nonexistent", ULTIMIT_DRY_RUN="")
        self.env.pop("ULTIMIT_DEVBOX", None)
        self.set("balanced")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def set(self, p):
        with open(self.ppd, "w") as f:
            f.write(p + "\n")

    def cur(self):
        with open(self.ppd) as f:
            return f.read().strip()

    def run_h(self, *args, env=None):
        r = subprocess.run([sys.executable, HELPER] + list(args), env=env or self.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout.strip()

    def state(self):
        return json.loads(self.run_h("power", "status"))

    def test_on_off_restores(self):
        self.run_h("power", "on")
        self.assertEqual(self.cur(), "performance")
        self.assertEqual(self.state()["prev"], "balanced")
        self.run_h("power", "off")
        self.assertEqual(self.cur(), "balanced")
        self.assertEqual(self.state(), {})

    def test_power_saver_restored(self):
        self.set("power-saver")
        self.run_h("power", "on")
        self.run_h("power", "off")
        self.assertEqual(self.cur(), "power-saver")

    def test_on_twice_keeps_first_profile(self):
        self.run_h("power", "on")
        self.run_h("power", "on")
        self.run_h("power", "off")
        self.assertEqual(self.cur(), "balanced")

    def test_stale_state_restored_at_startup(self):
        self.run_h("power", "on", "--owner", "999999")   # a "shell" that is gone
        self.assertEqual(self.cur(), "performance")
        self.run_h("power", "restore-stale")
        self.assertEqual(self.cur(), "balanced")
        self.assertEqual(self.state(), {})

    def test_user_changed_profile_meanwhile_is_kept(self):
        self.run_h("power", "on")
        self.set("power-saver")
        self.run_h("power", "off")
        self.assertEqual(self.cur(), "power-saver")

    def test_off_without_state_is_noop(self):
        self.set("performance")
        self.run_h("power", "off")
        self.assertEqual(self.cur(), "performance")

    def test_already_performance(self):
        self.set("performance")
        self.run_h("power", "on")
        self.run_h("power", "off")
        self.assertEqual(self.cur(), "performance")

    def test_no_performance_profile_skips(self):
        env = dict(self.env, ULTIMIT_FAKE_PPD_LIST="power-saver balanced")
        self.run_h("power", "on", env=env)
        self.assertEqual(self.cur(), "balanced")
        self.assertEqual(self.state(), {})

    def test_no_powerprofilesctl_skips_silently(self):
        env = dict(self.env)
        del env["ULTIMIT_FAKE_PPD"]
        self.assertEqual(self.run_h("power", "on", env=env), "")
        self.assertEqual(self.run_h("power", "off", env=env), "")

    def test_devbox_never_touches_real_power(self):
        env = dict(self.env, ULTIMIT_DEVBOX="1")
        del env["ULTIMIT_FAKE_PPD"]
        env["PATH"] = os.environ["PATH"]
        self.assertEqual(self.run_h("power", "on", env=env), "")
        self.assertEqual(self.state(), {})

    def test_dry_run_changes_nothing(self):
        out = self.run_h("--dry-run", "power", "on")
        self.assertIn("DRYRUN", out)
        self.assertEqual(self.cur(), "balanced")
        self.assertEqual(self.state(), {})

    def test_watcher_restores_when_owner_dies(self):
        owner = subprocess.Popen(["sleep", "30"])
        try:
            self.run_h("power", "on", "--owner", str(owner.pid))
            self.assertEqual(self.cur(), "performance")
            owner.kill()
            owner.wait()
            end = time.time() + 12
            while time.time() < end and self.cur() != "balanced":
                time.sleep(0.3)
            self.assertEqual(self.cur(), "balanced")
        finally:
            owner.kill()

    def test_game_run_markers(self):
        self.assertEqual(self.run_h("running"), "0")
        sleeper = subprocess.Popen(["sleep", "30"])
        try:
            self.run_h("mark", "--id", "steam:42", "--pid", str(sleeper.pid))
            self.assertEqual(self.run_h("running"), "1 steam:42")
        finally:
            sleeper.kill()
            sleeper.wait()
        self.assertEqual(self.run_h("running"), "0")   # crashed game: marker is dead, and cleaned up
        self.assertEqual(os.listdir(os.path.join(self.tmp, "state", "game-run")), [])

    def test_game_run_wrapper_marks_pid(self):
        env = dict(self.env, ULTIMIT_DRY_RUN="")
        wrapper = os.path.join(HERE, "..", "..", "bin", "ultimit-game-run")
        code = ("import importlib.machinery,importlib.util,sys;"
                "l=importlib.machinery.SourceFileLoader('gr',sys.argv[1]);s=importlib.util.spec_from_loader('gr',l);"
                "m=importlib.util.module_from_spec(s);l.exec_module(m);sys.exit(m.main(['--id','manual:t','--','sleep','2']))")
        env["PATH"] = "/usr/bin:/bin"
        env["HOME"] = self.tmp
        p = subprocess.Popen([sys.executable, "-c", code, wrapper], env=env, stderr=subprocess.DEVNULL)
        try:
            end = time.time() + 8
            seen = ""
            while time.time() < end and not seen.startswith("1"):
                seen = self.run_h("running")
                time.sleep(0.2)
            self.assertTrue(seen.startswith("1"), seen)
        finally:
            p.wait()
        self.assertEqual(self.run_h("running"), "0")


class Detect(unittest.TestCase):
    @unittest.skipUnless(shutil.which("node"), "node missing")
    def test_detect_js(self):
        r = subprocess.run(["node", os.path.join(HERE, "detect_test.js")], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
