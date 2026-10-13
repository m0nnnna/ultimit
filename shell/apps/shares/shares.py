#!/usr/bin/env python3
"""shares.py - backend of SHARES, the Ultimit file share maker (stdlib only, JSON on stdout).

Shares folders over SMB with Samba *usershares* (`net usershare`, no root per share: the same
mechanism GNOME Files uses). Every command prints one JSON object.

  shares.py status                       what is installed / running / allowed, host + LAN addresses
  shares.py list                         current usershares
  shares.py state                        {status, shares} in one call (what the UI polls)
  shares.py check NAME PATH [--writable] [--guest]       validate without changing anything
  shares.py suggest PATH                 a valid default share name for a folder
  shares.py add NAME PATH [--writable] [--guest] [--comment C]
  shares.py remove NAME
  shares.py mark password|firewall [--subnet CIDR]   remember "already done" (cannot be verified without root)
  shares.py chmod-ow PATH                make your own folder writable for others (guest writes)
  shares.py setup-commands [--subnet CIDR]   the exact privileged commands the UI runs, for display
  shares.py setup STEP [--subnet CIDR]   STEP: install | service | group | password | firewall-allow | firewall-block
                                         (password: ONE line on stdin, never argv, never echoed or logged)

Privileged steps go through pkexec (the Ultimit polkit agent shows the prompt). A dismissed prompt
is reported as {ok:false, cancelled:true}, not as an error.

Every external program goes through `runner` (a module-level function; tests replace it). With
SHARES_BIN_DIR=<dir> programs are looked up only in that directory, and SHARES_FAKE=1 points everything
at fixtures/bin (see fixtures/) so the UI can be exercised without touching the real system.
"""
import ipaddress
import json
import os
import pwd
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GROUP = "sambashare"
RESERVED = {"global", "homes", "printers", "print$", "ipc$", "admin$", "c$", "netlogon", "sysvol", "usershares"}
BAD_NAME_CHARS = set('\\/[]:|<>+=;,*?"%')
FORBIDDEN_PATHS = {"/", "/etc", "/bin", "/boot", "/dev", "/lib", "/lib32", "/lib64", "/proc", "/root", "/run",
                   "/sbin", "/sys", "/usr", "/var"}
SENSITIVE_HOME = (".ssh", ".gnupg", ".local/share/keyrings", ".password-store", ".config/ultimit")
SKIP_IFACE = re.compile(r"^(lo|docker\d*|veth.*|br-.*|virbr.*|tun\d*|tap.*|wg.*|tailscale.*|zt.*|vmnet.*)$")


# ---------------------------------------------------------------- environment / runner

def fake():
    return os.environ.get("SHARES_FAKE") == "1"


def fake_state():
    return os.environ.get("SHARES_FAKE_STATE") or os.path.join(os.environ.get("TMPDIR", "/tmp"), "shares-fake-state")


def bin_dir():
    d = os.environ.get("SHARES_BIN_DIR")
    if not d and fake():
        d = os.path.join(HERE, "fixtures", "bin")
    return d


def program(name):
    """Path of a program; inside SHARES_BIN_DIR when set (so tests never see the real system)."""
    d = bin_dir()
    return os.path.join(d, name) if d else name


def smbd_present():
    if fake():
        return os.path.exists(os.path.join(fake_state(), "installed"))
    d = bin_dir()
    return os.path.exists(os.path.join(d, "smbd")) if d else os.path.exists("/usr/sbin/smbd")


def etc_group_path():
    return os.environ.get("SHARES_ETC_GROUP") or (os.path.join(fake_state(), "etc_group") if fake() else "/etc/group")


def ufw_apps_dir():
    return os.environ.get("SHARES_UFW_APPS") or (os.path.join(fake_state(), "ufw-apps") if fake() else "/etc/ufw/applications.d")


def home():
    return os.environ.get("HOME") or os.path.expanduser("~")


def state_dir():
    return os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(home(), ".local", "state"), "ultimit")


