#!/usr/bin/env python3
"""firewall.py - backend of FIREWALL, the Ultimit ufw manager (stdlib only, JSON on stdout).

Everything privileged goes through the root helper /usr/libexec/ultimit/firewall-helper via pkexec
(distro/system/...; polkit action org.ultimit.firewall). Reading the state needs no password for an
admin at the computer; changes ask once (kept for a few minutes). This file only parses and decides.

  firewall.py state                      ufw on/off, rules, presets (on/off/partial), recent blocked connections
  firewall.py enable | disable           turn the firewall on / off
  firewall.py preset ID on|off           allow / stop allowing a preset (VTube Studio, Steam Remote Play, ...)
  firewall.py allow PORT PROTO FROM [--comment C]   FROM: lan | any | CIDR; PROTO: tcp | udp | any
  firewall.py remove "RULE LINE"         a line of `ufw show added`, as `state` listed it
  firewall.py setup-commands             the exact privileged commands of the setup steps, for display
  firewall.py setup install-ufw|install-helper

A dismissed password prompt is {ok:false, cancelled:true}, not an error. Every external program goes
through `runner` (tests replace it). FIREWALL_FAKE=1 runs the real helper without pkexec against the
fake ufw/journalctl in fixtures/bin (see fixtures/), so the UI can be tried without root.
"""
import ipaddress
import json
import os
import re
import shlex
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
SYSTEM = os.path.join(ROOT, "distro", "system")
HELPER = "/usr/libexec/ultimit/firewall-helper"
SYSTEM_FILES = [  # (path under /, mode): what install-helper copies from distro/system
    (HELPER, "755"),
    ("/usr/share/polkit-1/actions/org.ultimit.firewall.policy", "644"),
    ("/usr/share/polkit-1/rules.d/50-ultimit-firewall.rules", "644"),
]
SKIP_IFACE = re.compile(r"^(lo|docker\d*|veth.*|br-.*|virbr.*|tun\d*|tap.*|wg.*|tailscale.*|zt.*|vmnet.*)$")
# Chatter every LAN has; never worth a rule when it arrives as broadcast/multicast.
NOISE_PORTS = {67, 68, 137, 138, 1900, 3702, 5353, 5355}

# Ready-made rules. Each opens its ports to the home network only.
PRESETS = [
    {"id": "vtube-studio", "group": "VTuber tracking", "name": "VTube Studio phone tracking",
     "desc": "The VTube Studio app on an iPhone or Android phone sending face tracking to VTube Studio here.",
     "ports": [{"port": "25565", "proto": "tcp"}, {"port": "25565", "proto": "udp"}]},
    {"id": "ifacialmocap", "group": "VTuber tracking", "name": "iFacialMocap tracking",
     "desc": "iPhone face tracking for VBridger, VSeeFace and Warudo (the iFacialMocap protocol).",
     "ports": [{"port": "49983", "proto": "udp"}]},
    {"id": "vmc", "group": "VTuber tracking", "name": "VMC protocol",
     "desc": "Motion data between VSeeFace, VNyan, Warudo and phone or webcam trackers on other devices.",
     "ports": [{"port": "39539:39540", "proto": "udp"}]},
    {"id": "steam", "group": "Games", "name": "Steam Remote Play and LAN transfers",
     "desc": "Stream games from this PC to a Steam Deck, TV or phone, and copy games between PCs at home.",
     "ports": [{"port": "27031:27036", "proto": "udp"}, {"port": "27036:27037", "proto": "tcp"}, {"port": "27040", "proto": "tcp"}]},
    {"id": "sunshine", "group": "Games", "name": "Sunshine game streaming",
     "desc": "Let Moonlight on another device stream games from Sunshine on this PC.",
     "ports": [{"port": "47984,47989,48010", "proto": "tcp"}, {"port": "47998:48000,48002,48010", "proto": "udp"}]},
    {"id": "obs-websocket", "group": "Streaming", "name": "OBS remote control",
     "desc": "obs-websocket: control OBS from a phone, tablet or stream deck app on another device.",
     "ports": [{"port": "4455", "proto": "tcp"}]},
    {"id": "kdeconnect", "group": "Phones and devices", "name": "KDE Connect",
     "desc": "Phone notifications, file sending and remote input with KDE Connect or GSConnect.",
     "ports": [{"port": "1714:1764", "proto": "tcp"}, {"port": "1714:1764", "proto": "udp"}]},
    {"id": "localsend", "group": "Phones and devices", "name": "LocalSend",
     "desc": "Send files between this PC and phones or other computers with LocalSend.",
     "ports": [{"port": "53317", "proto": "tcp"}, {"port": "53317", "proto": "udp"}]},
    {"id": "ssh", "group": "Remote access", "name": "Remote login (SSH)",
     "desc": "Log in to this computer from another one with ssh.",
     "ports": [{"port": "22", "proto": "tcp"}]},
]


