#!/usr/bin/python3 -I
"""updates.py - what Settings > Updates shows. Unprivileged; one JSON object on stdout.

  updates.py status     system packages (apt), Flatpak apps, firmware (fwupd), restart needed,
                        the last automatic update
  updates.py flatpak    flatpak only (slow: asks the remotes)
  updates.py setup      the argv that installs the root helper and its polkit files (run with pkexec)

System packages come from a dry run of the same upgrade the root helper performs
(distro/system/usr/libexec/ultimit/updates-helper), so the list is exactly what "Install" will
install. Upgrades apt holds back (phased rollout, kept back) are reported separately: they are
not installable yet and are not counted as pending.

Test hooks (normal user only): UPDATES_FAKE_DIR=<dir> reads apt-sim.txt, flatpak.txt, fwupd.json,
reboot-required(.pkgs) and unattended.log from there instead of running anything.
"""
import json
import os
import re
import shlex
import subprocess
import sys
import time

FAKE = os.environ.get("UPDATES_FAKE_DIR") if os.getuid() != 0 else None

APT_SIM = ["apt-get", "-s", "-o", "Debug::NoLocking=1", "--with-new-pkgs", "upgrade"]
FLATPAK = ["flatpak", "remote-ls", "--updates", "--columns=application,name,branch,version"]
FWUPD = ["fwupdmgr", "get-updates", "--json", "--no-unreported-check", "--no-metadata-check"]
REBOOT = "/var/run/reboot-required"
UU_LOG = "/var/log/unattended-upgrades/unattended-upgrades.log"
APT_STAMP = "/var/lib/apt/periodic/update-success-stamp"
HELPER = "/usr/libexec/ultimit/updates-helper"
SYSTEM = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../distro/system"))
SYSTEM_FILES = [(HELPER, "755"),
                ("/usr/share/polkit-1/actions/org.ultimit.updates.policy", "644"),
                ("/usr/share/polkit-1/rules.d/50-ultimit-updates.rules", "644")]

# Inst NAME[:ARCH] [OLD] (NEW ORIGIN [ARCH]) ...   (OLD missing for a new package)
INST_RE = re.compile(r"^Inst (\S+?)(?::(\S+))? (?:\[([^\]]*)\] )?\((\S+) (\S+) \[([^\]]+)\]\)")


def run(argv, timeout=60):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                           stdin=subprocess.DEVNULL, env=dict(os.environ, LC_ALL="C"))
        return p.returncode, p.stdout, p.stderr
    except FileNotFoundError:
        return 127, "", argv[0] + ": not installed"
    except subprocess.TimeoutExpired:
        return 124, "", argv[0] + ": timed out"


def fake(name):
    try:
        with open(os.path.join(FAKE, name)) as f:
            return f.read()
    except OSError:
        return None


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return None


def parse_apt_sim(text):
    """-> (packages, held). Packages are merged across architectures."""
    pkgs, order, held = {}, [], []
    section = None
    for line in text.splitlines():
        m = INST_RE.match(line)
        if m:
            name, _, old, new, origin, arch = m.groups()
            p = pkgs.get(name)
            if not p:
                suite = origin.split("/")[-1]
                p = pkgs[name] = {"name": name, "from": old or "", "to": new, "origin": suite,
                                  "security": suite.endswith("-security"), "new": not old, "archs": []}
                order.append(name)
            if arch not in p["archs"]:
                p["archs"].append(arch)
            continue
        if line.startswith("The following upgrades have been deferred due to phasing") or \
                line.startswith("The following packages have been kept back"):
            section = "held"
            continue
        if line.startswith("  ") and section == "held":
            held += line.split()
            continue
        section = None
    held = sorted(set(h.split(":")[0] for h in held) - set(order))
    return [pkgs[n] for n in order], held


def parse_flatpak(text):
    out = []
    for line in text.splitlines():
        f = line.split("\t")
        if len(f) >= 1 and f[0] and "." in f[0]:
            out.append({"id": f[0], "name": f[1] if len(f) > 1 and f[1] else f[0],
                        "branch": f[2] if len(f) > 2 else "", "version": f[3] if len(f) > 3 else ""})
    return out