def pw_marker():
    return os.path.join(state_dir(), "shares-password-set")


def fw_marker():
    return os.path.join(state_dir(), "shares-firewall")


def username():
    try:
        return pwd.getpwuid(os.getuid()).pw_name
    except KeyError:
        return os.environ.get("USER", "")


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


def run(argv, input_text=None, timeout=15):
    argv = [program(argv[0])] + list(argv[1:])
    return runner(argv, input_text, timeout)


def out(o):
    sys.stdout.write(json.dumps(o))
    sys.stdout.flush()


# ---------------------------------------------------------------- validation

def validate_name(name):
    """-> error text, or None when `name` is a usable Samba share name."""
    if not name or not name.strip():
        return "Give the share a name."
    if name != name.strip():
        return "The name cannot start or end with a space."
    if len(name) > 80:
        return "The name is too long (80 characters at most)."
    bad = sorted({c for c in name if c in BAD_NAME_CHARS})
    if bad:
        return "The name cannot contain: " + " ".join(bad)
    if any(ord(c) < 32 or ord(c) == 127 for c in name):
        return "The name cannot contain control characters."
    if name.endswith("$"):
        return "Names ending in $ make hidden shares; pick a visible name."
    if name.lower() in RESERVED:
        return "“%s” is reserved by Samba; pick another name." % name
    if name.startswith("."):
        return "The name cannot start with a dot."
    return None


def sanitize_name(raw):
    s = "".join("-" if (c in BAD_NAME_CHARS or ord(c) < 32) else c for c in raw).strip(" .-")
    s = re.sub(r"-{2,}", "-", s)[:80].strip(" .-$")
    if not s or s.lower() in RESERVED:
        s = (s + " share").strip() if s else "share"
    return s


def suggest_name(path):
    p = os.path.abspath(os.path.expanduser(path or ""))
    base = os.path.basename(p.rstrip("/"))
    if p == home():
        base = "home"
    return sanitize_name(base or "share")


def inspect_path(path):
    """-> (resolved path or None, error, warnings[])"""
    warnings = []
    if not path or not path.strip():
        return None, "Choose a folder to share.", warnings
    p = os.path.abspath(os.path.expanduser(path.strip()))
    if not os.path.exists(p):
        return None, "That folder does not exist.", warnings
    if not os.path.isdir(p):
        return None, "That is a file; only folders can be shared.", warnings
    real = os.path.realpath(p)
    if real in FORBIDDEN_PATHS or p in FORBIDDEN_PATHS:
        return None, "Sharing %s would expose the system; pick a folder of your own." % real, warnings
    h = os.path.realpath(home())
    for rel in SENSITIVE_HOME:
        s = os.path.join(h, rel)
        if real == s or real.startswith(s + "/"):
            return None, "That folder holds private keys or settings and cannot be shared.", warnings
    if not os.access(p, os.R_OK | os.X_OK):
        return None, "You do not have permission to read that folder.", warnings
    if real == h or (h.startswith(real + "/") and real != "/"):
        warnings.append({"code": "wide", "message": "This shares your whole home folder (or a parent of it), including every file in it."})
    try:
        if os.stat(p).st_uid != os.getuid():
            warnings.append({"code": "not_owner", "message": "You do not own this folder; Samba may refuse to share it."})
    except OSError:
        pass
    return p, None, warnings


def check(name, path, writable=False, guest=False, existing=None):
    errors, warnings = {}, []
    e = validate_name(name)
    if e:
        errors["name"] = e
    p, e, w = inspect_path(path)
    if e:
        errors["path"] = e
    warnings += w
    if p and "name" not in errors:
        shares = existing if existing is not None else list_shares().get("shares", [])
        for s in shares:
            if s["name"].lower() == name.lower():
                errors["name"] = "A share called “%s” already exists." % s["name"]
        if any(s["path"] == p for s in shares if s["name"].lower() != name.lower()):
            warnings.append({"code": "dup_path", "message": "This folder is already shared under another name."})
    if p and guest and writable:
        try:
            if not os.stat(p).st_mode & 0o002:
                warnings.append({"code": "guest_perms", "message": "Guests write as the system user “nobody”, so the folder must be writable by everyone (o+w).", "fix": "chmod-ow"})
        except OSError:
            pass
    if guest:
        warnings.append({"code": "guest", "message": "Anyone on your network can open this share without a password."})
    return {"ok": not errors, "errors": errors, "warnings": warnings, "path": p or "", "name": name}


