#!/usr/bin/env python3
"""Unit tests for broadcast.py / obsws.py. Run: python3 apps/broadcast/test_broadcast.py
Unit tests use a fake runner/spawn and a temp HOME; the CLI tests run the real script in BROADCAST_FAKE=1 mode
(fake flatpak/systemd-run/pgrep/pw-dump + a fake obs-websocket server on a private port). Nothing touches the
real EasyEffects, OBS, PipeWire or the real home folder."""
import warnings; warnings.simplefilter("ignore", ResourceWarning)
import asyncio, base64, importlib.util, json, os, socket, subprocess, sys, tempfile, threading, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TMP = tempfile.mkdtemp(prefix="broadcast-test-")
for k in ("BROADCAST_FAKE", "BROADCAST_BIN_DIR", "BROADCAST_HOME", "BROADCAST_RUNTIME"):
    os.environ.pop(k, None)
os.environ.update({"HOME": TMP + "/home", "XDG_RUNTIME_DIR": TMP + "/run", "BROADCAST_V4L_DIR": HERE + "/fixtures/v4l"})
os.makedirs(TMP + "/home"); os.makedirs(TMP + "/run")
sys.path.insert(0, HERE)
spec = importlib.util.spec_from_file_location("broadcast", os.path.join(HERE, "broadcast.py"))
bc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bc)
import obsws  # noqa: E402


def fixture(n):
    return open(os.path.join(HERE, "fixtures", n)).read()


def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p


class Fake:
    """Records argv; `ee` = EasyEffects running. Answers like the real programs."""
    def __init__(self, ee=False, obs=False):
        self.calls, self.ee, self.obs, self.units = [], ee, obs, set()
        self.spawned = []

    def runner(self, argv, input_text=None, timeout=15):
        self.calls.append(list(argv))
        n = os.path.basename(argv[0]); a = argv[1:]
        if n == "pgrep":
            on = self.ee if a[-1] == "easyeffects" else self.obs
            return (0, "4242\n", "") if on else (1, "", "")
        if n == "pw-dump":
            d = json.loads(fixture("pw-dump.json"))
            if self.ee: d += json.loads(fixture("pw-dump-ee.json"))
            return 0, json.dumps(d), ""
        if n == "wpctl":
            return (0, fixture("wpctl-status.txt"), "") if a[0] == "status" else (0, "", "")
        if n == "systemctl":
            return (0, "active\n", "") if a[-1] in self.units else (3, "inactive\n", "")
        if n == "systemd-run":
            u = [x for x in a if x.startswith("--unit=")][0][7:]
            self.units.add(u)
            if "easyeffects" in u: self.ee = True
            else: self.obs = True
            return 0, "", ""
        if n == "flatpak":
            return 0, "", ""
        return 127, "", "nope"

    def names(self):
        return [" ".join(c) for c in self.calls]

    def ee_cli(self):
        return [c for c in self.calls if c[:3] == ["flatpak", "run", bc.EE_APP]]


def install(fake):
    bc.runner = fake.runner
    bc.spawn = lambda argv, log="x": 999999
    bc.sleep = lambda s: None
    bc.ee_ready = lambda: fake.ee


class Base(unittest.TestCase):
    def setUp(self):
        self.home = tempfile.mkdtemp(dir=TMP)
        os.environ["BROADCAST_HOME"] = self.home
        os.environ["BROADCAST_RUNTIME"] = tempfile.mkdtemp(dir=TMP)
        self.saved = (bc.runner, bc.spawn, bc.sleep, bc.ee_ready, obsws.transport)

    def tearDown(self):
        bc.runner, bc.spawn, bc.sleep, bc.ee_ready, obsws.transport = self.saved


