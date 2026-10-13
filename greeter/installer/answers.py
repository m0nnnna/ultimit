#!/usr/bin/python3 -I
"""answers.py BASE.json - turn the installer screen's answers (JSON on stdin) into the config
Ubuntu's installer (subiquity) runs: /autoinstall.yaml, which it reads again after the early
commands (greeter/installer/start.sh). Runs as root in the live system.

Answers: {"disk": "/dev/nvme0n1", "mode": "erase" | "alongside", "realname": "Alex",
          "username": "alex", "hostname": "alex-pc", "password": "...",
          "wifi": {"ssid": "Home", "password": "..."} | null, "keyboard": "us",
          "timezone": "America/New_York" (probe.py net; else Ubuntu's installer looks it up)}

BASE.json is everything else (scripts/build-iso.sh writes it: source, drivers, Ultimit's late
commands). The password is hashed here (openssl) and never written down in the clear; a Wi-Fi
password goes into NetworkManager's file on the new system so it is online after the restart.

  answers.py BASE.json [OUT]      (OUT: /autoinstall.yaml)
"""
import json
import os
import re
import subprocess
import sys

RUN = "/run/ultimit-installer"
if os.getuid() != 0 and os.environ.get("INSTALLER_RUN"):   # tests
    RUN = os.environ["INSTALLER_RUN"]


def fail(msg):
    print(json.dumps({"ok": False, "error": msg}))
    sys.exit(1)


def hash_password(pw):
    p = subprocess.run(["openssl", "passwd", "-6", "-stdin"], input=pw + "\n", capture_output=True, text=True)
    h = p.stdout.strip()
    if p.returncode != 0 or not h.startswith("$6$"):
        fail("Could not prepare the password.")
    return h


def nm_wifi(ssid, password):
    """A NetworkManager connection file for the new system (Ultimit runs its network with NM)."""
    lines = ["[connection]", "id=" + ssid, "type=wifi", "", "[wifi]", "mode=infrastructure", "ssid=" + ssid, ""]
    if password:
        lines += ["[wifi-security]", "key-mgmt=wpa-psk", "psk=" + password, ""]
    lines += ["[ipv4]", "method=auto", "", "[ipv6]", "method=auto", ""]
    return "\n".join(lines)


def build(base, a):
    disk = a.get("disk") or ""
    if not re.match(r"^/dev/[\w/-]+$", disk):
        fail("No drive chosen.")
    user = a.get("username") or ""
    if not re.match(r"^[a-z][a-z0-9-]{0,31}$", user):
        fail("The user name can use small letters, digits and -, starting with a letter.")
    host = a.get("hostname") or ""
    if not re.match(r"^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$", host):
        fail("The computer name can use letters, digits and -.")
    if not a.get("password"):
        fail("Choose a password.")

    c = dict(base)
    layout = {"name": "direct", "match": {"path": disk}}
    if a.get("mode") == "alongside":
        layout["mode"] = "use_gap"      # the largest free space; nothing else on the drive is touched
    c["storage"] = {"layout": layout}
    c["identity"] = {"realname": (a.get("realname") or user).strip(), "username": user,
                     "hostname": host, "password": hash_password(a["password"])}
    c["keyboard"] = {"layout": a.get("keyboard") or "us"}
    tz = a.get("timezone") or ""
    c["timezone"] = tz if re.match(r"^[A-Za-z_]+(/[A-Za-z0-9_+-]+){0,2}$", tz) else "geoip"
    late = list(base.get("late-commands", []))
    wifi = a.get("wifi")
    if wifi and wifi.get("ssid"):
        path = RUN + "/wifi.nmconnection"
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(nm_wifi(wifi["ssid"], wifi.get("password") or ""))
        late.append("install -D -m 600 %s /target/etc/NetworkManager/system-connections/ultimit-wifi.nmconnection" % path)
    # Tell the screen the install is done, then wait for its Restart button (or for the screen to
    # be gone) before Ubuntu's installer restarts the PC
    late.append("touch %s/installed" % RUN)
    late.append("sh -c 'for i in $(seq 21600); do [ -e %s/restart ] && exit 0; "
                "pgrep -f \"[g]reeter/installer.qml\" >/dev/null || exit 0; sleep 1; done'" % RUN)
    c["late-commands"] = late
    c.pop("interactive-sections", None)
    c.pop("early-commands", None)
    return {"autoinstall": c}


def main(a):
    if len(a) < 2:
        fail("usage: answers.py BASE.json [OUT]")
    out = a[2] if len(a) > 2 else "/autoinstall.yaml"
    try:
        with open(a[1]) as f:
            base = json.load(f)
        answers = json.loads(sys.stdin.read())
    except (OSError, ValueError) as e:
        fail("Could not read the answers (%s)." % e)
    os.makedirs(RUN, exist_ok=True)
    conf = build(base, answers)
    tmp = out + ".new"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(conf, f, indent=2)   # JSON is YAML: subiquity reads it as is
    os.replace(tmp, out)
    print(json.dumps({"ok": True}))


if __name__ == "__main__":
    main(sys.argv)