# ---------------------------------------------------------------- usershare parsing

def parse_usershares(text):
    """Parse `net usershare info --long` output into [{name, path, comment, writable, guest, acl}]."""
    shares, cur = [], None
    for raw in text.splitlines():
        line = raw.rstrip("\r")
        m = re.match(r"^\[(.+)\]\s*$", line)
        if m:
            cur = {"name": m.group(1), "path": "", "comment": "", "acl": "", "guest": False, "writable": False}
            shares.append(cur)
            continue
        if cur is None or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        if k == "path":
            cur["path"] = v
        elif k == "comment":
            cur["comment"] = v
        elif k == "usershare_acl":
            cur["acl"] = v
            cur["writable"] = any(e.strip().endswith(":F") for e in v.split(",") if e.strip())
        elif k == "guest_ok":
            cur["guest"] = v.strip().lower() == "y"
    return shares


def list_shares():
    rc, o, e = run(["net", "usershare", "info", "--long"])
    if rc == 127:
        return {"ok": True, "shares": [], "err": "net not installed"}
    if rc != 0:
        return {"ok": False, "shares": [], "err": (e or o).strip() or "net usershare failed"}
    return {"ok": True, "shares": parse_usershares(o)}


# ---------------------------------------------------------------- status

def testparm(param):
    rc, o, _ = run(["testparm", "-s", "--parameter-name=" + param])
    return o.strip() if rc == 0 else ""


def my_groups():
    rc, o, _ = run(["id", "-nG"])
    return o.split() if rc == 0 else []


def in_etc_group(user):
    try:
        with open(etc_group_path()) as f:
            for line in f:
                p = line.rstrip("\n").split(":")
                if p[0] == GROUP:
                    return True, user in (p[3].split(",") if len(p) > 3 else [])
    except OSError:
        pass
    return False, False


def usershare_dir_info(path):
    if not path:
        return {"path": "", "exists": False, "ok": False}
    try:
        s = os.stat(path)
    except OSError:
        return {"path": path, "exists": False, "ok": False}
    writable = os.access(path, os.W_OK | os.X_OK)
    shared_mode = bool(s.st_mode & 0o020 or s.st_mode & 0o002)   # group/other write (the group is sambashare)
    return {"path": path, "exists": True, "writable": writable, "ok": writable or shared_mode}


def lan_addresses():
    addrs = []
    rc, o, _ = run(["ip", "-j", "addr"])
    try:
        data = json.loads(o) if rc == 0 else []
    except ValueError:
        data = []
    primary = None
    rc, o, _ = run(["ip", "-j", "route"])
    try:
        for r in (json.loads(o) if rc == 0 else []):
            if r.get("dst") == "default":
                primary = r.get("dev")
                break
    except ValueError:
        pass
    for itf in data:
        name = itf.get("ifname", "")
        down = "UP" not in itf.get("flags", []) and itf.get("operstate") not in ("UP", "UNKNOWN")
        if SKIP_IFACE.match(name) or down:
            continue
        for a in itf.get("addr_info", []):
            if a.get("family") != "inet" or a.get("scope") != "global":
                continue
            try:
                net = ipaddress.ip_interface("%s/%s" % (a["local"], a.get("prefixlen", 24))).network
            except (ValueError, KeyError):
                continue
            addrs.append({"iface": name, "ip": a["local"], "subnet": str(net), "primary": name == primary})
    addrs.sort(key=lambda a: not a["primary"])
    return addrs


