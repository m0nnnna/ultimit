#!/usr/bin/env python3
"""Unit tests for scan.py on fixtures. Run: python3 apps/games/test_scan.py
Everything happens in a temp HOME; nothing launches."""
import importlib.util, json, os, shutil, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
TMP = tempfile.mkdtemp(prefix="games-test-")
HOME = os.path.join(TMP, "home")
subprocess.run(["sh", os.path.join(FIX, "make-home.sh"), HOME], check=True)
os.environ.update({
    "HOME": HOME, "XDG_DATA_HOME": HOME + "/.local/share", "XDG_CONFIG_HOME": HOME + "/.config",
    "XDG_DATA_DIRS": HOME + "/nonexistent", "ULTIMIT_STEAM_ROOT": FIX, "ULTIMIT_STEAM_BIN": "",
    "ULTIMIT_DRY_RUN": "1", "ULTIMIT_DRY_RUN_LOG": TMP + "/dry.log", "PATH": os.environ["PATH"],
})
spec = importlib.util.spec_from_file_location("scan", os.path.join(HERE, "scan.py"))
scan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scan)
scan.has_nvidia = lambda: True


class Scan(unittest.TestCase):
    def ids(self, games, src=None):
        return {g["id"] for g in games if src is None or g["source"] == src}

    def test_desktop_filtering(self):
        apps = {g["id"]: g for g in scan.scan_desktop()}
        self.assertIn("desktop:nekocore-launcher.desktop", apps)
        self.assertIn("desktop:org.example.Starfall.desktop", apps)    # Flatpak export dir
        self.assertIn("desktop:supertux.desktop", apps)
        for skipped in ("hidden-game", "steam", "steam_icon_525480", "text-editor"):   # NoDisplay, Steam, shortcut, not a game
            self.assertNotIn("desktop:%s.desktop" % skipped, apps)
        self.assertEqual(apps["desktop:supertux.desktop"]["exec"], ["env", "SDL_VIDEODRIVER=wayland", "supertux2", "--fullscreen"])
        self.assertEqual(apps["desktop:org.example.Starfall.desktop"]["exec"][:3], ["flatpak", "run", "--branch=stable"])
        self.assertNotIn("@@u", apps["desktop:org.example.Starfall.desktop"]["exec"])
        self.assertTrue(apps["desktop:org.example.Starfall.desktop"]["flatpak"])

    def test_steam_and_merge(self):
        d = scan.scan()
        steam = self.ids(d["games"], "steam")
        self.assertEqual(steam, {"525480", "1245620", "427520", "413150", "1493710"} & steam)
        self.assertNotIn("228980", steam)
        self.assertTrue(all(i.isdigit() for i in steam))
        self.assertEqual(d["steamState"], "ready")
        self.assertEqual(len([g for g in d["games"] if g["id"] == "525480"]), 1)   # shortcut not duplicated

    def test_steam_states(self):
        self.assertEqual(scan.steam_state(None, ""), "missing") if not scan.steam_data_present() else None
        self.assertEqual(scan.steam_state("/x", ""), "ready")
        saved = os.environ["ULTIMIT_STEAM_ROOT"]
        try:
            os.environ["ULTIMIT_STEAM_ROOT"] = TMP + "/no-steam"
            self.assertEqual(scan.steam_state(scan.find_root(), ""), "missing")
            self.assertEqual(scan.steam_state(scan.find_root(), "/usr/bin/steam"), "setup")
            os.makedirs(TMP + "/no-steam")                       # data dir exists, no steamapps yet
            self.assertEqual(scan.steam_state(scan.find_root(), "/usr/bin/steam"), "ready")
        finally:
            os.environ["ULTIMIT_STEAM_ROOT"] = saved

    def test_manual_and_settings(self):
        scan.main(["x", "add-manual", json.dumps({"id": "manual:abc", "name": "Old Game", "kind": "wine", "target": "/games/old/old.exe", "prefix": "/tmp/pfx"})])
        scan.main(["x", "set", "manual:abc", json.dumps({"dxvk": False})])
        d = scan.scan()
        g = next(g for g in d["games"] if g["id"] == "manual:abc")
        self.assertEqual((g["kind"], g["source"]), ("wine", "app"))
        self.assertEqual(d["settings"]["games"]["manual:abc"], {"prefix": "/tmp/pfx", "dxvk": False})
        scan.main(["x", "touch", "manual:abc"])
        self.assertGreater(scan.scan()["settings"]["games"]["manual:abc"]["lastLaunched"], 0)
        with self.assertRaises(SystemExit):
            scan.main(["x", "add-manual", json.dumps({"id": "bad", "name": "x"})])
        scan.main(["x", "remove-manual", "manual:abc"])
        self.assertNotIn("manual:abc", self.ids(scan.scan()["games"]))
        self.assertNotIn("manual:abc", scan.load_settings()["games"])

    def test_defaults(self):
        e = scan.effective({})
        self.assertEqual((e["gpu"], e["gamemode"], e["overlay"], e["gamescope"], e["dxvk"]), ("discrete", True, False, False, True))
        self.assertEqual(scan.effective({"gpu": "nvidia"})["gpu"], "discrete")        # legacy value
        self.assertEqual(scan.effective({"scopeRes": "$(evil)", "scopeFps": "x"})["scopeRes"], "")
        self.assertEqual(scan.parse_env('A=1 B="x y"\nC=3 1BAD=2'), {"A": "1", "B": "x y", "C": "3"})


