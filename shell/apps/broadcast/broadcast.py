#!/usr/bin/env python3
"""broadcast.py - backend of BROADCAST, Ultimit's replacement for NVIDIA Broadcast (stdlib + `websockets`).

BROADCAST drives two hidden engines: EasyEffects (microphone / speaker noise removal, Flatpak
com.github.wwmm.easyeffects) and OBS Studio with the Background Removal plugin (camera effects, Flatpak
com.obsproject.Studio, output to the v4l2loopback camera "Ultimit Camera"). Every command prints one JSON object.

  broadcast.py status                         everything the UI shows (engines, devices, settings)
  broadcast.py mic set [--enabled on|off] [--strength strong|light] [--echo on|off]
  broadcast.py mic use ID                     make the microphone ID the system default (only on the user's click)
  broadcast.py speakers set [--enabled on|off] [--strength strong|light]
  broadcast.py route mic|speakers             make "Easy Effects Source/Sink" the default device (user's click)
  broadcast.py engine start|stop              the EasyEffects service (start: systemd-run --user unit
                                              ultimit-easyeffects running `flatpak run ... -w`; stop: `-q`)
  broadcast.py camera set [--enabled on|off] [--device /dev/videoN] [--effect off|blur|replace|remove]
                          [--blur 0-100] [--image PATH] [--vcam on|off]
  broadcast.py camera off                     stop the virtual camera and quit OBS (user unit ultimit-broadcast-obs)
  broadcast.py camera preview [--loop FPS]    JPEG of the result -> $XDG_RUNTIME_DIR/ultimit-broadcast-preview.jpg
  broadcast.py monitor on|off                 "hear yourself": pw-loopback easyeffects_source -> speakers
  broadcast.py restore                        at login: re-apply presets, start the camera engine only if the
                                              virtual camera was left on
  broadcast.py scenes                         (re)write the OBS profile + scene collection "Ultimit Broadcast"

The EasyEffects command line is only used while EasyEffects is running: without a running instance even
`-l` / `-s` starts its full window. Every external program goes through `runner` / `spawn` (module-level
functions; tests replace them). With BROADCAST_FAKE=1 everything is redirected to fixtures/bin (fake flatpak,
pw-dump, pgrep, pw-loopback, a fake obs-websocket server) and a private home under the fake state dir, so
the UI can be exercised without touching the real engines.
"""
import argparse
import base64
import json
import os
import re
import secrets
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import obsws  # noqa: E402

EE_APP = "com.github.wwmm.easyeffects"
OBS_APP = "com.obsproject.Studio"
MIC_PRESET = "Broadcast Mic"
SPK_PRESET = "Broadcast Speakers"
OBS_NAME = "Ultimit Broadcast"       # profile + scene collection
OBS_SCENE = "Camera"
OBS_WEBCAM = "Webcam"                # the v4l2_input source
OBS_BACKDROP = "Backdrop"            # image source behind the camera (Replace)
OBS_FILTER = "Background Removal"
OBS_FILTER_ID = "background_removal"
BACKDROP_ITEM, WEBCAM_ITEM = 1, 2    # scene item ids in the generated collection
EE_UNIT = "ultimit-easyeffects"
OBS_UNIT = "ultimit-broadcast-obs"
VCAM_NAME = "Ultimit Camera"
DEFAULT_PORT = 4455
FAKE_PORT = 14455
PREVIEW_W, PREVIEW_H = 480, 270

DEFAULTS = {
    "mic": {"enabled": False, "strength": "strong", "echo": False},
    "speakers": {"enabled": False, "strength": "strong"},
    "camera": {"enabled": False, "device": "", "effect": "blur", "blur": 60, "image": "", "vcam": False},
}


# ---------------------------------------------------------------- environment / runner

def fake():
    return os.environ.get("BROADCAST_FAKE") == "1"


def fake_state():
    return os.environ.get("BROADCAST_FAKE_STATE") or os.path.join(os.environ.get("TMPDIR", "/tmp"), "broadcast-fake-state")


def bin_dir():
    d = os.environ.get("BROADCAST_BIN_DIR")
    if not d and fake():
        d = os.path.join(HERE, "fixtures", "bin")
    return d


def program(name):
    d = bin_dir()
    return os.path.join(d, name) if d else name


def home():
    if os.environ.get("BROADCAST_HOME"):
        return os.environ["BROADCAST_HOME"]
    if fake():
        return os.path.join(fake_state(), "home")
    return os.environ.get("HOME") or os.path.expanduser("~")


def runtime_dir():
    if os.environ.get("BROADCAST_RUNTIME"):
        return os.environ["BROADCAST_RUNTIME"]
    if fake():
        return os.path.join(fake_state(), "run")
    return os.environ.get("XDG_RUNTIME_DIR") or "/tmp"


def v4l_dir():
    return os.environ.get("BROADCAST_V4L_DIR") or (os.path.join(HERE, "fixtures", "v4l") if fake() else "/sys/class/video4linux")


def obs_port():
    try:
        return int(os.environ.get("BROADCAST_OBS_PORT") or (FAKE_PORT if fake() else DEFAULT_PORT))
    except ValueError:
        return DEFAULT_PORT


def settings_path():
    return os.path.join(home(), ".config", "ultimit", "broadcast.json")


def secret_path():
    return os.path.join(home(), ".config", "ultimit", "broadcast", "obs-ws")


def preview_path():
    return os.path.join(runtime_dir(), "ultimit-broadcast-preview.jpg")


def state_dir():
    return os.path.join(runtime_dir(), "ultimit-broadcast")


def ee_data(pipeline):
    return os.path.join(home(), ".var", "app", EE_APP, "data", "easyeffects", pipeline)


def obs_config():
    return os.path.join(home(), ".var", "app", OBS_APP, "config", "obs-studio")