def ufw_has_samba_profile():
    try:
        for fn in os.listdir(ufw_apps_dir()):
            with open(os.path.join(ufw_apps_dir(), fn), errors="replace") as f:
                if re.search(r"^\[Samba\]\s*$", f.read(), re.M):
                    return True
    except OSError:
        pass
    return False


def read_marker(path):
    try:
        with open(path) as f:
            return f.read().strip() or "1"
    except OSError:
        return None


def firewall_state():
    """-> {state: none|inactive|allowed|blocked|unknown, subnet}"""
    rc, o, _ = run(["systemctl", "is-active", "ufw"])
    if rc == 127:
        return {"state": "none", "subnet": ""}
    if o.strip() != "active":
        return {"state": "inactive", "subnet": ""}
    marker = read_marker(fw_marker())
    sub = marker if marker and marker != "1" else ""
    rc, o, _ = run(["ufw", "status"])
    if rc == 0 and o.strip():
        rules = [l for l in o.splitlines() if re.search(r"\bSamba\b|\b(139|445)\b", l) and "ALLOW" in l]
        return {"state": "allowed" if rules else "blocked", "subnet": sub}
    return {"state": "allowed" if marker else "unknown", "subnet": sub}


def status():
    user = username()
    installed = smbd_present()
    rc, o, _ = run(["systemctl", "is-active", "smbd"])
    active = rc == 0 and o.strip() == "active"
    udir = testparm("usershare path")
    try:
        maxshares = int(testparm("usershare max shares") or 0)
    except ValueError:
        maxshares = 0
    guests_allowed = testparm("usershare allow guests").lower() in ("yes", "true", "1", "y")
    group_exists, in_file = in_etc_group(user)
    in_group = GROUP in my_groups()
    relogin = in_file and not in_group
    addrs = lan_addresses()
    rc, host, _ = run(["hostname"])
    host = host.strip() or "localhost"
    password = "set" if read_marker(pw_marker()) else "unknown"
    fw = firewall_state()
    d = usershare_dir_info(udir)
    enabled = bool(udir) and maxshares > 0
    ready = installed and active and enabled and d["ok"] and in_group and not relogin
    return {
        "ok": True, "user": user, "host": host, "hostUpper": host.split(".")[0].upper(),
        "installed": installed, "active": active,
        "usershare": {"enabled": enabled, "max": maxshares, "guests": guests_allowed, "dir": d},
        "group": {"exists": group_exists, "member": in_group, "inFile": in_file, "reloginNeeded": relogin},
        "password": password,
        "firewall": dict(fw, profile=ufw_has_samba_profile()),
        "addresses": addrs,
        "ready": ready,
        "canShare": ready,
    }


def state():
    return {"ok": True, "status": status(), "shares": list_shares()}


# ---------------------------------------------------------------- add / remove

def add(name, path, writable=False, guest=False, comment=""):
    c = check(name, path, writable, guest)
    if not c["ok"]:
        return {"ok": False, "error": next(iter(c["errors"].values())), "errors": c["errors"], "warnings": c["warnings"]}
    acl = "Everyone:" + ("F" if writable else "R")
    comment = re.sub(r"[\r\n]+", " ", comment or "").strip()
    rc, o, e = run(["net", "usershare", "add", name, c["path"], comment, acl, "guest_ok=" + ("y" if guest else "n")])
    if rc != 0:
        msg = (e or o).strip() or "net usershare add failed (exit %d)" % rc
        if rc == 127:
            msg = "Samba is not installed."
        return {"ok": False, "error": msg, "samba": True, "warnings": c["warnings"]}
    shares = list_shares().get("shares", [])
    mine = next((s for s in shares if s["name"].lower() == name.lower()), None)
    return {"ok": True, "share": mine or {"name": name.lower(), "path": c["path"], "comment": comment, "writable": writable, "guest": guest},
            "warnings": c["warnings"]}


