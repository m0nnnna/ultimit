#!/usr/bin/env python3
"""fakecmd.py - stand-in for flatpak, pgrep, pw-dump, wpctl and pw-loopback (symlinked under those names next
to it). Used with BROADCAST_FAKE=1 so BROADCAST can be exercised without EasyEffects, OBS or PipeWire.
All state lives in $BROADCAST_FAKE_STATE; nothing outside it is ever touched. Every call is appended to
calls.log. Starting EasyEffects with anything but -w while it is not running writes the marker `gui-started`
(the real program would open its full window), which the tests assert never happens."""
import json, os, signal, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.dirname(HERE)
S = os.environ["BROADCAST_FAKE_STATE"]
os.makedirs(S, exist_ok=True)
name = os.path.basename(sys.argv[0])
a = sys.argv[1:]
EE, OBS = "com.github.wwmm.easyeffects", "com.obsproject.Studio"


def p(f): return os.path.join(S, f)
def has(f): return os.path.exists(p(f))
def put(f, t=""): open(p(f), "w").write(t)
def rm(f):
    try: os.remove(p(f))
    except OSError: pass
def alive(pid):
    try:
        os.kill(pid, 0)
        return open("/proc/%d/stat" % pid).read().rsplit(")", 1)[1].split()[0] not in ("Z", "X")
    except (OSError, ValueError): return False
def pid_of(f):
    try:
        v = int(open(p(f)).read().strip())
        return v if alive(v) else None
    except (OSError, ValueError): return None
def home(): return os.environ.get("BROADCAST_HOME") or p("home")
def log(): open(p("calls.log"), "a").write(name + " " + " ".join(a) + "\n")


def sleep_until_term(on_term=None):
    def term(*_):
        if on_term: on_term()
        sys.exit(0)
    signal.signal(signal.SIGTERM, term)
    while True: time.sleep(0.2)


def flatpak():
    if a[:1] != ["run"] or len(a) < 2: sys.exit(1)
    app, rest = a[1], a[2:]
    if app == EE:
        if rest == ["-w"]:
            if pid_of("ee.pid"): sys.exit(0)
            put("ee.pid", str(os.getpid()))
            def up(): rm("ee.pid"); rm("ee-ready")
            signal.signal(signal.SIGTERM, lambda *_: (up(), sys.exit(0)))
            time.sleep(float(os.environ.get("BROADCAST_FAKE_EE_DELAY", "0.4")))
            put("ee-ready")
            while True: time.sleep(0.2)
        if not pid_of("ee.pid"):
            put("gui-started", " ".join(rest))      # what the real EasyEffects would do: open its window
            sys.exit(0)
        if rest[:1] == ["-l"] and len(rest) == 2:
            for pipe in ("input", "output"):
                f = os.path.join(home(), ".var/app", EE, "data/easyeffects", pipe, rest[1] + ".json")
                if os.path.exists(f):
                    json.load(open(f))
                    put("loaded-" + pipe, rest[1] + "\n")
                    sys.exit(0)
            sys.stderr.write("preset not found\n"); sys.exit(1)
        if rest[:1] == ["-q"]:
            pid = pid_of("ee.pid")
            if pid: os.kill(pid, signal.SIGTERM)
            sys.exit(0)
        sys.exit(0)
    if app == OBS:
        if pid_of("obs.pid"): sys.exit(0)
        child = subprocess.Popen([sys.executable, os.path.join(FIX, "fakeobs.py")] + rest)
        put("obs.pid", str(child.pid))
        signal.signal(signal.SIGTERM, lambda *_: child.terminate())
        sys.exit(child.wait())
    sys.exit(1)


def pgrep():
    want = a[-1] if a else ""
    f = {"easyeffects": "ee.pid", "obs": "obs.pid"}.get(want)
    pid = pid_of(f) if f else None
    if want == "easyeffects" and has("ee-no-pgrep"): pid = None
    if pid: print(pid); sys.exit(0)
    sys.exit(1)


def pwdump():
    d = json.load(open(os.path.join(FIX, "pw-dump.json")))
    if pid_of("ee.pid") and has("ee-ready"):
        d += json.load(open(os.path.join(FIX, "pw-dump-ee.json")))
    for o in d:
        if o.get("type", "").endswith("Metadata"):
            for m in o["metadata"]:
                f = {"default.audio.source": "default-source", "default.audio.sink": "default-sink"}.get(m["key"])
                if f and has(f): m["value"] = {"name": open(p(f)).read().strip()}
    print(json.dumps(d))


def wpctl():
    if a[:1] == ["status"]:
        sys.stdout.write(open(os.path.join(FIX, "wpctl-status.txt")).read()); return
    if a[:1] == ["set-default"] and len(a) == 2:
        d = json.load(open(os.path.join(FIX, "pw-dump.json"))) + json.load(open(os.path.join(FIX, "pw-dump-ee.json")))
        for o in d:
            if str(o["id"]) == a[1] and o["type"].endswith("Node"):
                cls = o["info"]["props"].get("media.class", "")
                put("default-sink" if "Sink" in cls else "default-source", o["info"]["props"]["node.name"])
                return
        sys.stderr.write("Failed to set default: no such node\n"); sys.exit(1)
    sys.exit(1)


def systemd_run():
    """systemd-run --user --unit=U --collect CMD...: run CMD detached as unit U (pid in unit-U.pid)."""
    unit = next((x.split("=", 1)[1] for x in a if x.startswith("--unit=")), None)
    cmd = [x for x in a if not x.startswith("--") and x != "--user"]
    i = next(k for k, x in enumerate(a) if not x.startswith("--"))
    cmd = a[i:]
    if pid_of("unit-%s.pid" % unit):
        sys.stderr.write("Unit %s already exists.\n" % unit); sys.exit(1)
    c = subprocess.Popen([os.path.join(HERE, cmd[0])] + cmd[1:], stdin=subprocess.DEVNULL, start_new_session=True,
                         stdout=open(p("unit-%s.log" % unit), "a"), stderr=subprocess.STDOUT)
    put("unit-%s.pid" % unit, str(c.pid))
    print("Running as unit: %s.service" % unit)


def systemctl():
    rest = [x for x in a if x != "--user"]
    unit = rest[-1] if rest else ""
    pid = pid_of("unit-%s.pid" % unit)
    if rest[:1] == ["is-active"]:
        print("active" if pid else "inactive"); sys.exit(0 if pid else 3)
    if rest[:1] == ["stop"]:
        if pid:
            os.kill(pid, signal.SIGTERM)
            for _ in range(100):
                if not alive(pid): break
                time.sleep(0.1)
        rm("unit-%s.pid" % unit); sys.exit(0)
    sys.exit(1)


def loopback():
    put("monitor.args", " ".join(a))
    sleep_until_term(lambda: rm("monitor.args"))


log()
{"flatpak": flatpak, "pgrep": pgrep, "pw-dump": pwdump, "wpctl": wpctl, "pw-loopback": loopback, "systemd-run": systemd_run, "systemctl": systemctl}.get(name, lambda: sys.exit(127))()