class Presets(Base):
    def test_off_is_empty(self):
        self.assertEqual(bc.build_preset("input", False, "strong"), {"input": {"blocklist": [], "plugins_order": []}})

    def test_strong_light_echo(self):
        p = bc.build_preset("input", True, "strong")["input"]
        self.assertEqual(p["plugins_order"], ["deepfilternet#0"])
        self.assertEqual(p["deepfilternet#0"], {"bypass": False, "attenuation-limit": 100.0, "post-filter-beta": 0.02})
        p = bc.build_preset("input", True, "light")["input"]
        self.assertEqual(p["plugins_order"], ["rnnoise#0"])
        self.assertTrue(p["rnnoise#0"]["enable-vad"])
        p = bc.build_preset("input", True, "light", echo=True)["input"]
        self.assertEqual(p["plugins_order"], ["rnnoise#0", "speex#0"])
        self.assertEqual(p["speex#0"]["enable-dereverb"], True)
        self.assertEqual(p["speex#0"]["enable-denoise"], False)

    def test_speakers_never_get_echo(self):
        p = bc.build_preset("output", True, "strong", echo=True)
        self.assertEqual(list(p), ["output"])
        self.assertEqual(p["output"]["plugins_order"], ["deepfilternet#0"])

    def test_write_preset_paths(self):
        s = bc.load_settings(); s["mic"].update(enabled=True)
        path = bc.write_preset("input", s)
        self.assertTrue(path.endswith("easyeffects/input/Broadcast Mic.json"))
        self.assertTrue(json.load(open(path))["input"]["plugins_order"])
        self.assertTrue(bc.preset_path("output").endswith("easyeffects/output/Broadcast Speakers.json"))


class EasyEffectsRule(Base):
    def test_never_cli_when_not_running(self):
        f = Fake(ee=False); install(f)
        r = bc.apply_preset("input", bc.load_settings(), start_engine=False)
        self.assertTrue(r["ok"]); self.assertFalse(r["loaded"])
        self.assertEqual(f.ee_cli(), [])
        self.assertTrue(os.path.exists(bc.preset_path("input")))
        self.assertFalse(bc.ee_load("x")["ok"])
        self.assertEqual(f.ee_cli(), [])
        self.assertFalse(bc.ee_stop()["stopped"])
        self.assertEqual(f.ee_cli(), [])

    def test_start_then_load(self):
        f = Fake(ee=False); install(f)
        s = bc.load_settings(); s["mic"]["enabled"] = True
        r = bc.apply_preset("input", s, start_engine=True)
        self.assertTrue(r["loaded"])
        n = f.names()
        i = next(k for k, c in enumerate(n) if c.startswith("systemd-run"))
        self.assertIn("--unit=ultimit-easyeffects", n[i])
        self.assertTrue(n[i].endswith("flatpak run com.github.wwmm.easyeffects -w"))
        self.assertEqual([c[3:] for c in f.ee_cli()], [["-l", "Broadcast Mic"]])
        self.assertLess(i, n.index("flatpak run com.github.wwmm.easyeffects -l Broadcast Mic"))

    def test_load_when_running_no_start(self):
        f = Fake(ee=True); install(f)
        bc.apply_preset("output", bc.load_settings(), start_engine=False)
        self.assertEqual([c[3:] for c in f.ee_cli()], [["-l", "Broadcast Speakers"]])
        self.assertFalse([c for c in f.calls if c[0] == "systemd-run"])

    def test_stop_uses_q(self):
        f = Fake(ee=True); install(f)
        def run(argv, i=None, t=15):
            r = f.runner(argv, i, t)
            if argv[-1] == "-q": f.ee = False
            return r
        bc.runner = run
        self.assertTrue(bc.ee_stop()["stopped"])
        self.assertEqual([c[3:] for c in f.ee_cli()], [["-q"]])


