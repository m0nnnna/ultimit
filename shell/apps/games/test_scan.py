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
        self.assertEqual(d["settings"]["games"]["manual:abc"],
                         {"prefix": "/tmp/pfx", "dxvk": False, "runner": "", "proton": "", "gameid": ""})
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


class Proton(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="steam-", dir=TMP)
        self.saved, self.which = os.environ["ULTIMIT_STEAM_ROOT"], scan.which
        os.environ["ULTIMIT_STEAM_ROOT"] = self.root
        os.makedirs(self.root + "/steamapps/common")
        for d in ("compatibilitytools.d/GE-Proton9-5", "compatibilitytools.d/GE-Proton10-1",
                  "steamapps/common/Proton - Experimental", "steamapps/common/Proton 9.0 (Beta)"):
            os.makedirs(os.path.join(self.root, d))
            open(os.path.join(self.root, d, "proton"), "w").close()
        os.makedirs(self.root + "/compatibilitytools.d/Broken")                  # no proton script
        os.makedirs(self.root + "/steamapps/common/Proton Hotfix")
        scan.write_settings(scan.normalize({}))
        scan.which = lambda n, _w=scan.which: {"umu-run": "/usr/bin/umu-run", "gamemoderun": "/usr/games/gamemoderun",
                                              "mangohud": "/usr/bin/mangohud"}.get(n, _w(n))
        self.exe = TMP + "/g/game.exe"
        scan.main(["x", "add-manual", json.dumps({"id": "manual:p1", "name": "P", "kind": "wine", "target": self.exe,
                                                   "prefix": TMP + "/ppfx", "runner": "proton"})])

    def tearDown(self):
        os.environ["ULTIMIT_STEAM_ROOT"] = self.saved
        scan.which = self.which

    def test_effective(self):
        e = scan.effective({})
        self.assertEqual((e["runner"], e["proton"], e["gameid"]), ("wine", "", "umu-default"))
        e = scan.effective({"runner": "bogus", "gameid": "  ", "proton": None})
        self.assertEqual((e["runner"], e["proton"], e["gameid"]), ("wine", "", "umu-default"))
        e = scan.effective({"runner": "proton", "proton": "/p/x", "gameid": "umu-123"})
        self.assertEqual((e["runner"], e["proton"], e["gameid"]), ("proton", "/p/x", "umu-123"))

    def test_find_protons(self):
        got = scan.find_protons()
        self.assertEqual([p["name"] for p in got], ["GE-Proton10-1", "GE-Proton9-5", "Proton - Experimental", "Proton 9.0 (Beta)"])
        self.assertEqual(got[0]["path"], self.root + "/compatibilitytools.d/GE-Proton10-1")
        os.symlink(self.root + "/compatibilitytools.d/GE-Proton9-5", self.root + "/compatibilitytools.d/alias")
        self.assertEqual(len(scan.find_protons()), 4)                              # deduped by realpath
        d = scan.scan()
        self.assertEqual(d["protons"], scan.find_protons())
        self.assertIn("umu", d["tools"])

    def test_plan_proton(self):
        p = scan.plan("manual:p1")
        self.assertEqual(p["argv"], ["gamemoderun", "/usr/bin/umu-run", self.exe])
        self.assertEqual(p["cwd"], os.path.dirname(self.exe))
        self.assertEqual(p["pre"], [{"step": "mkdir", "prefix": TMP + "/ppfx"}])  # no wineboot/dxvk
        os.makedirs(TMP + "/ppfx", exist_ok=True)
        self.assertEqual(scan.plan("manual:p1")["pre"], [])
        self.assertEqual(p["env"]["WINEPREFIX"], TMP + "/ppfx")
        self.assertEqual(p["env"]["GAMEID"], "umu-default")
        self.assertEqual(p["env"]["PROTONPATH"], self.root + "/compatibilitytools.d/GE-Proton10-1")
        self.assertNotIn("WINEDLLOVERRIDES", p["env"])
        self.assertNotIn("WINEDEBUG", p["env"])
        scan.main(["x", "set", "manual:p1", json.dumps({"prefix": "default"})])
        self.assertEqual(scan.plan("manual:p1")["env"]["WINEPREFIX"], scan.PROTON_PREFIX)  # not Wine's default
        self.assertNotEqual(scan.PROTON_PREFIX, scan.DEFAULT_PREFIX)
        scan.main(["x", "set", "manual:p1", json.dumps({"prefix": TMP + "/ppfx"})])
        scan.main(["x", "set", "manual:p1", json.dumps({"overlay": True, "gameid": "umu-42", "env": "FOO=1", "args": "-w"})])
        p = scan.plan("manual:p1")
        self.assertEqual((p["env"]["MANGOHUD"], p["env"]["GAMEID"], p["env"]["FOO"]), ("1", "umu-42", "1"))
        self.assertEqual(p["argv"][-1], "-w")

    def test_auto_choice(self):
        valve = self.root + "/steamapps/common/"
        shutil.rmtree(self.root + "/compatibilitytools.d")
        self.assertEqual(scan.plan("manual:p1")["env"]["PROTONPATH"], valve + "Proton - Experimental")
        shutil.rmtree(valve + "Proton - Experimental")
        self.assertEqual(scan.plan("manual:p1")["env"]["PROTONPATH"], valve + "Proton 9.0 (Beta)")
        shutil.rmtree(valve + "Proton 9.0 (Beta)")
        p = scan.plan("manual:p1")
        self.assertNotIn("PROTONPATH", p["env"])
        self.assertTrue(any("UMU-Proton" in n for n in p["notes"]))

    def test_explicit_and_missing_umu(self):
        pick = self.root + "/steamapps/common/Proton 9.0 (Beta)"
        scan.main(["x", "set", "manual:p1", json.dumps({"proton": pick})])
        self.assertEqual(scan.plan("manual:p1")["env"]["PROTONPATH"], pick)
        scan.main(["x", "set", "manual:p1", json.dumps({"proton": "/nope"})])
        p = scan.plan("manual:p1")
        self.assertEqual(p["env"]["PROTONPATH"], self.root + "/compatibilitytools.d/GE-Proton10-1")
        self.assertTrue(any("Proton not found" in n for n in p["notes"]))
        scan.which = lambda n: ""
        p = scan.plan("manual:p1")
        self.assertIn("umu-run is not installed", p["notes"])
        self.assertEqual(p["argv"][0], "umu-run")

    def test_wine_runner_unchanged(self):
        scan.main(["x", "set", "manual:p1", json.dumps({"runner": "wine"})])
        scan.which = lambda n: "/usr/bin/" + n if n == "wine" else ""
        p = scan.plan("manual:p1")
        self.assertEqual(p["argv"], ["/usr/bin/wine", self.exe])
        self.assertEqual([s["step"] for s in p["pre"]], ["wineboot", "dxvk"])
        self.assertNotIn("GAMEID", p["env"])
        self.assertEqual(p["env"]["WINEDEBUG"], "-all")


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