def default_runner(argv, input_text=None, timeout=15):
    """-> (returncode, stdout, stderr). A missing program is rc 127; a timeout rc 124."""
    try:
        p = subprocess.run(argv, input=input_text, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except FileNotFoundError:
        return 127, "", "%s: not found" % argv[0]
    except subprocess.TimeoutExpired:
        return 124, "", "%s: timed out" % argv[0]
    except OSError as e:
        return 126, "", str(e)


runner = default_runner
_children = []


def default_spawn(argv, log_name="spawn"):
    """Start a long-running program detached; -> pid, or None when it cannot be started."""
    try:
        os.makedirs(state_dir(), exist_ok=True)
        log = open(os.path.join(state_dir(), log_name + ".log"), "ab")
        p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
        _children.append(p)
        return p.pid
    except OSError:
        return None


spawn = default_spawn
sleep = time.sleep
clock = time.monotonic


def run(argv, input_text=None, timeout=15):
    return runner([program(argv[0])] + list(argv[1:]), input_text, timeout)


def start(argv, log_name):
    return spawn([program(argv[0])] + list(argv[1:]), log_name)


def unit_active(unit):
    rc, o, _ = run(["systemctl", "--user", "is-active", unit], timeout=6)
    return rc == 0 and o.strip() == "active"


def unit_start(unit, argv):
    """Run argv as a transient user service (survives this helper; --collect lets a stopped unit name be reused)."""
    rc, _, err = run(["systemd-run", "--user", "--unit=" + unit, "--collect"] + list(argv), timeout=15)
    return (True, "") if rc == 0 else (False, err.strip())


def unit_stop(unit, timeout=30):
    run(["systemctl", "--user", "stop", unit], timeout=timeout)
    return wait_until(lambda: not unit_active(unit), 5, 0.2) is not None


def wait_until(fn, timeout, step=0.25):
    end = clock() + timeout
    while True:
        v = fn()
        if v:
            return v
        if clock() >= end:
            return None
        sleep(step)


def out(o):
    sys.stdout.write(json.dumps(o))
    sys.stdout.flush()


def fail(msg, **kw):
    d = {"ok": False, "error": msg}
    d.update(kw)
    return d


# ---------------------------------------------------------------- processes (pid + start time, so a reused pid is never ours)

def proc_start(pid):
    try:
        with open("/proc/%d/stat" % pid) as f:
            s = f.read()
        rest = s[s.rindex(")") + 2:].split()
        return rest[19], rest[0]   # starttime, state
    except (OSError, ValueError, IndexError):
        return None


def proc_alive(pid, started=None):
    if not pid:
        return False
    st = proc_start(pid)
    if st is None or st[1] in ("Z", "X"):
        return False
    return started is None or st[0] == started


def read_json(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_atomic(path, data, mode=None, binary=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp%d" % os.getpid()
    with open(tmp, "wb" if binary else "w") as f:
        f.write(data)
    if mode is not None:
        os.chmod(tmp, mode)
    os.replace(tmp, path)


def write_json(path, obj, mode=None):
    write_atomic(path, json.dumps(obj, indent=2) + "\n", mode)


def pidfile(name):
    return os.path.join(state_dir(), name + ".pid")


def record_pids(name, **pids):
    d = {}
    for k, pid in pids.items():
        st = proc_start(pid) if pid else None
        d[k] = {"pid": pid, "started": st[0] if st else None} if pid else None
    write_json(pidfile(name), d)


def read_pids(name):
    d = read_json(pidfile(name), {}) or {}
    return {k: v for k, v in d.items() if v and proc_alive(v.get("pid"), v.get("started"))}


def forget_pids(name):
    try:
        os.remove(pidfile(name))
    except OSError:
        pass


def stop_pid(pid, timeout=12.0):
    """SIGTERM, wait, then SIGKILL (only for a pid BROADCAST started). -> True when gone."""
    if not proc_alive(pid):
        return True
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return True
    except OSError:
        return False
    if wait_until(lambda: not proc_alive(pid), timeout, 0.1):
        return True
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
    return bool(wait_until(lambda: not proc_alive(pid), 3, 0.1))


# ---------------------------------------------------------------- settings

def load_settings():
    raw = read_json(settings_path(), {}) or {}
    s = {k: dict(v) for k, v in DEFAULTS.items()}
    for k in s:
        if isinstance(raw.get(k), dict):
            for kk in s[k]:
                if kk in raw[k] and type(raw[k][kk]) is type(s[k][kk]):
                    s[k][kk] = raw[k][kk]
    for k in ("mic", "speakers"):
        if s[k]["strength"] not in ("strong", "light"):
            s[k]["strength"] = "strong"
    c = s["camera"]
    if c["effect"] not in ("off", "blur", "replace", "remove"):
        c["effect"] = "blur"
    c["blur"] = max(0, min(100, int(c["blur"])))
    return s


def save_settings(s):
    write_json(settings_path(), s)


def parse_bool(v):
    if isinstance(v, bool):
        return v
    t = str(v).strip().lower()
    if t in ("on", "true", "1", "yes"):
        return True
    if t in ("off", "false", "0", "no"):
        return False
    raise ValueError("expected on or off, got %r" % v)


# ---------------------------------------------------------------- devices (read-only)

def parse_pwdump(text):
    """pw-dump JSON -> {mics, speakers, eeSource, eeSink, defaultSource, defaultSink} (names are PipeWire node.name)."""
    try:
        objs = json.loads(text)
    except ValueError:
        return None
    nodes, default_src, default_sink = [], None, None
    for o in objs:
        t = o.get("type", "").rsplit(":", 1)[-1]
        if t == "Node":
            p = (o.get("info") or {}).get("props") or {}
            nodes.append((o.get("id"), p))
        elif t == "Metadata":
            for m in o.get("metadata") or []:
                v = m.get("value")
                if m.get("key") == "default.audio.source" and isinstance(v, dict):
                    default_src = v.get("name")
                elif m.get("key") == "default.audio.sink" and isinstance(v, dict):
                    default_sink = v.get("name")
    mics, spk, ee_src, ee_sink = [], [], None, None
    for nid, p in nodes:
        cls, name = p.get("media.class", ""), p.get("node.name", "")
        entry = {"id": nid, "name": name,
                 "description": p.get("node.description") or p.get("node.nick") or name}
        if name == "easyeffects_source":
            ee_src = entry
        elif name == "easyeffects_sink":
            ee_sink = entry
        elif name.startswith("ee_"):
            continue
        elif cls == "Audio/Source":
            mics.append(entry)
        elif cls == "Audio/Sink":
            spk.append(entry)
    for e in mics:
        e["default"] = e["name"] == default_src
    for e in spk:
        e["default"] = e["name"] == default_sink
    return {"mics": mics, "speakers": spk, "eeSource": ee_src, "eeSink": ee_sink,
            "defaultSource": default_src, "defaultSink": default_sink}


def parse_wpctl_status(text):
    """`wpctl status` text -> the same shape (fallback when pw-dump is missing; names are descriptions)."""
    sect, mics, spk, ee_src, ee_sink = None, [], [], None, None
    for line in text.splitlines():
        s = line.replace("│", " ").replace("├─", " ").replace("└─", " ").rstrip()
        m = re.match(r"^\s*(Sinks|Sources|Filters|Streams|Devices|Clients):\s*$", s)
        if m:
            sect = m.group(1)
            continue
        if re.match(r"^(Video|Settings)\b", s.strip()):
            sect = None
            continue
        m = re.match(r"^\s*(\*)?\s*(\d+)\.\s+(.+?)\s*(\[.*\])?\s*$", s)
        if not m or sect not in ("Sinks", "Sources", "Filters"):
            continue
        entry = {"id": int(m.group(2)), "name": m.group(3), "description": m.group(3), "default": bool(m.group(1))}
        if sect == "Filters":
            if m.group(3) == "easyeffects_source":
                ee_src = entry
            elif m.group(3) == "easyeffects_sink":
                ee_sink = entry
        elif sect == "Sources":
            mics.append(entry)
        else:
            spk.append(entry)
    ds = next((e["name"] for e in mics if e["default"]), None)
    dk = next((e["name"] for e in spk if e["default"]), None)
    return {"mics": mics, "speakers": spk, "eeSource": ee_src, "eeSink": ee_sink, "defaultSource": ds, "defaultSink": dk}


def devices():
    rc, o, _ = run(["pw-dump"], timeout=8)
    d = parse_pwdump(o) if rc == 0 else None
    if d is None:
        rc, o, _ = run(["wpctl", "status"], timeout=8)
        d = parse_wpctl_status(o) if rc == 0 else None
    return d or {"mics": [], "speakers": [], "eeSource": None, "eeSink": None, "defaultSource": None, "defaultSink": None}


def read_text(path):
    with open(path) as f:
        return f.read().strip()


def webcams():
    """[{path, name}] of the real webcams: capture nodes (index 0) except the loopback "Ultimit Camera"."""
    root, res = v4l_dir(), []
    try:
        names = sorted((n for n in os.listdir(root) if re.fullmatch(r"video\d+", n)), key=lambda n: int(n[5:]))
    except OSError:
        return res
    for n in names:
        try:
            name = read_text(os.path.join(root, n, "name"))
            idx = read_text(os.path.join(root, n, "index"))
        except OSError:
            continue
        if idx != "0" or name == VCAM_NAME or "loopback" in name.lower() or "dummy" in name.lower():
            continue
        res.append({"path": "/dev/" + n, "name": name.split(":")[0].strip() or name})
    return res


def vcam_present():
    root = v4l_dir()
    try:
        return any(read_text(os.path.join(root, n, "name")) == VCAM_NAME for n in os.listdir(root))
    except OSError:
        return False


# ---------------------------------------------------------------- EasyEffects

def plugin_noise(strength):
    """The noise removal plugin: Strong = DeepFilterNet, Light = RNNoise (same settings as the session presets)."""
    if strength == "light":
        return "rnnoise#0", {"bypass": False, "enable-vad": True, "input-gain": 0.0, "output-gain": 0.0,
                             "release": 20.0, "vad-thres": 50.0, "wet": 0.0}
    return "deepfilternet#0", {"bypass": False, "attenuation-limit": 100.0, "post-filter-beta": 0.02}


def plugin_dereverb():
    """Room echo removal: the Speex preprocessor with only dereverb on."""
    return "speex#0", {"bypass": False, "enable-denoise": False, "enable-agc": False, "enable-vad": False,
                       "enable-dereverb": True, "input-gain": 0.0, "output-gain": 0.0}


def build_preset(pipeline, enabled, strength, echo=False):
    """EasyEffects preset JSON. Off = no plugins at all (EasyEffects defaults every key not written)."""
    plugins = []
    if enabled:
        plugins.append(plugin_noise(strength))
        if echo and pipeline == "input":
            plugins.append(plugin_dereverb())
    body = {"blocklist": [], "plugins_order": [p[0] for p in plugins]}
    for pid, opts in plugins:
        body[pid] = opts
    return {pipeline: body}


def preset_path(pipeline):
    return os.path.join(ee_data(pipeline), (MIC_PRESET if pipeline == "input" else SPK_PRESET) + ".json")


def write_preset(pipeline, s):
    sec = s["mic"] if pipeline == "input" else s["speakers"]
    p = preset_path(pipeline)
    write_json(p, build_preset(pipeline, sec["enabled"], sec["strength"], sec.get("echo", False)))
    return p


def ee_pids():
    rc, o, _ = run(["pgrep", "-x", "easyeffects"], timeout=4)
    return [int(x) for x in o.split() if x.isdigit()] if rc == 0 else []


def ee_running():
    return bool(ee_pids())


def ee_ready():
    """Running and its command socket is up (a `-l` before that would start a second, windowed instance)."""
    pids = ee_pids()
    if not pids:
        return False
    if fake():
        return os.path.exists(os.path.join(fake_state(), "ee-ready"))
    for pid in pids:
        if os.path.exists("/proc/%d/root/tmp/EasyEffectsServer" % pid):   # the Flatpak sandbox's private /tmp
            return True
    d = devices()   # sockets not inspectable: fall back to the virtual nodes + the caller's settle delay
    return d["eeSource"] is not None


def ee_start():
    """Start the EasyEffects service (-w: no window) as the user unit ultimit-easyeffects. Never opens its window:
    closing that window would quit the engine."""
    if ee_running():
        return {"ok": True, "started": False}
    ok, err = unit_start(EE_UNIT, ["flatpak", "run", EE_APP, "-w"])
    if not ok:
        return fail("Could not start EasyEffects: " + err)
    if not wait_until(ee_running, 8):
        return fail("EasyEffects did not start.")
    if not wait_until(ee_ready, 25):
        return fail("EasyEffects started but is not ready yet.")
    sleep(1.0 if not fake() else 0)
    return {"ok": True, "started": True}


def ee_stop():
    if not ee_running():
        return {"ok": True, "stopped": False}
    rc, _, err = run(["flatpak", "run", EE_APP, "-q"], timeout=15)
    if not wait_until(lambda: not ee_running(), 10):
        if unit_active(EE_UNIT):
            unit_stop(EE_UNIT)
        if ee_running():
            return fail("EasyEffects did not quit: " + err.strip())
    return {"ok": True, "stopped": True}


def ee_load(name):
    """Load a preset in the RUNNING instance. Never called when EasyEffects is not running."""
    if not ee_running():
        return fail("EasyEffects is not running.")
    rc, _, err = run(["flatpak", "run", EE_APP, "-l", name], timeout=20)
    if rc != 0:
        return fail("EasyEffects could not load “%s”: %s" % (name, err.strip()))
    return {"ok": True}


def apply_preset(pipeline, s, start_engine):
    """Write the preset; start EasyEffects if wanted and load it. -> result dict"""
    path = write_preset(pipeline, s)
    name = MIC_PRESET if pipeline == "input" else SPK_PRESET
    res = {"ok": True, "preset": path, "loaded": False}
    if not ee_running():
        if not start_engine:
            res["note"] = "Audio engine stopped; the preset is saved and loads when it starts."
            return res
        r = ee_start()
        if not r["ok"]:
            res.update(ok=False, error=r["error"])
            return res
    r = ee_load(name)
    if not r["ok"]:
        res.update(ok=False, error=r["error"])
        return res
    res["loaded"] = True
    return res


def pipeline_enabled(s, pipeline):
    return s["mic" if pipeline == "input" else "speakers"]["enabled"]


def cmd_mic_set(a):
    s = load_settings()
    m = s["mic"]
    try:
        if a.enabled is not None:
            m["enabled"] = parse_bool(a.enabled)
        if a.echo is not None:
            m["echo"] = parse_bool(a.echo)
    except ValueError as e:
        return fail(str(e))
    if a.strength:
        if a.strength not in ("strong", "light"):
            return fail("strength must be strong or light")
        m["strength"] = a.strength
    save_settings(s)
    # any change while on, or switching on, starts the engine; switching off only loads when it already runs
    r = apply_preset("input", s, start_engine=m["enabled"])
    return {"ok": r["ok"], "error": r.get("error"), "mic": m, "preset": r}


def cmd_speakers_set(a):
    s = load_settings()
    m = s["speakers"]
    try:
        if a.enabled is not None:
            m["enabled"] = parse_bool(a.enabled)
    except ValueError as e:
        return fail(str(e))
    if a.strength:
        if a.strength not in ("strong", "light"):
            return fail("strength must be strong or light")
        m["strength"] = a.strength
    save_settings(s)
    r = apply_preset("output", s, start_engine=m["enabled"])
    return {"ok": r["ok"], "error": r.get("error"), "speakers": m, "preset": r}


def set_default(node):
    """wpctl set-default: changes the system default device. Only ever called for an explicit user click."""
    rc, _, err = run(["wpctl", "set-default", str(node["id"])], timeout=6)
    return {"ok": True} if rc == 0 else fail("Could not set the default device: " + err.strip())


def cmd_mic_use(a):
    d = devices()
    node = next((e for e in d["mics"] if str(e["id"]) == str(a.id)), None)
    if not node:
        return fail("That microphone is not available.")
    r = set_default(node)
    r["device"] = node
    return r


def cmd_route(a):
    d = devices()
    node = d["eeSource"] if a.what == "mic" else d["eeSink"]
    if not node:
        return fail("The audio engine is not running yet.")
    r = set_default(node)
    r["device"] = node
    return r


def cmd_engine(a):
    if a.action == "start":
        s = load_settings()
        r = ee_start()
        if r["ok"]:
            for pipe in ("input", "output"):
                if pipeline_enabled(s, pipe):
                    lr = apply_preset(pipe, s, start_engine=False)
                    if not lr["ok"]:
                        return lr
        return r
    return ee_stop()


# ---------------------------------------------------------------- hear yourself

def cmd_monitor(a):
    rec = read_pids("monitor").get("loop")
    if a.action == "off":
        if rec:
            stop_pid(rec["pid"], 4)
        forget_pids("monitor")
        return {"ok": True, "on": False}
    if rec:
        return {"ok": True, "on": True, "pid": rec["pid"]}
    if not ee_running():
        return fail("Start the audio engine first.")
    d = devices()
    if not d["eeSource"]:
        return fail("The Easy Effects microphone is not available yet.")
    sink = d["defaultSink"]
    if not sink or sink == "easyeffects_sink":
        sink = next((e["name"] for e in d["speakers"]), None)
    if not sink:
        return fail("No speakers or headphones found.")
    pid = start(["pw-loopback", "-n", "ultimit-hear-yourself", "-l", "30", "-C", "easyeffects_source", "-P", sink],
                "monitor")
    if not pid:
        return fail("Could not start the monitor.")
    sleep(0.3 if not fake() else 0.05)
    if not proc_alive(pid):
        return fail("The monitor stopped right away (see the log in the runtime folder).")
    record_pids("monitor", loop=pid)
    return {"ok": True, "on": True, "pid": pid}


# ---------------------------------------------------------------- OBS: profile + scene collection

def blur_value(strength):
    """UI 0-100 -> the filter's `blur_background` (0 = no blur, i.e. a transparent background)."""
    return 0 if strength <= 0 else int(round(5 + strength * 0.45))


def filter_settings(cam):
    blur = blur_value(cam["blur"]) if cam["effect"] == "blur" else 0
    return {"model_select": "models/mediapipe.onnx", "useGPU": "cpu", "numThreads": 2, "mask_every_x_frames": 2,
            "enable_threshold": True, "threshold": 0.5, "contour_filter": 0.05, "smooth_contour": 0.5,
            "feather": 0.0, "mask_expansion": 0, "blur_background": blur}


def filter_enabled(cam):
    return cam["effect"] in ("blur", "replace", "remove")


def backdrop_visible(cam):
    return cam["effect"] == "replace" and bool(cam["image"])


def webcam_settings(cam):
    return {"device_id": cam["device"], "buffering": True}


def backdrop_settings(cam):
    return {"file": cam["image"] or "", "unload": False}


def profile_ini():
    return "\n".join([
        "[General]", "Name=" + OBS_NAME, "",
        "[Video]", "BaseCX=1280", "BaseCY=720", "OutputCX=1280", "OutputCY=720", "FPSType=0", "FPSCommon=30",
        "ScaleType=bicubic", "ColorFormat=NV12", "ColorSpace=709", "ColorRange=Partial", "",
        "[Audio]", "SampleRate=48000", "ChannelSetup=Stereo", "",
        "[Output]", "Mode=Simple", "",
        "[SimpleOutput]", "VBitrate=2500", "StreamEncoder=x264", "RecQuality=Small", ""])


def _src(name, sid, settings, filters=None, extra=None):
    d = {"prev_ver": 536870912, "name": name, "uuid": "", "id": sid, "versioned_id": sid, "settings": settings,
         "mixers": 0, "sync": 0, "flags": 0, "volume": 1.0, "balance": 0.5, "enabled": True, "muted": False,
         "push-to-mute": False, "push-to-mute-delay": 0, "push-to-talk": False, "push-to-talk-delay": 0,
         "hotkeys": {}, "deinterlace_mode": 0, "deinterlace_field_order": 0, "monitoring_type": 0,
         "private_settings": {}}
    if filters:
        d["filters"] = filters
    if extra:
        d.update(extra)
    return d


def _uuid(seed):
    import uuid
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "ultimit-broadcast/" + seed))


def scene_collection(cam):
    """The OBS scene collection "Ultimit Broadcast": scene Camera = [Webcam (+ filter), Backdrop behind it]."""
    flt = {"prev_ver": 536870912, "name": OBS_FILTER, "id": OBS_FILTER_ID, "versioned_id": OBS_FILTER_ID,
           "enabled": filter_enabled(cam), "hotkeys": {}, "settings": filter_settings(cam)}

    def item(name, iid, visible):
        return {"name": name, "source_uuid": _uuid(name), "visible": visible, "locked": False, "rot": 0.0,
                "pos": {"x": 0.0, "y": 0.0}, "scale": {"x": 1.0, "y": 1.0}, "align": 5, "bounds_type": 2,
                "bounds_align": 0, "bounds": {"x": 1280.0, "y": 720.0}, "crop_left": 0, "crop_top": 0,
                "crop_right": 0, "crop_bottom": 0, "id": iid, "group_item_backup": False,
                "scale_filter": "disable", "blend_method": "default", "blend_type": "normal",
                "show_transition": {"duration": 0}, "hide_transition": {"duration": 0}, "private_settings": {}}
    # Items are listed bottom to top.
    scene = _src(OBS_SCENE, "scene", {"id_counter": 2, "custom_size": False,
                                      "items": [item(OBS_BACKDROP, BACKDROP_ITEM, backdrop_visible(cam)),
                                                item(OBS_WEBCAM, WEBCAM_ITEM, True)]})
    scene["uuid"] = _uuid(OBS_SCENE)
    scene["versioned_id"] = "scene"
    back = _src(OBS_BACKDROP, "image_source", backdrop_settings(cam))
    back["uuid"] = _uuid(OBS_BACKDROP)
    cam_src = _src(OBS_WEBCAM, "v4l2_input", webcam_settings(cam), [flt])
    cam_src["uuid"] = _uuid(OBS_WEBCAM)
    return {"current_scene": OBS_SCENE, "current_program_scene": OBS_SCENE, "scene_order": [{"name": OBS_SCENE}],
            "name": OBS_NAME, "sources": [scene, back, cam_src], "groups": [], "quick_transitions": [],
            "transitions": [], "saved_projectors": [], "current_transition": "Fade", "transition_duration": 300,
            "preview_locked": False, "scaling_enabled": False, "scaling_level": -8, "scaling_off_x": 0.0,
            "scaling_off_y": 0.0, "virtual-camera": {"type2": 3}, "modules": {}, "version": 2}


def obs_paths():
    base = obs_config()
    return {"profile": os.path.join(base, "basic", "profiles", "Ultimit_Broadcast", "basic.ini"),
            "scenes": os.path.join(base, "basic", "scenes", "Ultimit_Broadcast.json"),
            "global": os.path.join(base, "global.ini"),
            "user": os.path.join(base, "user.ini"),
            "ws": os.path.join(base, "plugin_config", "obs-websocket", "config.json")}


GLOBAL_INI = "\n".join(["[General]", "FirstRun=true", "ConfirmOnExit=false", "EnableAutoUpdates=false", "",
                        "[BasicWindow]", "SysTrayEnabled=true", "SysTrayWhenStarted=true",
                        "SysTrayMinimizeToTray=true", "ShowSystemTrayNotifications=false", ""])


def ws_password():
    """The random obs-websocket password in ~/.config/ultimit/broadcast/obs-ws (mode 600), created on first use."""
    p = secret_path()
    try:
        with open(p) as f:
            v = f.read().strip()
        if v:
            return v
    except OSError:
        pass
    v = secrets.token_urlsafe(24)
    write_atomic(p, v + "\n", 0o600)
    return v


def write_obs_files(s):
    """Our profile + collection, the websocket enabled in OBS's global config (only our keys are touched) and a
    first-run global.ini when OBS never ran. Nothing else of the user's OBS setup is modified."""
    p = obs_paths()
    write_atomic(p["profile"], profile_ini())
    write_json(p["scenes"], scene_collection(s["camera"]))
    if not os.path.exists(p["global"]):
        write_atomic(p["global"], GLOBAL_INI)
    merge_user_ini(p["user"])
    ws = read_json(p["ws"], {}) or {}
    ws.update({"first_load": False, "server_enabled": True, "server_port": obs_port(), "auth_required": True,
               "server_password": ws_password()})
    ws.setdefault("alerts_enabled", False)
    write_json(p["ws"], ws)
    return p


# OBS 31+ reads these from user.ini (global.ini only on first ever start): without FirstRun the
# auto-configuration wizard opens over the desktop, and the tray keys keep the hidden engine hidden.
USER_INI_KEYS = {"General": {"FirstRun": "true", "ConfirmOnExit": "false"},
                 "BasicWindow": {"SysTrayEnabled": "true", "SysTrayWhenStarted": "true",
                                 "SysTrayMinimizeToTray": "true", "ShowSystemTrayNotifications": "false"}}


def merge_user_ini(path):
    """Set USER_INI_KEYS in OBS's user.ini, keeping every other line as it is."""
    try:
        with open(path, encoding="utf-8-sig") as f:
            lines = f.read().splitlines()
    except OSError:
        lines = []
    todo = {sec: dict(keys) for sec, keys in USER_INI_KEYS.items()}
    out, sec = [], None

    def flush(section):
        for k, v in todo.pop(section, {}).items():
            out.append("%s=%s" % (k, v))

    for line in lines:
        m = re.match(r"^\[(.+)\]\s*$", line)
        if m:
            if sec in todo:
                while out and out[-1] == "":
                    out.pop()
                flush(sec)
                out.append("")
            sec = m.group(1)
        elif sec in todo and "=" in line and line.split("=", 1)[0] in todo[sec]:
            k = line.split("=", 1)[0]
            out.append("%s=%s" % (k, todo[sec].pop(k)))
            continue
        out.append(line)
    if sec in todo:
        flush(sec)
    for section in list(todo):
        out += ["", "[%s]" % section]
        flush(section)
    write_atomic(path, "\n".join(out).strip("\n") + "\n")


# ---------------------------------------------------------------- OBS: engine + websocket

def ws_call(requests, timeout=8):
    return obsws.call(requests, obs_port(), ws_password(), timeout)


def obs_pids():
    rc, o, _ = run(["pgrep", "-x", "obs"], timeout=4)
    return [int(x) for x in o.split() if x.isdigit()] if rc == 0 else []


def obs_marker():
    return os.path.join(runtime_dir(), "obs-started")


def obs_alive():
    """BROADCAST's OBS: the transient unit is active, or OBS outlived it (flatpak runs the app in its own scope,
    so the unit can end while OBS keeps running) and we recorded starting it."""
    return unit_active(OBS_UNIT) or (os.path.exists(obs_marker()) and bool(obs_pids()))


def obs_command(vcam):
    cmd = ["flatpak", "run", OBS_APP, "--profile", OBS_NAME, "--collection", OBS_NAME, "--scene", OBS_SCENE]
    if vcam:
        cmd.append("--startvirtualcam")
    return cmd + ["--minimize-to-tray", "--disable-updater", "--disable-missing-files-check"]


def obs_reachable(timeout=2):
    try:
        r = ws_call([obsws.request("GetVersion")], timeout)
        return bool(r and r[0]["ok"])
    except obsws.ObsError:
        return False


def obs_start(s):
    if obs_alive():
        return {"ok": True, "started": False}
    if obs_pids():
        return fail("OBS Studio is already running (not started by BROADCAST). Close it first, then try again.")
    write_obs_files(s)
    ok, err = unit_start(OBS_UNIT, obs_command(s["camera"]["vcam"]))
    if not ok:
        return fail("Could not start OBS Studio: " + err)

    def ready():
        if not obs_alive():
            raise RuntimeError("exited")
        return obs_reachable(2)
    try:
        up = wait_until(ready, 60, 0.5)
    except RuntimeError:
        return fail("OBS Studio quit while starting (journalctl --user -u %s)." % OBS_UNIT)
    if not up:
        obs_stop()
        return fail("OBS Studio did not become ready in time.")
    write_atomic(obs_marker(), "%d\n" % int(time.time()))
    return {"ok": True, "started": True, "pid": next(iter(obs_pids()), None)}


def obs_stop():
    was = obs_alive()
    if was and obs_reachable(1):
        try:
            ws_call([obsws.request("StopVirtualCam")], 3)
        except obsws.ObsError:
            pass
    ok = unit_stop(OBS_UNIT) if was else True   # systemctl stop = SIGTERM to the unit
    if was:
        # The unit's SIGTERM doesn't reach OBS inside flatpak's own scope: ask OBS itself to quit, then insist.
        for sig, wait in ((signal.SIGTERM, 10), (signal.SIGKILL, 3)):
            pids = obs_pids()
            if not pids:
                break
            for pid in pids:
                try:
                    os.kill(pid, sig)
                except OSError:
                    pass
            wait_until(lambda: not obs_pids(), wait, 0.25)
        ok = not obs_pids()
        try:
            os.remove(obs_marker())
        except OSError:
            pass
    return {"ok": ok, "stopped": was}


VCAM_RUNNING, VCAM_NOT_RUNNING = 500, 501


def build_apply_requests(cam):
    """The websocket requests that put a running OBS in the state `cam` describes (idempotent)."""
    r = [obsws.request("SetInputSettings", inputName=OBS_WEBCAM, inputSettings=webcam_settings(cam), overlay=True),
         obsws.request("SetInputSettings", inputName=OBS_BACKDROP, inputSettings=backdrop_settings(cam), overlay=True),
         obsws.request("SetSourceFilterSettings", sourceName=OBS_WEBCAM, filterName=OBS_FILTER,
                       filterSettings=filter_settings(cam), overlay=True),
         obsws.request("SetSourceFilterEnabled", sourceName=OBS_WEBCAM, filterName=OBS_FILTER,
                       filterEnabled=filter_enabled(cam)),
         obsws.request("SetSceneItemEnabled", sceneName=OBS_SCENE, sceneItemId=BACKDROP_ITEM,
                       sceneItemEnabled=backdrop_visible(cam))]
    r.append(obsws.request("StartVirtualCam" if cam["vcam"] else "StopVirtualCam"))
    return r


def apply_camera(s):
    cam = s["camera"]
    st = obs_start(s)
    if not st["ok"]:
        return st
    try:
        res = ws_call(build_apply_requests(cam), 15)
    except obsws.ObsError as e:
        return fail("Could not talk to OBS: %s" % e)
    for rq, rs in zip(build_apply_requests(cam), res):
        if rs["ok"]:
            continue
        if rq["type"] == "StartVirtualCam" and rs["code"] == VCAM_RUNNING:
            continue
        if rq["type"] == "StopVirtualCam" and rs["code"] == VCAM_NOT_RUNNING:
            continue
        what = "the virtual camera" if "VirtualCam" in rq["type"] else "the camera effect"
        return fail("OBS could not set up %s: %s" % (what, rs["comment"] or "error %s" % rs["code"]), code=rs["code"])
    return {"ok": True, "started": st.get("started", False)}


def cmd_camera_set(a):
    s = load_settings()
    c = s["camera"]
    try:
        if a.enabled is not None:
            c["enabled"] = parse_bool(a.enabled)
        if a.vcam is not None:
            c["vcam"] = parse_bool(a.vcam)
    except ValueError as e:
        return fail(str(e))
    if a.vcam is not None and c["vcam"]:
        c["enabled"] = True
    if a.enabled is not None and not c["enabled"]:
        c["vcam"] = False
    if a.device is not None:
        if a.device and a.device not in [w["path"] for w in webcams()]:
            return fail("That camera is not available.")
        c["device"] = a.device
    if a.effect:
        if a.effect not in ("off", "blur", "replace", "remove"):
            return fail("effect must be off, blur, replace or remove")
        c["effect"] = a.effect
    if a.blur is not None:
        c["blur"] = max(0, min(100, a.blur))
    if a.image is not None:
        if a.image and not os.path.isfile(a.image):
            return fail("That image file does not exist.")
        c["image"] = a.image
    if c["enabled"] and not c["device"]:
        cams = webcams()
        if not cams:
            return fail("No webcam found.")
        c["device"] = cams[0]["path"]
    save_settings(s)
    if not c["enabled"]:
        r = obs_stop() if obs_alive() else {"ok": True}
        return {"ok": r["ok"], "camera": c}
    if not vcam_present() and c["vcam"]:
        pass   # OBS reports it; the UI shows the hint from status
    r = apply_camera(s)
    r["camera"] = c
    return r


def cmd_camera_off(a):
    s = load_settings()
    s["camera"]["enabled"] = False
    s["camera"]["vcam"] = False
    save_settings(s)
    r = obs_stop()
    r["camera"] = s["camera"]
    return r


def screenshot_request():
    return obsws.request("GetSourceScreenshot", sourceName=OBS_SCENE, imageFormat="jpg", imageWidth=PREVIEW_W,
                         imageHeight=PREVIEW_H, imageCompressionQuality=60)


def save_preview(result, path):
    data = result["data"].get("imageData", "")
    if not result["ok"] or "," not in data:
        return False
    write_atomic(path, base64.b64decode(data.split(",", 1)[1]), binary=True)
    return True


def cmd_camera_preview(a):
    if not obs_alive():
        return fail("The camera engine is not running.")
    try:
        res = ws_call([screenshot_request()], 5)
    except obsws.ObsError as e:
        return fail("Could not talk to OBS: %s" % e)
    if not save_preview(res[0], preview_path()):
        return fail("OBS gave no picture: %s" % res[0]["comment"])
    return {"ok": True, "path": preview_path()}


def preview_loop(fps):
    """Long-running: one websocket session, a JPEG per tick; one JSON line per frame on stdout."""
    import asyncio
    import json as _json
    import uuid

    async def go():
        from websockets.asyncio.client import connect
        async with connect("ws://127.0.0.1:%d" % obs_port(), open_timeout=5, max_size=16 * 1024 * 1024) as ws:
            hello = _json.loads(await ws.recv())
            await ws.send(obsws.identify_message(hello["d"], ws_password()))
            if _json.loads(await ws.recv()).get("op") != 2:
                raise obsws.ObsError("OBS refused the login")
            n = 0
            while True:
                t0 = time.monotonic()
                rid = uuid.uuid4().hex
                await ws.send(obsws.encode_request(screenshot_request(), rid))
                while True:
                    msg = _json.loads(await ws.recv())
                    if msg.get("op") == 7 and msg["d"].get("requestId") == rid:
                        break
                if save_preview(obsws.parse_result(msg["d"]), preview_path()):
                    n += 1
                    out({"ok": True, "seq": n})
                    sys.stdout.write("\n")
                    sys.stdout.flush()
                await asyncio.sleep(max(0.02, 1.0 / fps - (time.monotonic() - t0)))
    try:
        asyncio.run(go())
    except Exception as e:
        out(fail("%s: %s" % (type(e).__name__, e)))
        sys.stdout.write("\n")
    return None


# ---------------------------------------------------------------- status / restore

def cmd_status(a=None):
    s = load_settings()
    d = devices()
    pids = ee_pids()
    cams = webcams()
    cam = s["camera"]
    rec = obs_alive()
    vcam_on, reachable = None, False
    if rec:
        try:
            r = ws_call([obsws.request("GetVirtualCamStatus")], 1.5)
            reachable = bool(r and r[0]["ok"])
            vcam_on = r[0]["data"].get("outputActive") if reachable else None
        except obsws.ObsError:
            pass
    mic_phys = next((e for e in d["mics"] if e["default"]), d["mics"][0] if d["mics"] else None)
    spk_phys = next((e for e in d["speakers"] if e["default"]), d["speakers"][0] if d["speakers"] else None)
    mon = read_pids("monitor").get("loop")
    return {
        "ok": True, "fake": fake(),
        "audioEngine": {"running": bool(pids), "pid": pids[0] if pids else None},
        "mic": dict(s["mic"], device=mic_phys, devices=d["mics"], eeNode=d["eeSource"],
                    routed=bool(d["eeSource"]) and d["defaultSource"] == "easyeffects_source",
                    defaultIsPhysical=mic_phys is not None and mic_phys["default"], preset=preset_path("input")),
        "speakers": dict(s["speakers"], device=spk_phys, devices=d["speakers"], eeNode=d["eeSink"],
                         routed=bool(d["eeSink"]) and d["defaultSink"] == "easyeffects_sink",
                         preset=preset_path("output")),
        "webcams": cams,
        "camera": dict(cam, device=cam["device"] or (cams[0]["path"] if cams else ""),
                       engine={"running": bool(rec), "reachable": reachable, "pid": next(iter(obs_pids()), None) if rec else None},
                       vcamOn=vcam_on, vcamDevicePresent=vcam_present(), previewPath=preview_path()),
        "monitor": {"on": bool(mon), "pid": mon["pid"] if mon else None},
        "settingsPath": settings_path(),
    }


def cmd_restore(a=None):
    s = load_settings()
    res = {"ok": True, "mic": None, "speakers": None, "camera": None}
    for pipe, key in (("input", "mic"), ("output", "speakers")):
        if s[key]["enabled"]:
            res[key] = apply_preset(pipe, s, start_engine=True)
            res["ok"] = res["ok"] and res[key]["ok"]
    if s["camera"]["enabled"] and s["camera"]["vcam"]:
        res["camera"] = apply_camera(s)
        res["ok"] = res["ok"] and res["camera"]["ok"]
    return res


def cmd_scenes(a=None):
    p = write_obs_files(load_settings())
    return {"ok": True, "paths": p}


# ---------------------------------------------------------------- CLI

def build_parser():
    ap = argparse.ArgumentParser(prog="broadcast.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    sub.add_parser("restore")
    sub.add_parser("scenes")
    m = sub.add_parser("mic").add_subparsers(dest="sub", required=True)
    ms = m.add_parser("set")
    ms.add_argument("--enabled")
    ms.add_argument("--strength")
    ms.add_argument("--echo")
    mu = m.add_parser("use")
    mu.add_argument("id")
    sp = sub.add_parser("speakers").add_subparsers(dest="sub", required=True)
    ss = sp.add_parser("set")
    ss.add_argument("--enabled")
    ss.add_argument("--strength")
    r = sub.add_parser("route")
    r.add_argument("what", choices=["mic", "speakers"])
    e = sub.add_parser("engine")
    e.add_argument("action", choices=["start", "stop"])
    c = sub.add_parser("camera").add_subparsers(dest="sub", required=True)
    cs = c.add_parser("set")
    cs.add_argument("--enabled")
    cs.add_argument("--device")
    cs.add_argument("--effect")
    cs.add_argument("--blur", type=int)
    cs.add_argument("--image")
    cs.add_argument("--vcam")
    c.add_parser("off")
    cp = c.add_parser("preview")
    cp.add_argument("--loop", type=float)
    mo = sub.add_parser("monitor")
    mo.add_argument("action", choices=["on", "off"])
    return ap


def main(argv=None):
    a = build_parser().parse_args(argv)
    if a.cmd == "camera" and a.sub == "preview" and a.loop:
        preview_loop(max(0.5, min(15.0, a.loop)))
        return 0
    table = {("status", None): cmd_status, ("restore", None): cmd_restore, ("scenes", None): cmd_scenes,
             ("mic", "set"): cmd_mic_set, ("mic", "use"): cmd_mic_use, ("speakers", "set"): cmd_speakers_set,
             ("route", None): cmd_route, ("engine", None): cmd_engine, ("camera", "set"): cmd_camera_set,
             ("camera", "off"): cmd_camera_off, ("camera", "preview"): cmd_camera_preview,
             ("monitor", None): cmd_monitor}
    fn = table.get((a.cmd, getattr(a, "sub", None))) or table[(a.cmd, None)]
    res = fn(a)
    out(res)
    return 0 if res.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