class Devices(Base):
    def test_pwdump(self):
        d = bc.parse_pwdump(fixture("pw-dump.json"))
        self.assertEqual([m["id"] for m in d["mics"]], [55, 73])
        self.assertEqual([m["default"] for m in d["mics"]], [True, False])
        self.assertEqual(d["speakers"][0]["description"], "Built-in Audio Analog Stereo")
        self.assertIsNone(d["eeSource"])
        d = bc.parse_pwdump(json.dumps(json.loads(fixture("pw-dump.json")) + json.loads(fixture("pw-dump-ee.json"))))
        self.assertEqual(d["eeSource"]["name"], "easyeffects_source")
        self.assertEqual(len(d["mics"]), 2)   # the virtual mic and the ee_ filters are not offered

    def test_wpctl_fallback(self):
        d = bc.parse_wpctl_status(fixture("wpctl-status.txt"))
        self.assertEqual([(m["id"], m["default"]) for m in d["mics"]], [(55, True), (73, False)])
        self.assertEqual([m["id"] for m in d["speakers"]], [67, 72])
        self.assertEqual(d["eeSource"]["id"], 91); self.assertEqual(d["eeSink"]["id"], 103)

    def test_fallback_used_when_pwdump_missing(self):
        f = Fake(); install(f)
        base = f.runner
        bc.runner = lambda argv, i=None, t=15: (127, "", "") if argv[0].endswith("pw-dump") else base(argv, i, t)
        self.assertEqual(len(bc.devices()["mics"]), 2)

    def test_webcams_skip_loopback_and_metadata(self):
        self.assertEqual(bc.webcams(), [{"path": "/dev/video0", "name": "HD User Facing"}])
        self.assertTrue(bc.vcam_present())

    def test_mic_use_only_sets_default_on_click(self):
        f = Fake(); install(f)
        bc.cmd_status()
        self.assertFalse([c for c in f.calls if c[:2] == ["wpctl", "set-default"]])
        r = bc.cmd_mic_use(type("A", (), {"id": "73"}))
        self.assertTrue(r["ok"]); self.assertIn("wpctl set-default 73", f.names())
        self.assertFalse(bc.cmd_mic_use(type("A", (), {"id": "999"}))["ok"])