# ---------------------------------------------------------------- environment / runner

def fake():
    return os.environ.get("FIREWALL_FAKE") == "1"


def fake_state():
    return os.environ.get("FIREWALL_FAKE_STATE") or os.path.join(os.environ.get("TMPDIR", "/tmp"), "firewall-fake-state")


def system_root():
    """Where the installed system files are looked for ("/" normally; the fake state in fake mode)."""
    return os.path.join(fake_state(), "root") if fake() else os.environ.get("FIREWALL_SYSROOT", "/")


def ufw_apps_dir():
    return os.environ.get("FIREWALL_UFW_APPS") or os.path.join(system_root(), "etc/ufw/applications.d")


def helper_installed():
    return all(os.path.exists(os.path.join(system_root(), p.lstrip("/"))) for p, _ in SYSTEM_FILES)


def default_runner(argv, input_text=None, timeout=30):
    """-> (returncode, stdout, stderr). A missing program is rc 127; a timeout rc 124."""
    env = None
    if fake():
        b = os.path.join(HERE, "fixtures", "bin")
        env = dict(os.environ, FIREWALL_UFW=os.path.join(b, "ufw"), FIREWALL_JOURNALCTL=os.path.join(b, "journalctl"))
        if os.path.exists(os.path.join(b, argv[0])):
            argv = [os.path.join(b, argv[0])] + list(argv[1:])
    try:
        p = subprocess.run(argv, input=input_text, capture_output=True, text=True, timeout=timeout, env=env)
        return p.returncode, p.stdout, p.stderr
    except FileNotFoundError:
        return 127, "", "%s: not found" % argv[0]
    except subprocess.TimeoutExpired:
        return 124, "", "%s: timed out" % argv[0]
    except OSError as e:
        return 126, "", str(e)


runner = default_runner


def out(o):
    sys.stdout.write(json.dumps(o))
    sys.stdout.flush()


def pk(argv, input_text=None, timeout=600):
    """Run argv through pkexec (directly in fake mode). -> (ok, cancelled, stdout, message)."""
    if fake():
        if os.environ.get("FIREWALL_FAKE_CANCEL") == "1":
            return False, True, "", "Cancelled. Nothing was changed."
        if argv[0] == HELPER:
            argv = [sys.executable, os.path.join(SYSTEM, HELPER.lstrip("/"))] + argv[1:]
        rc, o, e = runner(argv, input_text, timeout)
    else:
        rc, o, e = runner(["pkexec"] + argv, input_text, timeout)
    if rc == 0:
        return True, False, o, ""
    if rc in (126, 127) and not o.strip():
        # 126: prompt dismissed / not authorized, 127: authorization could not be obtained.
        return False, True, o, "Cancelled. Nothing was changed."
    msg = (e or o).strip().splitlines()
    return False, False, o, (msg[-1] if msg else "The command failed (exit %d)." % rc)


def helper(args, req=None):
    """Call the root helper; -> its JSON (+cancelled)."""
    ok, cancelled, o, msg = pk([HELPER] + args, json.dumps(req) if req is not None else None)
    if cancelled:
        return {"ok": False, "cancelled": True, "error": msg}
    try:
        r = json.loads(o)
    except ValueError:
        return {"ok": False, "error": msg or "The firewall helper did not answer."}
    if not ok and r.get("ok") is not False:
        r = {"ok": False, "error": msg}
    return r


