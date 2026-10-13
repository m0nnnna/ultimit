#!/usr/bin/env python3
"""fakecmd.py - stand-in for net, systemctl, ip, testparm, id, hostname, ufw and pkexec (symlinked under
those names next to it). Used with SHARES_FAKE=1 so SHARES can be exercised without Samba or root.
All state lives in $SHARES_FAKE_STATE (see make-state.sh); nothing outside it is ever touched.
SHARES_FAKE_CANCEL=1 makes pkexec behave like a dismissed prompt."""
import json, os, sys, time

S = os.environ["SHARES_FAKE_STATE"]
name = os.path.basename(sys.argv[0])
a = sys.argv[1:]


def has(f): return os.path.exists(os.path.join(S, f))
def put(f, t=""): open(os.path.join(S, f), "w").write(t)
def rm(f):
    try: os.remove(os.path.join(S, f))
    except OSError: pass
def die(msg, rc=1):
    sys.stderr.write(msg + "\n"); sys.exit(rc)


def net():
    d = os.path.join(S, "shares"); os.makedirs(d, exist_ok=True)
    if a[:2] == ["usershare", "info"]:
        for n in sorted(os.listdir(d)):
            sys.stdout.write("[%s]\n%s\n" % (n, open(os.path.join(d, n)).read()))
    elif a[:2] == ["usershare", "add"]:
        n, path, comment, acl, guest = a[2:7]
        if guest == "guest_ok=y" and has("guests_disabled"):
            die("net usershare add: guest access is not allowed")
        if os.path.exists(os.path.join(d, n.lower())):
            die("net usershare add: share name %s already exists" % n)
        open(os.path.join(d, n.lower()), "w").write("path=%s\ncomment=%s\nusershare_acl=%s,\n%s\n" % (path, comment, acl, guest.replace("guest_ok=", "guest_ok=")))
    elif a[:2] == ["usershare", "delete"]:
        try: os.remove(os.path.join(d, a[2].lower()))
        except OSError: die("net usershare delete: usershare %s does not exist" % a[2])
    else:
        die("net: unsupported", 2)


def systemctl():
    if a[:1] == ["is-active"]:
        unit = a[1]
        ok = has("active") if unit == "smbd" else has("ufw")
        print("active" if ok else "inactive"); sys.exit(0 if ok else 3)
    die("systemctl: unsupported", 2)


def pkexec():
    if os.environ.get("SHARES_FAKE_CANCEL") == "1":
        die("Error executing command as another user: Request dismissed", 126)
    time.sleep(float(os.environ.get("SHARES_FAKE_DELAY", "0.6")))
    c = a[:]
    if c[:1] == ["env"]:
        c = [x for x in c[1:] if "=" not in x]
    prog, rest = c[0], c[1:]
    if prog == "apt-get": put("installed"); put("active"); put("usershare_ok")
    elif prog == "systemctl": put("active")
    elif prog == "usermod":
        put("etc_group", "sambashare:x:123:%s\n" % rest[-1]); put("group_pending")
    elif prog == "smbpasswd":
        pw = sys.stdin.read().split("\n")
        if len(pw) < 2 or pw[0] != pw[1] or not pw[0]: die("Mismatch - password unchanged.")
    elif prog == "ufw":
        if "delete" in rest: rm("fw_rule")
        else: put("fw_rule", " ".join(rest))
    else: die("pkexec: fake does not know %s" % prog, 127)


def ip():
    if "route" in a:
        print(json.dumps([{"dst": "default", "gateway": "192.168.1.1", "dev": "wlan0"}, {"dst": "192.168.1.0/24", "dev": "wlan0"}]))
    else:
        print(json.dumps([
            {"ifname": "lo", "flags": ["LOOPBACK", "UP"], "addr_info": [{"family": "inet", "local": "127.0.0.1", "prefixlen": 8, "scope": "host"}]},
            {"ifname": "wlan0", "flags": ["UP"], "operstate": "UP", "addr_info": [{"family": "inet", "local": "192.168.1.42", "prefixlen": 24, "scope": "global"}]},
            {"ifname": "docker0", "flags": ["UP"], "operstate": "UP", "addr_info": [{"family": "inet", "local": "172.17.0.1", "prefixlen": 16, "scope": "global"}]}]))


def testparm():
    p = [x.split("=", 1)[1] for x in a if x.startswith("--parameter-name=")][0]
    if not has("installed"): die("testparm: not configured", 1)
    d = os.path.join(S, "usershares"); os.makedirs(d, exist_ok=True)
    print({"usershare path": d, "usershare max shares": "100",
           "usershare allow guests": "no" if has("guests_disabled") else "yes"}.get(p, ""))


def idc():
    g = "mino adm cdrom" + (" sambashare" if has("group") else "")
    print(g)


def ufw():
    die("ERROR: You need to be root to run this script", 1)


{"net": net, "systemctl": systemctl, "pkexec": pkexec, "ip": ip, "testparm": testparm, "id": idc,
 "hostname": lambda: print("ultimit-box"), "ufw": ufw, "smbd": lambda: None}[name]()