class Obs(Base):
    def cam(self, **kw):
        c = dict(bc.DEFAULTS["camera"], enabled=True, device="/dev/video0", effect="blur", blur=50)
        c.update(kw); return c

    def test_user_ini_merge(self):
        # OBS 31+: FirstRun lives in user.ini; without it the setup wizard opens over the desktop.
        p = os.path.join(self.home, "user.ini")
        with open(p, "w") as f:
            f.write("[General]\nPre19Defaults=false\nFirstRun=false\n\n[BasicWindow]\nPreviewEnabled=true\n\n[Other]\nX=1\n")
        bc.merge_user_ini(p)
        t = open(p).read()
        self.assertIn("FirstRun=true", t); self.assertNotIn("FirstRun=false", t)
        self.assertIn("Pre19Defaults=false", t); self.assertIn("PreviewEnabled=true", t); self.assertIn("[Other]\nX=1", t)
        self.assertIn("SysTrayMinimizeToTray=true", t)
        bc.merge_user_ini(p)
        self.assertEqual(open(p).read(), t)                                      # idempotent
        q = os.path.join(self.home, "fresh.ini"); bc.merge_user_ini(q)
        self.assertTrue(open(q).read().startswith("[General]\nFirstRun=true"))

    def test_scene_collection(self):
        sc = bc.scene_collection(self.cam(effect="replace", image="/x/bg.png", blur=80))
        self.assertEqual(sc["name"], "Ultimit Broadcast"); self.assertEqual(sc["current_scene"], "Camera")
        src = {s["name"]: s for s in sc["sources"]}
        self.assertEqual(src["Webcam"]["id"], "v4l2_input")
        self.assertEqual(src["Webcam"]["settings"]["device_id"], "/dev/video0")
        f = src["Webcam"]["filters"][0]
        self.assertEqual(f["id"], "background_removal"); self.assertTrue(f["enabled"])
        self.assertEqual(f["settings"]["blur_background"], 0)   # replace: transparent, the backdrop shows
        self.assertEqual(src["Backdrop"]["settings"]["file"], "/x/bg.png")
        items = src["Camera"]["settings"]["items"]
        self.assertEqual([i["name"] for i in items], ["Backdrop", "Webcam"])   # bottom to top
        self.assertTrue(items[0]["visible"])
        self.assertEqual(sc["sources"][0]["id"], "scene")

    def test_effects(self):
        self.assertFalse(bc.filter_enabled(self.cam(effect="off")))
        self.assertGreater(bc.filter_settings(self.cam(effect="blur", blur=50))["blur_background"], 0)
        self.assertEqual(bc.filter_settings(self.cam(effect="remove"))["blur_background"], 0)
        self.assertFalse(bc.backdrop_visible(self.cam(effect="replace", image="")))
        self.assertFalse(bc.backdrop_visible(self.cam(effect="blur", image="/a.png")))

    def test_profile_ini(self):
        ini = bc.profile_ini()
        for k in ("Name=Ultimit Broadcast", "BaseCX=1280", "OutputCY=720", "FPSCommon=30"):
            self.assertIn(k, ini)

    def test_write_files_and_ws_config_merge(self):
        p = bc.obs_paths()
        os.makedirs(os.path.dirname(p["ws"]))
        json.dump({"server_enabled": False, "alerts_enabled": True, "other": 1}, open(p["ws"], "w"))
        s = bc.load_settings(); s["camera"]["device"] = "/dev/video0"
        bc.write_obs_files(s)
        ws = json.load(open(p["ws"]))
        self.assertTrue(ws["server_enabled"]); self.assertTrue(ws["auth_required"])
        self.assertEqual(ws["server_port"], 4455); self.assertEqual(ws["other"], 1); self.assertTrue(ws["alerts_enabled"])
        pw = open(bc.secret_path()).read().strip()
        self.assertEqual(ws["server_password"], pw)
        self.assertEqual(oct(os.stat(bc.secret_path()).st_mode & 0o777), "0o600")
        self.assertEqual(bc.ws_password(), pw)
        self.assertIn("FirstRun=true", open(p["global"]).read())
        open(p["global"], "w").write("[General]\nX=1\n")
        bc.write_obs_files(s)
        self.assertEqual(open(p["global"]).read(), "[General]\nX=1\n")   # an existing global.ini is never touched
        self.assertIn("Name=Ultimit Broadcast", open(p["profile"]).read())
        self.assertEqual(json.load(open(p["scenes"]))["name"], "Ultimit Broadcast")

    def test_apply_requests(self):
        r = bc.build_apply_requests(self.cam(effect="blur", vcam=True, blur=100))
        t = [x["type"] for x in r]
        self.assertEqual(t, ["SetInputSettings", "SetInputSettings", "SetSourceFilterSettings",
                             "SetSourceFilterEnabled", "SetSceneItemEnabled", "StartVirtualCam"])
        self.assertEqual(r[2]["data"]["filterName"], "Background Removal")
        self.assertEqual(r[2]["data"]["filterSettings"]["blur_background"], 50)
        self.assertTrue(r[3]["data"]["filterEnabled"]); self.assertFalse(r[4]["data"]["sceneItemEnabled"])
        r = bc.build_apply_requests(self.cam(effect="off", vcam=False))
        self.assertFalse(r[3]["data"]["filterEnabled"]); self.assertEqual(r[-1]["type"], "StopVirtualCam")

    def test_apply_tolerates_vcam_already_in_state(self):
        f = Fake(obs=True); f.units.add("ultimit-broadcast-obs"); install(f)
        def tr(port, pw, reqs, timeout=8):
            return [{"ok": q["type"] != "StartVirtualCam", "code": 500 if q["type"] == "StartVirtualCam" else 100,
                     "comment": "", "data": {}} for q in reqs]
        obsws.transport = tr
        s = bc.load_settings(); s["camera"].update(enabled=True, vcam=True, device="/dev/video0")
        self.assertTrue(bc.apply_camera(s)["ok"])

    def test_obs_refuses_foreign_instance(self):
        f = Fake(obs=True); install(f)
        s = bc.load_settings(); s["camera"]["device"] = "/dev/video0"
        r = bc.obs_start(s)
        self.assertFalse(r["ok"]); self.assertIn("already running", r["error"])
        self.assertFalse([c for c in f.calls if c[0] == "systemd-run"])

    def test_obs_command(self):
        c = bc.obs_command(True)
        self.assertEqual(c[:3], ["flatpak", "run", "com.obsproject.Studio"])
        for x in ("--startvirtualcam", "--minimize-to-tray", "--disable-updater"):
            self.assertIn(x, c)
        self.assertEqual(c[c.index("--profile") + 1], "Ultimit Broadcast")
        self.assertNotIn("--startvirtualcam", bc.obs_command(False))