class Installer(unittest.TestCase):
    def setUp(self):
        self.saved_root = os.environ["ULTIMIT_STEAM_ROOT"]
        os.environ["ULTIMIT_STEAM_ROOT"] = ""                    # no Proton builds installed
        self.which = scan.which
        scan.which = lambda n, _w=scan.which: {"umu-run": "/usr/bin/umu-run", "wine": "/usr/bin/wine"}.get(n, _w(n))
        self.inst = os.path.join(TMP, "dl", "setup_the_witcher_2_1.0.2_(12345).exe")
        os.makedirs(os.path.dirname(self.inst), exist_ok=True)
        open(self.inst, "w").close()

    def tearDown(self):
        os.environ["ULTIMIT_STEAM_ROOT"] = self.saved_root
        scan.which = self.which
        shutil.rmtree(os.path.dirname(scan.PROTON_PREFIX), ignore_errors=True)

    def test_name_slug_and_uniqueness(self):
        self.assertEqual(scan.installer_name(self.inst), "the witcher 2")
        p = scan.install_plan(self.inst)
        self.assertEqual((p["name"], p["slug"]), ("the witcher 2", "the-witcher-2"))
        self.assertTrue(p["prefix"].startswith(os.path.dirname(scan.PROTON_PREFIX)))
        self.assertEqual(p["gameid"], "umu-the-witcher-2")
        self.assertEqual(p["env"]["GAMEID"], "umu-the-witcher-2")
        os.makedirs(p["prefix"])                                 # taken -> -2
        self.assertEqual(scan.install_plan(self.inst)["slug"], "the-witcher-2-2")

    def test_plan_proton_and_wine(self):
        p = scan.install_plan(self.inst, runner="proton")
        self.assertEqual(p["argv"], ["/usr/bin/umu-run", self.inst])
        self.assertNotIn("PROTONPATH", p["env"])
        self.assertTrue(any("UMU-Proton" in n for n in p["notes"]))
        w = scan.install_plan(self.inst, runner="wine")
        self.assertEqual(w["argv"], ["/usr/bin/wine", self.inst])
        self.assertEqual(w["env"]["WINEDEBUG"], "-all")
        with self.assertRaises(ValueError):
            scan.install_plan(TMP + "/missing.exe")
        r = subprocess.run([sys.executable, os.path.join(HERE, "scan.py"), "install-plan",
                            json.dumps({"installer": self.inst, "name": "X"})],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(r.stdout)["name"], "X")

    def test_scan_prefix_filters_debris(self):
        pfx = os.path.join(TMP, "pp")
        g = os.path.join(pfx, "drive_c/Program Files/TW2/bin/witcher2.exe")
        others = (os.path.join(pfx, "drive_c/Program Files/TW2/unins000.exe"),
                  os.path.join(pfx, "drive_c/windows/system32/kernel32.exe"),
                  os.path.join(pfx, "drive_c/users/witcher/AppData/Local/updater.exe"),
                  os.path.join(pfx, "drive_c/Program Files/Common Files/system/advpack.exe"))
        for f in (g,) + others:
            os.makedirs(os.path.dirname(f), exist_ok=True)
            open(f, "w").write("x" * 10)
        open(g, "w").write("x" * 100)
        cands = scan.scan_prefix(pfx)
        self.assertEqual([c["path"] for c in cands], [g])
        r = subprocess.run([sys.executable, os.path.join(HERE, "scan.py"), "install-scan", pfx],
                           capture_output=True, text=True)
        self.assertEqual(json.loads(r.stdout)["candidates"][0]["size"], 100)

    def test_install_run_makes_prefix(self):
        pfx = os.path.join(TMP, "pr")
        plan = {"prefix": pfx, "installer": self.inst,
                "argv": ["/bin/sh", "-c", "echo ok > \"$WINEPREFIX/marker\""], "env": {"WINEPREFIX": pfx}}
        self.assertEqual(scan.install_run(plan)["rc"], 0)
        self.assertEqual(open(os.path.join(pfx, "marker")).read().strip(), "ok")

    def test_installer_mode_env(self):
        p = scan.install_plan(self.inst, runner="proton", installer_mode=True, log=True)
        self.assertEqual(p["env"]["PROTON_USE_WINED3D"], "1")
        self.assertEqual(p["env"]["PROTON_LOG"], "1")
        self.assertEqual((p["installer_mode"], p["winver"], p["log"]), (True, "win10", True))
        plain = scan.install_plan(self.inst, runner="proton", installer_mode=False)
        self.assertNotIn("PROTON_USE_WINED3D", plain["env"])
        self.assertFalse(plain["installer_mode"])
        self.assertEqual(scan.install_plan(self.inst, winver="bogus")["winver"], "win10")

    def test_winver_implies_32bit_prefix_for_wine(self):
        p = scan.install_plan(self.inst, runner="wine", winver="winxp")
        self.assertEqual(p["env"]["WINEARCH"], "win32")
        self.assertEqual(p["winver"], "winxp")
        pr = scan.install_plan(self.inst, runner="proton", winver="winxp")
        self.assertNotIn("WINEARCH", pr["env"])                  # Proton prefixes are 64-bit only

    def test_install_run_winver_steps(self):
        calls, real = [], scan.subprocess.call
        scan.subprocess.call = lambda a, **k: calls.append(list(a)) or 0
        try:
            plan = {"prefix": TMP + "/wv", "installer": self.inst, "runner": "wine",
                    "argv": ["wine", self.inst], "env": {"WINEPREFIX": TMP + "/wv"}, "winver": "win7"}
            self.assertEqual(scan.install_run(plan)["rc"], 0)
            self.assertTrue(calls[0][0].endswith("wineboot"))
            self.assertEqual(calls[1][:2], ["wine", "reg"])
            self.assertEqual(calls[1][calls[1].index("/d") + 1], "win7")
            self.assertEqual(calls[2], ["wine", self.inst])
            calls.clear()
            plan["winver"] = "win10"                             # default: no setup steps
            scan.install_run(plan)
            self.assertEqual(calls, [["wine", self.inst]])
            calls.clear()
            plan["runner"] = "proton"                            # proton: setup via umu-run
            plan["argv"] = ["/usr/bin/umu-run", self.inst]
            plan["winver"] = "win7"
            scan.install_run(plan)
            self.assertEqual(calls[0], ["/usr/bin/umu-run", "wineboot", "-u"])
            self.assertEqual(calls[1][:2], ["/usr/bin/umu-run", "reg"])
            calls.clear()
            scan.subprocess.call = lambda a, **k: calls.append(list(a)) or (_ for _ in ()).throw(OSError("no umu"))
            r = scan.install_run(plan)
            self.assertEqual((r["rc"], r["error"]), (127, "no umu"))
        finally:
            scan.subprocess.call = real


