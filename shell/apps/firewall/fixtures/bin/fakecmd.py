#!/usr/bin/env python3
"""fakecmd.py - stand-in for ufw, journalctl and ip (symlinked under those names next to it). Used with
FIREWALL_FAKE=1 (the real firewall-helper runs unprivileged against these) and by the tests.
All state lives in $FIREWALL_FAKE_STATE (see make-state.sh); nothing outside it is ever touched:
  ufw-installed  ufw is "installed"        active     ufw is on
  added          one `ufw show added` line per rule
  log            journal lines "<seconds ago> <text>" (timestamps are made relative to now)"""
import os, shlex, sys, time

S = os.environ["FIREWALL_FAKE_STATE"]
name = os.path.basename(sys.argv[0])
a = sys.argv[1:]


def has(f): return os.path.exists(os.path.join(S, f))
def read(f):
    try: return open(os.path.join(S, f)).read().splitlines()
    except OSError: return []
def put(f, lines): open(os.path.join(S, f), "w").write("".join(l + "\n" for l in lines))
def die(msg, rc=1):
    sys.stderr.write(msg + "\n"); sys.exit(rc)


def strip_comment(line):
    t = shlex.split(line)
    return t[:t.index("comment")] if "comment" in t else t


def ufw():
    if not has("ufw-installed"):
        die("ufw: not found", 127)
    if a[:2] == ["status", "verbose"]:
        if not has("active"):
            print("Status: inactive"); return
        print("Status: active\nLogging: %s\nDefault: deny (incoming), allow (outgoing), disabled (routed)\nNew profiles: skip\n"
              % ("off" if has("logging-off") else "on (low)"))
    elif a[:2] == ["show", "added"]:
        rules = read("added")
        print("Added user rules (see 'ufw status' for running firewall):")
        print("\n".join(rules) if rules else "(None)")
    elif a == ["--force", "enable"]:
        put("active", []); print("Firewall is active and enabled on system startup")
    elif a == ["disable"]:
        try: os.remove(os.path.join(S, "active"))
        except OSError: pass
        print("Firewall stopped and disabled on system startup")
    elif a[:1] == ["allow"]:
        t = list(a)
        if "comment" in t:
            i = t.index("comment"); t = t[:i] + ["comment", "'%s'" % t[i + 1]]
        line = "ufw " + " ".join(t)
        rules = read("added")
        if any(strip_comment(r) == strip_comment(line) for r in rules):
            print("Skipping adding existing rule"); return
        put("added", rules + [line]); print("Rule added")
    elif a[:1] == ["delete"]:
        want = ["ufw"] + a[1:]
        rules = read("added")
        keep = [r for r in rules if strip_comment(r) != want]
        if len(keep) == len(rules):
            die("Could not delete non-existent rule")
        put("added", keep); print("Rule deleted")
    else:
        die("ufw: fake does not know: " + " ".join(a), 2)


def journalctl():
    now = time.time()
    for l in read("log"):
        ago, _, text = l.partition(" ")
        print("%.6f %s" % (now - float(ago), text))


def ip():
    import json
    if "route" in a:
        print(json.dumps([{"dst": "default", "gateway": "192.168.1.1", "dev": "wlan0"}]))
    else:
        print(json.dumps([
            {"ifname": "lo", "flags": ["LOOPBACK", "UP"], "addr_info": [{"family": "inet", "local": "127.0.0.1", "prefixlen": 8, "scope": "host"}]},
            {"ifname": "wlan0", "flags": ["UP"], "operstate": "UP", "addr_info": [{"family": "inet", "local": "192.168.1.42", "prefixlen": 24, "scope": "global"}]}]))


{"ufw": ufw, "journalctl": journalctl, "ip": ip}[name]()