# ---------------------------------------------------------------- network

def lan():
    """-> {ip, subnet, addrs: [ip...]} of the default-route interface (falls back to any LAN address)."""
    rc, o, _ = runner(["ip", "-j", "addr"])
    try:
        data = json.loads(o) if rc == 0 else []
    except ValueError:
        data = []
    primary = None
    rc, o, _ = runner(["ip", "-j", "route"])
    try:
        primary = next((r.get("dev") for r in (json.loads(o) if rc == 0 else []) if r.get("dst") == "default"), None)
    except ValueError:
        pass
    found, mine = [], []
    for itf in data:
        name = itf.get("ifname", "")
        for a in itf.get("addr_info", []):
            if a.get("local"):
                mine.append(a["local"])
        if SKIP_IFACE.match(name) or ("UP" not in itf.get("flags", []) and itf.get("operstate") not in ("UP", "UNKNOWN")):
            continue
        for a in itf.get("addr_info", []):
            if a.get("family") != "inet" or a.get("scope") != "global":
                continue
            try:
                net = ipaddress.ip_interface("%s/%s" % (a["local"], a.get("prefixlen", 24))).network
            except (ValueError, KeyError):
                continue
            if net.is_private:
                found.append((name != primary, a["local"], str(net)))
    found.sort()
    return {"ip": found[0][1] if found else "", "subnet": found[0][2] if found else "", "addrs": mine}


# ---------------------------------------------------------------- ufw parsing

def parse_verbose(text):
    st = {"active": False, "incoming": "", "outgoing": "", "routed": "", "logging": ""}
    for line in text.splitlines():
        if line.startswith("Status:"):
            st["active"] = line.split(":", 1)[1].strip() == "active"
        elif line.startswith("Logging:"):
            st["logging"] = line.split(":", 1)[1].strip()
        elif line.startswith("Default:"):
            for m in re.finditer(r"(\w+) \((incoming|outgoing|routed)\)", line):
                st[m.group(2)] = m.group(1)
    return st


def parse_ports(spec):
    """'1714:1764,22' -> [(1714, 1764), (22, 22)]; None when it is not a port list (e.g. an app name)."""
    res = []
    for part in spec.split(","):
        m = re.match(r"^(\d+)(?::(\d+))?$", part)
        if not m:
            return None
        lo = int(m.group(1))
        res.append((lo, int(m.group(2) or lo)))
    return res


def app_profiles():
    """ufw application profiles: {name: [(ports, proto)]} (readable without root)."""
    apps = {}
    try:
        names = sorted(os.listdir(ufw_apps_dir()))
    except OSError:
        return apps
    for fn in names:
        cur = None
        try:
            with open(os.path.join(ufw_apps_dir(), fn), errors="replace") as f:
                for line in f:
                    line = line.strip()
                    m = re.match(r"^\[(.+)\]$", line)
                    if m:
                        cur = m.group(1)
                        apps[cur] = []
                    elif cur and line.startswith("ports="):
                        for item in line[6:].split("|"):
                            spec, _, proto = item.partition("/")
                            ports = parse_ports(spec)
                            if ports:
                                apps[cur].append((ports, proto or "any"))
        except OSError:
            continue
    return apps