class Protocol(unittest.TestCase):
    def test_auth_string(self):   # vector from the obs-websocket protocol docs flow, computed independently
        import hashlib
        pw, salt, ch = "supersecretpassword", "lM1GncleQOaCu9lT1yeUZhFYnqhsLLP1G5lAGo3ixaI=", "+IxH4CnCiqpX1rM9scsNynZzbOe4KhDeYcTNS3PDaeY="
        sec = base64.b64encode(hashlib.sha256((pw + salt).encode()).digest()).decode()
        want = base64.b64encode(hashlib.sha256((sec + ch).encode()).digest()).decode()
        self.assertEqual(obsws.auth_string(pw, salt, ch), want)
        self.assertEqual(want, "1Ct943GAT+6YQUUX47Ia/ncufilbe6+oD6lY+5kaCu4=")

    def test_encode_and_identify(self):
        m = json.loads(obsws.encode_request(obsws.request("SetCurrentProgramScene", sceneName="Camera"), "id1"))
        self.assertEqual(m, {"op": 6, "d": {"requestType": "SetCurrentProgramScene", "requestId": "id1",
                                            "requestData": {"sceneName": "Camera"}}})
        self.assertNotIn("requestData", json.loads(obsws.encode_request(obsws.request("GetVersion"), "i"))["d"])
        i = json.loads(obsws.identify_message({"authentication": {"salt": "s", "challenge": "c"}}, "pw"))
        self.assertEqual(i["op"], 1); self.assertIn("authentication", i["d"])
        with self.assertRaises(obsws.ObsError):
            obsws.identify_message({"authentication": {"salt": "s", "challenge": "c"}}, "")

    def test_real_socket_against_fake_server(self):
        from websockets.asyncio.server import serve
        port, got = free_port(), []

        async def handler(ws):
            await ws.send(json.dumps({"op": 0, "d": {"rpcVersion": 1, "authentication": {"salt": "S", "challenge": "C"}}}))
            ident = json.loads(await ws.recv())
            if ident["d"].get("authentication") != obsws.auth_string("pw", "S", "C"):
                await ws.close(4009); return
            await ws.send(json.dumps({"op": 2, "d": {}}))
            async for raw in ws:
                m = json.loads(raw)["d"]; got.append(m["requestType"])
                await ws.send(json.dumps({"op": 7, "d": {"requestType": m["requestType"], "requestId": m["requestId"],
                                                          "requestStatus": {"result": True, "code": 100}, "responseData": {"n": len(got)}}}))

        async def main():
            async with serve(handler, "127.0.0.1", port):
                loop = asyncio.get_running_loop()
                ok = await loop.run_in_executor(None, lambda: obsws.default_transport(port, "pw", [obsws.request("A"), obsws.request("B")], 5))
                bad = await loop.run_in_executor(None, lambda: self.try_call(port))
                return ok, bad
        ok, bad = asyncio.run(main())
        self.assertEqual([r["data"]["n"] for r in ok], [1, 2]); self.assertEqual(got, ["A", "B"])
        self.assertTrue(bad)

    def try_call(self, port):
        try:
            obsws.default_transport(port, "wrong", [obsws.request("A")], 3); return False
        except obsws.ObsError:
            return True

    def test_unreachable(self):
        with self.assertRaises(obsws.ObsError):
            obsws.default_transport(free_port(), "x", [obsws.request("A")], 1)