class Manage(unittest.TestCase):
    def setUp(self):
        scan.write_settings(scan.normalize({}))

    def test_edit_replaces_managed_keys(self):
        scan.main(["x", "add-manual", json.dumps({"id": "manual:e1", "name": "E", "kind": "wine", "target": "/g/e.exe",
                                                   "prefix": "/pfx", "runner": "proton", "proton": "/p", "gameid": "umu-e"})])
        scan.main(["x", "add-manual", json.dumps({"id": "manual:e1", "name": "E2", "kind": "wine", "target": "/g/e2.exe"})])
        g = scan.load_settings()["games"]["manual:e1"]
        self.assertEqual((g["prefix"], g["runner"], g["proton"], g["gameid"]), ("", "", "", ""))
        e = scan.effective(g)
        self.assertEqual((e["prefix"], e["runner"], e["proton"], e["gameid"]),
                         ("default", "wine", "", "umu-default"))
        self.assertEqual(next(x for x in scan.scan()["games"] if x["id"] == "manual:e1")["name"], "E2")

    def test_remove_manual_deletes_prefix_inside_ultimit_only(self):
        scan.main(["x", "add-manual", json.dumps({"id": "manual:r1", "name": "R", "kind": "wine", "target": "/g/r.exe"})])
        pfx = os.path.join(scan.DATA_HOME, "ultimit", "proton", "r1")
        os.makedirs(pfx)
        open(os.path.join(pfx, "f"), "w").close()
        scan.main(["x", "remove-manual", "manual:r1", pfx])
        self.assertFalse(os.path.exists(pfx))
        self.assertNotIn("manual:r1", scan.load_settings()["games"])
        outside = os.path.join(TMP, "outside")
        os.makedirs(outside, exist_ok=True)
        with self.assertRaises(SystemExit):
            scan.main(["x", "remove-manual", "manual:r1", outside])
        self.assertTrue(os.path.isdir(outside))                     # untouched

    def test_hidden_desktop_games(self):
        scan.main(["x", "top", "hidden", json.dumps(["desktop:supertux.desktop"])])
        self.assertNotIn("desktop:supertux.desktop", {g["id"] for g in scan.scan()["games"]})
        scan.main(["x", "top", "hidden", json.dumps([])])
        self.assertIn("desktop:supertux.desktop", {g["id"] for g in scan.scan()["games"]})


if __name__ == "__main__":
    try:
        unittest.main(verbosity=2)
    finally:
        shutil.rmtree(TMP, ignore_errors=True)