def parse_rule(line, apps=None):
    """One line of `ufw show added` -> dict. Unknown syntax keeps `custom: true` (still listable/removable)."""
    r = {"line": line, "action": "", "dir": "in", "route": False, "iface": "", "from": "any", "to": "any",
         "ports": None, "proto": "any", "app": "", "comment": "", "custom": False}
    try:
        t = shlex.split(line)
    except ValueError:
        return dict(r, custom=True)
    if t[:1] != ["ufw"]:
        return dict(r, custom=True)
    t = t[1:]
    if t[:1] == ["route"]:
        r["route"] = True
        t = t[1:]
    if not t or t[0] not in ("allow", "deny", "reject", "limit"):
        return dict(r, custom=True)
    r["action"] = t.pop(0)
    if t[:1] and t[0] in ("in", "out"):
        r["dir"] = t.pop(0)
    if t[:1] == ["on"] and len(t) > 1:
        r["iface"] = t[1]
        t = t[2:]
    if t[:1] and t[0] in ("log", "log-all"):
        t = t[1:]
    if "comment" in t:
        i = t.index("comment")
        r["comment"] = " ".join(t[i + 1:])
        t = t[:i]
    if len(t) == 1:                     # simple form: PORT[/proto] or an app name
        spec, _, proto = t[0].partition("/")
        ports = parse_ports(spec)
        if ports is None:
            r["app"] = t[0]
        else:
            r["ports"], r["proto"] = ports, proto or "any"
        return resolve_app(r, apps)
    side = None
    while t:
        k = t.pop(0)
        if k in ("from", "to") and t:
            side = k
            r[k] = t.pop(0)
        elif k == "port" and t:
            v = t.pop(0)
            if side == "to":
                r["ports"] = parse_ports(v)
                if r["ports"] is None:
                    r["custom"] = True
            else:
                r["custom"] = True      # source-port rules: shown, never matched to presets
        elif k == "proto" and t:
            r["proto"] = t.pop(0)
        elif k == "app" and t:
            v = t.pop(0)
            if side == "to":
                r["app"] = v
            else:
                r["custom"] = True
        else:
            r["custom"] = True
            break
    return resolve_app(r, apps)


def resolve_app(r, apps):
    """An app rule gets the app profile's ports (one entry per protocol)."""
    r["appPorts"] = []
    if r["app"] and apps is not None:
        prof = apps.get(r["app"])
        if prof is None:
            r["custom"] = True
        else:
            r["appPorts"] = [{"ports": p, "proto": pr} for p, pr in prof]
    return r


def port_text(ports):
    return ",".join(str(a) if a == b else "%d:%d" % (a, b) for a, b in ports)


def summary(r):
    """Plain words for a rule: 'Allow 25565 (TCP+UDP) from 192.168.0.0/24'."""
    if r["custom"] and not r["action"]:
        return r["line"]
    verb = {"allow": "Allow", "deny": "Block", "reject": "Reject", "limit": "Allow (rate-limited)"}.get(r["action"], r["action"])
    if r["app"]:
        what = r["app"]
    elif r["ports"]:
        what = port_text(r["ports"]).replace(":", "–") + " " + ("TCP+UDP" if r["proto"] == "any" else r["proto"].upper())
    else:
        what = "everything" + ("" if r["proto"] == "any" else " " + r["proto"].upper())
    src = "anywhere" if r["from"] == "any" else r["from"]
    s = "%s %s %s %s" % (verb, what, "to" if r["dir"] == "out" else "from", "anywhere" if r["dir"] == "out" and r["to"] == "any" else src)
    if r["iface"]:
        s += " on " + r["iface"]
    if r["route"]:
        s = "Route: " + s
    return s


def source_covers(src, subnet):
    """Does a rule's source include the whole home network?"""
    if src == "any":
        return True
    if not subnet:
        return False
    try:
        return ipaddress.ip_network(subnet).subnet_of(ipaddress.ip_network(src, strict=False))
    except (ValueError, TypeError):
        return False


def rule_entries(r):
    """[(ports or None (= every port), proto)] a rule opens."""
    if r["app"]:
        return [(e["ports"], e["proto"]) for e in r["appPorts"]]
    return [(r["ports"], r["proto"])]


def covers(r, port, proto, subnet):
    """Does rule r let the home network reach `port` (int) / `proto` (tcp|udp)?"""
    if r["action"] not in ("allow", "limit") or r["dir"] != "in" or r["route"] or r["iface"] or r["to"] != "any":
        return False
    if not source_covers(r["from"], subnet):
        return False
    for ports, pr in rule_entries(r):
        if pr not in ("any", proto):
            continue
        if ports is None or any(a <= port <= b for a, b in ports):
            return True
    return False