class Monitor(Base):
    def test_loopback_and_pid(self):
        f = Fake(ee=True); install(f)
        p = subprocess.Popen(["sleep", "30"])
        bc.spawn = lambda argv, log="x": p.pid
        try:
            r = bc.cmd_monitor(type("A", (), {"action": "on"}))
            self.assertTrue(r["ok"], r); self.assertEqual(r["pid"], p.pid)
            lb = [c for c in f.calls if c[0].endswith("pw-loopback")] or [c for c in f.calls]
            self.assertTrue(os.path.exists(bc.pidfile("monitor")))
            self.assertEqual(bc.cmd_status()["monitor"], {"on": True, "pid": p.pid})
            self.assertTrue(bc.cmd_monitor(type("A", (), {"action": "on"}))["on"])   # already on: no second loop
            self.assertFalse(bc.cmd_monitor(type("A", (), {"action": "off"}))["on"])
            p.wait(5)
            self.assertFalse(os.path.exists(bc.pidfile("monitor")))
        finally:
            p.kill()

    def test_pid_reuse_is_not_ours(self):
        f = Fake(ee=True); install(f)
        bc.write_json(bc.pidfile("monitor"), {"loop": {"pid": os.getpid(), "started": "1"}})
        self.assertFalse(bc.cmd_status()["monitor"]["on"])
        bc.cmd_monitor(type("A", (), {"action": "off"}))   # must not kill us

    def test_needs_engine(self):
        f = Fake(ee=False); install(f)
        self.assertFalse(bc.cmd_monitor(type("A", (), {"action": "on"}))["ok"])

    def test_argv(self):
        f = Fake(ee=True); install(f)
        seen = []
        bc.spawn = lambda argv, log="x": seen.append(argv) or None
        bc.cmd_monitor(type("A", (), {"action": "on"}))
        a = seen[0]
        self.assertEqual(a[a.index("-C") + 1], "easyeffects_source")
        self.assertEqual(a[a.index("-P") + 1], "alsa_output.pci-0000_00_1f.3.analog-stereo")


class Settings(Base):
    def test_roundtrip_and_garbage(self):
        s = bc.load_settings(); s["mic"].update(enabled=True, strength="light", echo=True); bc.save_settings(s)
        self.assertEqual(bc.load_settings()["mic"], {"enabled": True, "strength": "light", "echo": True})
        open(bc.settings_path(), "w").write('{"mic": {"strength": "weird", "enabled": "yes"}, "camera": {"blur": 500}}')
        s = bc.load_settings()
        self.assertEqual(s["mic"]["strength"], "strong"); self.assertFalse(s["mic"]["enabled"]); self.assertEqual(s["camera"]["blur"], 100)

    def test_restore_camera_only_if_vcam(self):
        f = Fake(ee=True); install(f)
        s = bc.load_settings(); s["camera"].update(enabled=True, vcam=False, device="/dev/video0"); s["mic"]["enabled"] = True
        bc.save_settings(s)
        r = bc.cmd_restore()
        self.assertIsNone(r["camera"]); self.assertTrue(r["mic"]["loaded"])
        self.assertFalse([c for c in f.calls if c[0] == "systemd-run"])