def parse_fwupd(text):
    """Newest release per device. fwupdmgr prints nothing useful (exit 2) when there is nothing."""
    try:
        d = json.loads(text)
    except ValueError:
        return []
    out = []
    for dev in d.get("Devices", []):
        rels = dev.get("Releases") or []
        if not rels:
            continue
        r = rels[0]  # fwupd lists the newest first
        out.append({"device": dev.get("Name", "?"), "vendor": dev.get("Vendor", ""),
                    "id": dev.get("DeviceId", ""), "from": dev.get("Version", ""),
                    "to": r.get("Version", ""), "summary": r.get("Summary", ""),
                    "reboot": "needs-reboot" in (dev.get("Flags") or [])})
    return out


def parse_uu_log(text):
    """Last unattended-upgrades run: when it started and what it said at the end."""
    if not text:
        return None
    runs = [i for i, l in enumerate(text.splitlines()) if "Starting unattended upgrades script" in l]
    if not runs:
        return None
    lines = text.splitlines()[runs[-1]:]
    when = lines[0][:19]
    said = ""
    for l in lines[1:]:
        m = re.match(r"^\S+ \S+ INFO (.*)$", l)
        if not m:
            continue
        t = m.group(1)
        if t.startswith(("Packages that will be upgraded", "All upgrades installed",
                         "No packages found", "Installing the upgrades failed")):
            said = t
    return {"time": when, "text": said}


def status():
    o = {"apt": [], "held": [], "aptError": "", "firmware": [], "fwupdError": "",
         "reboot": False, "rebootPkgs": [], "auto": None, "checkedAt": 0}

    sim = fake("apt-sim.txt") if FAKE else None
    if sim is None and not FAKE:
        rc, sim, err = run(APT_SIM, timeout=120)
        if rc != 0:
            o["aptError"] = (err or sim).strip().splitlines()[-1:] or ["apt-get failed"]
            o["aptError"] = o["aptError"][0]
            sim = ""
    o["apt"], o["held"] = parse_apt_sim(sim or "")

    fw = fake("fwupd.json") if FAKE else None
    if fw is None and not FAKE:
        rc, fw, err = run(FWUPD, timeout=60)
        if rc == 127:
            o["fwupdError"] = "fwupd is not installed"
    o["firmware"] = parse_fwupd(fw or "")

    rr = fake("reboot-required") if FAKE else read(REBOOT)
    o["reboot"] = rr is not None
    pk = fake("reboot-required.pkgs") if FAKE else read(REBOOT + ".pkgs")
    o["rebootPkgs"] = sorted(set((pk or "").split()))

    o["auto"] = parse_uu_log(fake("unattended.log") if FAKE else read(UU_LOG))
    try:
        o["checkedAt"] = int(os.stat(os.path.join(FAKE, "apt-sim.txt") if FAKE else APT_STAMP).st_mtime)
    except OSError:
        pass
    o["now"] = int(time.time())
    o["helper"] = os.access(HELPER, os.X_OK)
    return o


def setup():
    install = " && ".join("install -D -m %s %s %s" % (mode, shlex.quote(os.path.join(SYSTEM, p.lstrip("/"))), p)
                          for p, mode in SYSTEM_FILES)
    argv = ["/bin/sh", "-ec", install]
    return {"argv": argv, "display": "pkexec " + " ".join(shlex.quote(a) for a in argv)}


def flatpak():
    text = fake("flatpak.txt") if FAKE else None
    err = ""
    if text is None and not FAKE:
        rc, text, e = run(FLATPAK, timeout=90)
        if rc != 0:
            err = "flatpak is not installed" if rc == 127 else ((e or "").strip().splitlines() or ["flatpak failed"])[-1]
            text = ""
    return {"flatpak": parse_flatpak(text or ""), "flatpakError": err}


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "status"
    if cmd == "status":
        print(json.dumps(status()))
    elif cmd == "flatpak":
        print(json.dumps(flatpak()))
    elif cmd == "setup":
        print(json.dumps(setup()))
    else:
        print(json.dumps({"error": "usage: updates.py status|flatpak|setup"}))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