# ---------------------------------------------------------------- presets

def preset_by_id(pid):
    return next((p for p in PRESETS if p["id"] == pid), None)


def preset_units(p):
    """[(lo, hi, proto)] of a preset."""
    return [(a, b, e["proto"]) for e in p["ports"] for a, b in parse_ports(e["port"])]


def range_covered(rules, lo, hi, proto, subnet):
    return all(any(covers(r, n, proto, subnet) for r in rules) for n in range(lo, hi + 1))


def preset_state(p, rules, subnet):
    units = preset_units(p)
    done = [range_covered(rules, a, b, pr, subnet) for a, b, pr in units]
    any_port = any(any(covers(r, n, pr, subnet) for r in rules) for a, b, pr in units for n in range(a, b + 1))
    return "on" if all(done) else ("partial" if any_port else "off")


def preset_owned(p, rules):
    """Rules that belong to the preset: its comment, or allow rules whose ports all lie inside the preset's ports."""
    units = preset_units(p)
    own = []
    for r in rules:
        if r["action"] != "allow" or r["custom"] or r["app"] or r["route"] or r["dir"] != "in":
            continue
        if r["comment"] == p["name"]:
            own.append(r)
            continue
        if r["ports"] and all(any(a <= lo and hi <= b for a, b, _ in units) for lo, hi in r["ports"]) \
                and (r["proto"] == "any" or any(pr == r["proto"] for _, _, pr in units)):
            own.append(r)
    return own


def preset_adds(p, rules, subnet):
    """Rule specs to add so the home network reaches every port of the preset (grouped per protocol)."""
    need = {}
    for e in p["ports"]:
        if not all(range_covered(rules, a, b, e["proto"], subnet) for a, b in parse_ports(e["port"])):
            need.setdefault(e["proto"], []).append(e["port"])
    return [{"port": ",".join(v), "proto": k, "from": subnet, "comment": p["name"]} for k, v in need.items()]


def port_label(port, proto):
    for p in PRESETS:
        if any(a <= port <= b and pr == proto for a, b, pr in preset_units(p)):
            return p["name"], p["id"]
    return "", ""


# ---------------------------------------------------------------- blocked connections

LOG_RE = re.compile(r"^(\d+(?:\.\d+)?)\s.*\[UFW BLOCK\](.*)$")


def parse_block(line):
    m = LOG_RE.match(line)
    if not m:
        return None
    f = dict(kv.split("=", 1) for kv in m.group(2).split() if "=" in kv)
    if "DPT" not in f or f.get("PROTO") not in ("TCP", "UDP"):
        return None
    try:
        return {"t": float(m.group(1)), "src": f.get("SRC", ""), "dst": f.get("DST", ""), "proto": f["PROTO"].lower(),
                "port": int(f["DPT"]), "iface": f.get("IN", "")}
    except ValueError:
        return None


def is_unicast(addr, subnet):
    try:
        a = ipaddress.ip_address(addr)
    except ValueError:
        return False
    if a.is_multicast or str(a) == "255.255.255.255":
        return False
    if subnet:
        try:
            if a == ipaddress.ip_network(subnet).broadcast_address:
                return False
        except ValueError:
            pass
    return True


def blocked(lines, rules, net, now=None):
    """Group [UFW BLOCK] log lines by (proto, port): who knocked, how often, when last, and whether a rule allows it now."""
    now = now or time.time()
    groups = {}
    for line in lines:
        e = parse_block(line)
        if not e or e["src"] in net["addrs"]:
            continue                                # our own multicast echo
        uni = is_unicast(e["dst"], net["subnet"])
        if not uni and e["port"] in NOISE_PORTS:
            continue
        g = groups.setdefault((e["proto"], e["port"]), {"proto": e["proto"], "port": e["port"], "count": 0, "sources": [],
                                                       "last": 0, "broadcast": True, "lan": True})
        g["count"] += 1
        g["last"] = max(g["last"], e["t"])
        g["broadcast"] = g["broadcast"] and not uni
        if e["src"] not in g["sources"]:
            g["sources"].append(e["src"])
        try:
            ip = ipaddress.ip_address(e["src"])
            local = ip.is_private or ip.is_link_local
        except ValueError:
            local = False
        g["lan"] = g["lan"] and local
    res = []
    for g in groups.values():
        g["label"], g["preset"] = port_label(g["port"], g["proto"])
        g["allowed"] = any(covers(r, g["port"], g["proto"], net["subnet"]) for r in rules)
        g["ago"] = max(0, int(now - g["last"]))
        g["sources"] = g["sources"][:6]
        res.append(g)
    res.sort(key=lambda g: (g["allowed"], -g["last"]))
    return res