@unittest.skipUnless(os.path.exists(os.path.join(HERE, "fixtures/preview.jpg")), "fixtures missing")
class CliFake(unittest.TestCase):
    """The real script, end to end, against the fake engines."""
    @classmethod
    def setUpClass(cls):
        cls.state = tempfile.mkdtemp(dir=TMP)
        cls.env = dict(os.environ, BROADCAST_FAKE="1", BROADCAST_FAKE_STATE=cls.state, BROADCAST_OBS_PORT=str(free_port()),
                       BROADCAST_FAKE_EE_DELAY="0.2")
        for k in ("BROADCAST_HOME", "BROADCAST_RUNTIME", "BROADCAST_V4L_DIR", "BROADCAST_BIN_DIR"):
            cls.env.pop(k, None)

    @classmethod
    def tearDownClass(cls):
        for u in ("ultimit-easyeffects", "ultimit-broadcast-obs"):
            cls.cli("x") if False else subprocess.run([os.path.join(HERE, "fixtures/bin/systemctl"), "--user", "stop", u], env=cls.env)

    @classmethod
    def cli(cls, *args):
        p = subprocess.run([sys.executable, os.path.join(HERE, "broadcast.py")] + list(args), env=cls.env,
                           capture_output=True, text=True, timeout=90)
        try:
            return json.loads(p.stdout)
        except ValueError:
            raise AssertionError("not JSON: %r %r" % (p.stdout, p.stderr))

    def f(self, name): return os.path.join(self.state, name)

    def test_full_flow(self):
        st = self.cli("status")
        self.assertTrue(st["fake"]); self.assertFalse(st["audioEngine"]["running"])
        self.assertEqual(len(st["mic"]["devices"]), 2); self.assertEqual(st["webcams"][0]["path"], "/dev/video0")
        # a mic change while the engine is stopped and the mic off never starts anything
        r = self.cli("mic", "set", "--strength", "light")
        self.assertTrue(r["ok"]); self.assertFalse(r["preset"]["loaded"])
        self.assertFalse(os.path.exists(self.f("ee.pid")))
        # switching on starts the engine and loads the preset
        r = self.cli("mic", "set", "--enabled", "on", "--echo", "on")
        self.assertTrue(r["ok"], r); self.assertTrue(r["preset"]["loaded"])
        self.assertEqual(open(self.f("loaded-input")).read().strip(), "Broadcast Mic")
        preset = json.load(open(os.path.join(self.f("home"), ".var/app/com.github.wwmm.easyeffects/data/easyeffects/input/Broadcast Mic.json")))
        self.assertEqual(preset["input"]["plugins_order"], ["rnnoise#0", "speex#0"])
        self.assertTrue(self.cli("status")["audioEngine"]["running"])
        r = self.cli("speakers", "set", "--enabled", "on", "--strength", "strong")
        self.assertEqual(open(self.f("loaded-output")).read().strip(), "Broadcast Speakers")
        self.assertEqual(self.cli("monitor", "on")["on"], True)
        self.assertEqual(self.cli("status")["monitor"]["on"], True)
        self.assertIn("-C easyeffects_source", open(self.f("monitor.args")).read())
        self.assertFalse(self.cli("monitor", "off")["on"])
        self.assertTrue(self.cli("route", "mic")["ok"]); self.assertTrue(self.cli("status")["mic"]["routed"])
        # camera: effect saved while off does not start OBS
        r = self.cli("camera", "set", "--effect", "replace", "--image", os.path.join(HERE, "fixtures/preview.jpg"))
        self.assertTrue(r["ok"]); self.assertFalse(os.path.exists(self.f("obs.pid")))
        self.assertFalse(self.cli("camera", "preview")["ok"])
        r = self.cli("camera", "set", "--enabled", "on", "--vcam", "on")
        self.assertTrue(r["ok"], r)
        o = json.load(open(self.f("obs-state.json")))
        self.assertEqual(o["profile"], "Ultimit Broadcast"); self.assertTrue(o["vcam"])
        self.assertIn("--minimize-to-tray", o["flags"])
        self.assertTrue(o["sources"]["Webcam"]["filters"]["Background Removal"]["enabled"])
        self.assertTrue(o["items"]["1"]["enabled"])           # replace + image: backdrop visible
        st = self.cli("status")["camera"]
        self.assertTrue(st["engine"]["running"]); self.assertTrue(st["engine"]["reachable"]); self.assertTrue(st["vcamOn"])
        r = self.cli("camera", "set", "--effect", "blur", "--blur", "100", "--vcam", "off")
        self.assertTrue(r["ok"], r)
        o = json.load(open(self.f("obs-state.json")))
        self.assertEqual(o["sources"]["Webcam"]["filters"]["Background Removal"]["settings"]["blur_background"], 50)
        self.assertFalse(o["items"]["1"]["enabled"]); self.assertFalse(o["vcam"])
        r = self.cli("camera", "preview")
        self.assertTrue(r["ok"]); self.assertEqual(open(r["path"], "rb").read(), open(os.path.join(HERE, "fixtures/preview.jpg"), "rb").read())
        self.assertTrue(r["path"].startswith(self.state))     # never the real runtime dir
        # camera off quits OBS cleanly
        r = self.cli("camera", "off"); self.assertTrue(r["ok"])
        self.assertEqual(json.load(open(self.f("obs-state.json"))).get("exited"), "clean")
        self.assertFalse(self.cli("status")["camera"]["engine"]["running"])
        # restore: mic/speakers back, camera stays off (virtual camera was off)
        r = self.cli("restore"); self.assertTrue(r["ok"]); self.assertIsNone(r["camera"])
        # engine stop uses -q
        self.assertTrue(self.cli("engine", "stop")["ok"])
        self.assertFalse(self.cli("status")["audioEngine"]["running"])
        # the golden rule: the windowed EasyEffects was never started
        self.assertFalse(os.path.exists(self.f("gui-started")), "EasyEffects CLI used while it was not running")
        calls = open(self.f("calls.log")).read()
        self.assertNotIn("flatpak run com.github.wwmm.easyeffects -s", calls)


if __name__ == "__main__":
    unittest.main()