def remove(name):
    if not name or not name.strip():
        return {"ok": False, "error": "No such share."}
    rc, o, e = run(["net", "usershare", "delete", name])
    if rc != 0:
        return {"ok": False, "error": (e or o).strip() or "net usershare delete failed (exit %d)" % rc}
    return {"ok": True}


def chmod_ow(path):
    p, err, _ = inspect_path(path)
    if err:
        return {"ok": False, "error": err}
    try:
        st = os.stat(p)
        if st.st_uid != os.getuid():
            return {"ok": False, "error": "You do not own this folder, so you cannot change its permissions."}
        os.chmod(p, (st.st_mode & 0o7777) | 0o002)
    except OSError as e:
        return {"ok": False, "error": e.strerror or str(e)}
    return {"ok": True}


# ---------------------------------------------------------------- privileged setup

def valid_subnet(s):
    try:
        n = ipaddress.ip_network(s, strict=False)
    except ValueError:
        return None
    if n.version != 4 or not n.is_private or n.prefixlen < 8:
        return None
    return str(n)


def firewall_argvs(subnet, allow=True, profile=True):
    """pkexec argv lists for allowing/blocking Samba from `subnet`."""
    verb = ["ufw", "allow"] if allow else ["ufw", "delete", "allow"]
    cm = ["comment", "Ultimit SHARES"] if allow else []
    if profile:
        return [["pkexec"] + verb + ["from", subnet, "to", "any", "app", "Samba"] + cm]
    return [["pkexec"] + verb + ["from", subnet, "to", "any", "port", "139,445", "proto", "tcp"] + cm,
            ["pkexec"] + verb + ["from", subnet, "to", "any", "port", "137,138", "proto", "udp"] + cm]


def setup_commands(subnet=""):
    user = username()
    sub = valid_subnet(subnet) if subnet else None
    if not sub:
        addrs = lan_addresses()
        sub = addrs[0]["subnet"] if addrs else "192.168.1.0/24"
    prof = ufw_has_samba_profile()

    def disp(argvs):
        return "\n".join(" ".join(shquote(a) for a in av) for av in argvs)
    steps = [
        {"id": "install", "label": "Install Samba", "argv": [["pkexec", "env", "DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y", "samba"]]},
        {"id": "service", "label": "Start the sharing service", "argv": [["pkexec", "systemctl", "enable", "--now", "smbd"]]},
        {"id": "group", "label": "Allow sharing for your account", "argv": [["pkexec", "usermod", "-aG", GROUP, user]]},
        {"id": "password", "label": "Set your network password", "argv": [["pkexec", "smbpasswd", "-a", "-s", user]], "stdin": "password twice (not shown)"},
        {"id": "firewall-allow", "label": "Allow on home network", "argv": firewall_argvs(sub, True, prof)},
        {"id": "firewall-block", "label": "Block again", "argv": firewall_argvs(sub, False, prof)},
    ]
    for s in steps:
        s["display"] = disp(s["argv"])
    return {"ok": True, "subnet": sub, "steps": steps}


def shquote(a):
    return a if re.match(r"^[A-Za-z0-9_@%+=:,./-]+$", a) else "'" + a.replace("'", "'\\''") + "'"


def write_marker(path, text="1"):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(text)
        os.chmod(path, 0o600)
    except OSError:
        pass


def rm_marker(path):
    try:
        os.remove(path)
    except OSError:
        pass


def pk(argv, input_text=None, timeout=900):
    """Run a pkexec command; -> (ok, cancelled, message)."""
    rc, o, e = run(argv, input_text, timeout)
    if rc == 0:
        return True, False, ""
    if rc in (126, 127) and argv[0] == "pkexec":
        # 126: prompt dismissed / not authorized, 127: authorization could not be obtained.
        if rc == 126 or "not authorized" in e.lower() or "dismissed" in e.lower() or not e.strip():
            return False, True, "Cancelled. Nothing was changed."
    msg = (e or o).strip().splitlines()
    return False, False, (msg[-1] if msg else "The command failed (exit %d)." % rc)