class Plan(unittest.TestCase):
    def setUp(self):
        scan.write_settings(scan.normalize({}))
        scan.which = lambda n, _w=scan.which: {"gamemoderun": "/usr/games/gamemoderun", "mangohud": "/usr/bin/mangohud",
                                              "gamescope": "/usr/bin/gamescope", "wine": "/usr/bin/wine"}.get(n, _w(n))

    def test_nekocore_discrete_gamemode(self):
        p = scan.plan("desktop:nekocore-launcher.desktop")
        self.assertEqual(p["argv"], ["gamemoderun", "/home/mino/.local/bin/nekocore"])
        for k, v in scan.NVIDIA_ENV.items():
            self.assertEqual(p["env"][k], v)

    def test_options_compose(self):
        scan.main(["x", "set", "desktop:supertux.desktop", json.dumps({
            "gpu": "integrated", "gamemode": False, "overlay": True, "gamescope": True, "scopeRes": "1280x720",
            "scopeFps": 60, "env": "FOO=bar", "args": "--debug '--name=a b'"})])
        p = scan.plan("desktop:supertux.desktop")
        self.assertEqual(p["argv"][:11], ["gamescope", "-f", "-w", "1280", "-h", "720", "-W", "1280", "-H", "720", "-r"])
        self.assertEqual(p["argv"][11:15], ["60", "--", "mangohud", "env"])  # gamemode off in this case
        self.assertEqual(p["argv"][-2:], ["--debug", "--name=a b"])
        self.assertEqual(p["env"]["DXVK_FILTER_DEVICE_NAME"], "Intel")
        self.assertEqual(p["env"]["FOO"], "bar")
        self.assertNotIn("__NV_PRIME_RENDER_OFFLOAD", p["env"])

    def test_wine_manual_dxvk(self):
        pfx = TMP + "/pfx"
        exe = TMP + "/g/game.exe"
        scan.main(["x", "add-manual", json.dumps({"id": "manual:w1", "name": "W", "kind": "wine", "target": exe, "prefix": pfx})])
        p = scan.plan("manual:w1")
        self.assertEqual(p["argv"], ["gamemoderun", "/usr/bin/wine", exe])
        self.assertEqual(p["env"]["WINEPREFIX"], pfx)
        self.assertEqual([s["step"] for s in p["pre"]], ["wineboot", "dxvk"])
        self.assertIn("dxgi", p["env"]["WINEDLLOVERRIDES"])
        # default shared prefix + dxvk off
        scan.main(["x", "set", "manual:w1", json.dumps({"prefix": "default", "dxvk": False})])
        p = scan.plan("manual:w1")
        self.assertEqual(p["env"]["WINEPREFIX"], scan.DEFAULT_PREFIX)
        self.assertEqual([s["step"] for s in p["pre"]], ["wineboot"])
        self.assertNotIn("WINEDLLOVERRIDES", p["env"])

    def test_install_dxvk(self):
        pfx = TMP + "/pfx2"
        for d in ("system32", "syswow64"):
            os.makedirs(pfx + "/drive_c/windows/" + d)
        done = scan.install_dxvk(pfx, FIX + "/dxvk/current")
        self.assertEqual(len(done), 8)
        self.assertEqual(open(pfx + "/drive_c/windows/syswow64/d3d9.dll").read(), "dummy x32 d3d9\n")
        self.assertEqual(open(pfx + "/drive_c/windows/system32/d3d9.dll").read(), "dummy x64 d3d9\n")
        self.assertEqual(scan.install_dxvk(pfx, FIX + "/dxvk/current"), [])          # idempotent

    def test_flatpak_env_and_steam(self):
        p = scan.plan("desktop:org.example.Starfall.desktop")
        self.assertIn("--env=__NV_PRIME_RENDER_OFFLOAD=1", p["argv"])
        self.assertLess(p["argv"].index("--env=__NV_PRIME_RENDER_OFFLOAD=1"), p["argv"].index("--branch=stable"))
        scan.main(["x", "set", "413150", json.dumps({"overlay": True})])
        p = scan.plan("413150", ["/games/sv", "-x"])
        self.assertEqual(p["argv"], ["gamemoderun", "mangohud", "/games/sv", "-x"])
        with self.assertRaises(ValueError):
            scan.plan("413150")

    def test_wrapper_dry_run(self):
        w = os.path.join(HERE, "..", "..", "bin", "ultimit-game-run")
        r = subprocess.run([w, "--id", "desktop:nekocore-launcher.desktop"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        log = open(TMP + "/dry.log").read()
        self.assertIn('"/home/mino/.local/bin/nekocore"', log)
        self.assertGreater(scan.load_settings()["games"]["desktop:nekocore-launcher.desktop"]["lastLaunched"], 0)
        r = subprocess.run([w, "--", "/bin/echo", "never-run"], capture_output=True, text=True)
        self.assertNotIn("never-run", r.stdout)


if __name__ == "__main__":
    try:
        unittest.main(verbosity=2)
    finally:
        shutil.rmtree(TMP, ignore_errors=True)