# ---------------------------------------------------------------- state

def state():
    net = lan()
    base = {"ok": True, "helper": helper_installed(), "subnet": net["subnet"], "ip": net["ip"],
            "presets": [], "rules": [], "blocked": [], "ufw": {"installed": True, "active": False}}
    if not base["helper"]:
        return base
    st = helper(["status"])
    if st.get("cancelled"):
        return dict(base, locked=True)
    if not st.get("ok"):
        return dict(base, ok=False, error=st.get("error", "Could not read the firewall."))
    if not st.get("installed"):
        return dict(base, ufw={"installed": False, "active": False})
    apps = app_profiles()
    rules = [parse_rule(l, apps) for l in st.get("added", [])]
    for r in rules:
        r["text"] = summary(r)
        r["preset"] = ""
    presets = []
    for p in PRESETS:
        own = preset_owned(p, rules)
        for r in own:
            r["preset"] = r["preset"] or p["id"]
        presets.append(dict(p, state=preset_state(p, rules, net["subnet"]), rules=[r["line"] for r in own],
                            portsText=" · ".join("%s/%s" % (e["port"].replace(":", "–"), e["proto"].upper()) for e in p["ports"])))
    ufw = dict(parse_verbose(st.get("verbose", "")), installed=True)
    logging_off = ufw["logging"].startswith("off")
    return dict(base, ufw=ufw, rules=rules, presets=presets,
                blocked=blocked(st.get("log", []), rules, net),
                logNote="Logging is off in ufw, so blocked connections are not recorded." if logging_off
                        else ("" if st.get("logOk", True) else "The kernel log could not be read."))


def current_rules():
    st = helper(["status"])
    if not st.get("ok"):
        return None, st
    apps = app_profiles()
    return [parse_rule(l, apps) for l in st.get("added", [])], st


def result(r):
    o = {"ok": bool(r.get("ok")), "cancelled": bool(r.get("cancelled"))}
    if r.get("error"):
        o["error"] = r["error"]
    return o


def set_preset(pid, on):
    p = preset_by_id(pid)
    if not p:
        return {"ok": False, "error": "unknown preset"}
    subnet = lan()["subnet"]
    if on and not subnet:
        return {"ok": False, "error": "No home network found, so there is nothing to allow it from."}
    rules, st = current_rules()
    if rules is None:
        return result(st)
    if on:
        req = {"add": preset_adds(p, rules, subnet)}
    else:
        req = {"remove": [r["line"] for r in preset_owned(p, rules)]}
    if not req.get("add") and not req.get("remove"):
        return {"ok": True, "changed": 0}
    r = result(helper(["apply"], req))
    if r["ok"]:
        r["changed"] = len(req.get("add") or req.get("remove"))
    return r


def valid_source(src):
    if src == "lan":
        s = lan()["subnet"]
        return s or None
    if src == "any":
        return "any"
    try:
        return str(ipaddress.ip_network(src, strict=False))
    except ValueError:
        return None