def setup(step, subnet="", password=None):
    user = username()
    if step == "install":
        ok, cancelled, msg = pk(["pkexec", "env", "DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y", "samba"])
    elif step == "service":
        ok, cancelled, msg = pk(["pkexec", "systemctl", "enable", "--now", "smbd"], timeout=120)
    elif step == "group":
        ok, cancelled, msg = pk(["pkexec", "usermod", "-aG", GROUP, user], timeout=120)
    elif step == "password":
        if not password or "\n" in password or "\r" in password:
            return {"ok": False, "error": "Enter a password."}
        ok, cancelled, msg = pk(["pkexec", "smbpasswd", "-a", "-s", user], password + "\n" + password + "\n", 300)
        if ok:
            write_marker(pw_marker())
    elif step in ("firewall-allow", "firewall-block"):
        sub = valid_subnet(subnet)
        if not sub:
            return {"ok": False, "error": "Not a private home network address range: %r" % subnet}
        allow = step == "firewall-allow"
        ok, cancelled, msg = True, False, ""
        for av in firewall_argvs(sub, allow, ufw_has_samba_profile()):
            ok, cancelled, msg = pk(av, timeout=120)
            if not ok:
                break
        if ok:
            if allow:
                write_marker(fw_marker(), sub)
            else:
                rm_marker(fw_marker())
    else:
        return {"ok": False, "error": "unknown step"}
    r = {"ok": ok, "cancelled": cancelled}
    if msg:
        r["error"] = msg
    if ok and step == "group":
        r["reloginNeeded"] = True
    return r


def mark(what, subnet=""):
    """The user says a step is already done (it cannot be verified without root): remember that."""
    if what == "password":
        write_marker(pw_marker())
    elif what == "firewall":
        write_marker(fw_marker(), valid_subnet(subnet) or "1")
    else:
        return {"ok": False, "error": "unknown step"}
    return {"ok": True}


# ---------------------------------------------------------------- CLI

def flag(args, name):
    return name in args


def opt(args, name, default=""):
    return args[args.index(name) + 1] if name in args and args.index(name) + 1 < len(args) else default


def positional(args):
    res, skip = [], False
    for i, a in enumerate(args):
        if skip:
            skip = False
        elif a in ("--comment", "--subnet"):
            skip = True
        elif not a.startswith("--"):
            res.append(a)
    return res


def main(argv):
    if not argv:
        out({"ok": False, "error": "usage: shares.py status|list|state|check|suggest|add|remove|chmod-ow|mark|setup-commands|setup"})
        return 2
    cmd, args = argv[0], argv[1:]
    pos = positional(args)
    try:
        if cmd == "status":
            out(status())
        elif cmd == "list":
            out(list_shares())
        elif cmd == "state":
            out(state())
        elif cmd == "check" and len(pos) >= 2:
            out(check(pos[0], pos[1], flag(args, "--writable"), flag(args, "--guest")))
        elif cmd == "suggest" and pos:
            out({"ok": True, "name": suggest_name(pos[0])})
        elif cmd == "add" and len(pos) >= 2:
            out(add(pos[0], pos[1], flag(args, "--writable"), flag(args, "--guest"), opt(args, "--comment")))
        elif cmd == "remove" and pos:
            out(remove(pos[0]))
        elif cmd == "chmod-ow" and pos:
            out(chmod_ow(pos[0]))
        elif cmd == "mark" and pos:
            out(mark(pos[0], opt(args, "--subnet")))
        elif cmd == "setup-commands":
            out(setup_commands(opt(args, "--subnet")))
        elif cmd == "setup" and pos:
            pw = sys.stdin.readline().rstrip("\n") if pos[0] == "password" else None
            out(setup(pos[0], opt(args, "--subnet"), pw))
        else:
            out({"ok": False, "error": "bad command or arguments"})
            return 2
    except Exception as e:   # never leave the UI without JSON
        out({"ok": False, "error": "%s: %s" % (type(e).__name__, e)})
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