def check_allow(port, proto):
    """-> error text or None (the helper checks again; this is for friendly messages)."""
    port = (port or "").replace(" ", "").replace("-", ":")
    if proto not in ("tcp", "udp", "any"):
        return port, "Pick TCP, UDP or both."
    ports = parse_ports(port) if port else None
    if not ports:
        return port, "Enter a port (like 25565), a range (27031-27036) or a list (80,443)."
    if any(a < 1 or b > 65535 or a > b or (a == b and ":" in port) for a, b in ports):
        return port, "Ports go from 1 to 65535, and a range starts with the lower one."
    if len(ports) > 15:
        return port, "At most 15 ports or ranges in one rule."
    if proto == "any" and (len(ports) > 1 or ports[0][0] != ports[0][1]):
        return port, "Ranges and lists need TCP or UDP; add one rule for each."
    return port, None


def allow(port, proto, src, comment=""):
    port, err = check_allow(port, proto)
    if err:
        return {"ok": False, "error": err}
    s = valid_source(src)
    if not s:
        return {"ok": False, "error": "No home network found." if src == "lan" else "Not an address or network: %s" % src}
    comment = re.sub(r"[^A-Za-z0-9 ._:()/+&-]", "", comment or "").strip()[:60]
    return result(helper(["apply"], {"add": [{"port": port, "proto": proto, "from": s, "comment": comment}]}))


def remove(line):
    return result(helper(["apply"], {"remove": [line]}))


def setup_commands():
    install = " && ".join("install -D -m %s %s %s" % (mode, shlex.quote(os.path.join(SYSTEM, p.lstrip("/"))), p)
                          for p, mode in SYSTEM_FILES)
    steps = [
        {"id": "install-ufw", "label": "Install ufw",
         "argv": ["env", "DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y", "ufw"]},
        {"id": "install-helper", "label": "Install the firewall helper", "argv": ["/bin/sh", "-ec", install]},
    ]
    for s in steps:
        s["display"] = "pkexec " + " ".join(shlex.quote(a) for a in s["argv"])
    return {"ok": True, "steps": steps}


def setup(step):
    s = next((s for s in setup_commands()["steps"] if s["id"] == step), None)
    if not s:
        return {"ok": False, "error": "unknown step"}
    argv = s["argv"]
    if fake() and step == "install-helper":   # install into the fake root instead of /
        root = system_root()
        argv = ["/bin/sh", "-ec", " && ".join("install -D -m %s %s %s" % (mode, shlex.quote(os.path.join(SYSTEM, p.lstrip("/"))),
                                                                          shlex.quote(os.path.join(root, p.lstrip("/"))))
                                               for p, mode in SYSTEM_FILES)]
    elif fake():
        argv = ["touch", os.path.join(fake_state(), "ufw-installed")]
    ok, cancelled, _, msg = pk(argv, timeout=900)
    o = {"ok": ok, "cancelled": cancelled}
    if msg:
        o["error"] = msg
    return o


# ---------------------------------------------------------------- CLI

def main(argv):
    cmd, args = (argv[0], argv[1:]) if argv else ("", [])
    comment = ""
    if "--comment" in args:
        i = args.index("--comment")
        comment = args[i + 1] if i + 1 < len(args) else ""
        args = args[:i] + args[i + 2:]
    try:
        if cmd == "state":
            out(state())
        elif cmd in ("enable", "disable"):
            out(result(helper([cmd])))
        elif cmd == "preset" and len(args) == 2 and args[1] in ("on", "off"):
            out(set_preset(args[0], args[1] == "on"))
        elif cmd == "allow" and len(args) == 3:
            out(allow(args[0], args[1], args[2], comment))
        elif cmd == "check-allow" and len(args) == 2:
            port, err = check_allow(args[0], args[1])
            out({"ok": err is None, "error": err or "", "port": port})
        elif cmd == "remove" and len(args) == 1:
            out(remove(args[0]))
        elif cmd == "setup-commands":
            out(setup_commands())
        elif cmd == "setup" and len(args) == 1:
            out(setup(args[0]))
        else:
            out({"ok": False, "error": "usage: firewall.py state|enable|disable|preset|allow|check-allow|remove|setup-commands|setup"})
            return 2
    except Exception as e:   # never leave the UI without JSON
        out({"ok": False, "error": "%s: %s" % (type(e).__name__, e)})
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
