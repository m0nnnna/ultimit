#!/usr/bin/python3 -I
"""updates.py - what Settings > Updates shows. Unprivileged; one JSON object on stdout.

  updates.py status     system packages (apt), Flatpak apps, firmware (fwupd), restart needed,
                        the last automatic update
  updates.py flatpak    flatpak only (slow: asks the remotes)
  updates.py ultimit    Ultimit itself: the installed version and the latest GitHub release
                        (distro/update-source names the repository)
  updates.py setup      the argv that installs the root helper and its polkit files (run with pkexec)

System packages come from a dry run of the same upgrade the root helper performs
(distro/system/usr/libexec/ultimit/updates-helper), so the list is exactly what "Install" will
install. Upgrades apt holds back (phased rollout, kept back) are reported separately: they are
not installable yet and are not counted as pending.

Test hooks (normal user only): UPDATES_FAKE_DIR=<dir> reads apt-sim.txt, flatpak.txt, fwupd.json,
reboot-required(.pkgs), unattended.log, github.json (the releases/latest answer) and
VERSION from there instead of running anything.
"""
import json
import os
import re
import shlex
import subprocess
import sys
import time
import urllib.error
import urllib.request

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

PREFIX = "/opt/ultimit"
SOURCE_FILES = [os.path.join(PREFIX, "distro/update-source"), os.path.join(os.path.dirname(SYSTEM), "update-source")]
UPDATE_RUNNING = "/run/ultimit-update.running"
GITHUB_API = "https://api.github.com/repos/%s/releases/latest"
# v0.2.0, 0.2.0, v0.2.0-3-gabc1234 (git describe: 3 commits after v0.2.0), any of them -dirty
VERSION_RE = re.compile(r"^v?(\d+(?:\.\d+)*)(?:-(\d+)-g[0-9a-f]+)?(?:-dirty)?$")

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


def parse_version(v):
    """-> a comparable tuple, or None for something that isn't a release version (a bare commit)."""
    m = VERSION_RE.match((v or "").strip())
    if not m:
        return None
    nums = [int(x) for x in m.group(1).split(".")]
    nums += [0] * (4 - len(nums))
    return tuple(nums[:4]) + (int(m.group(2) or 0),)


def is_newer(latest, installed):
    """A release is newer than an install that isn't a release (built from some commit)."""
    lv, iv = parse_version(latest), parse_version(installed)
    if lv is None:
        return False
    return iv is None or lv > iv


def update_source():
    for f in SOURCE_FILES:
        text = read(f)
        if text is None:
            continue
        if text:
            for line in text.splitlines():
                line = line.split("#")[0].strip()
                if re.match(r"^[\w.-]+/[\w.-]+$", line):
                    return line
        return ""
    return "m0nnnna/ultimit"   # installs older than distro/update-source


def parse_release(d, repo):
    tag = d.get("tag_name") or ""
    ver = tag[1:] if tag.startswith("v") else tag
    want = "ultimit-%s-amd64.tar.gz" % ver
    asset = next((a for a in d.get("assets") or [] if a.get("name") == want), None)
    return {"tag": tag, "version": ver, "name": d.get("name") or tag, "notes": (d.get("body") or "").strip(),
            "published": (d.get("published_at") or "")[:10], "url": d.get("html_url") or "https://github.com/%s/releases" % repo,
            "size": asset.get("size", 0) if asset else 0, "asset": bool(asset)}


def ultimit():
    o = {"installed": "", "running": os.environ.get("ULTIMIT_VERSION", ""), "repo": update_source(),
         "latest": None, "newer": False, "error": ""}
    o["installed"] = ((fake("VERSION") if FAKE else read(os.path.join(PREFIX, "VERSION"))) or "").strip()
    pid = ((fake("update-running") if FAKE else read(UPDATE_RUNNING)) or "").strip()
    o["updating"] = pid.isdigit() and (FAKE is not None or os.path.exists("/proc/" + pid))
    if not o["repo"]:
        o["error"] = "No update source (distro/update-source)."
        return o
    text = fake("github.json") if FAKE else None
    if text is None and not FAKE:
        req = urllib.request.Request(GITHUB_API % o["repo"], headers={
            "Accept": "application/vnd.github+json", "User-Agent": "ultimit-updates"})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                text = r.read().decode()
        except urllib.error.HTTPError as e:
            o["error"] = ("No Ultimit releases published yet." if e.code == 404
                          else "GitHub is limiting requests; try again later." if e.code in (403, 429)
                          else "GitHub answered %d." % e.code)
            return o
        except (urllib.error.URLError, OSError) as e:
            o["error"] = "Could not reach GitHub (%s)." % getattr(e, "reason", e)
            return o
    try:
        rel = parse_release(json.loads(text or ""), o["repo"])
    except (ValueError, AttributeError):
        o["error"] = "GitHub's answer didn't make sense."
        return o
    o["latest"] = rel
    o["newer"] = rel["asset"] and is_newer(rel["tag"], o["installed"])
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
    elif cmd == "ultimit":
        print(json.dumps(ultimit()))
    elif cmd == "setup":
        print(json.dumps(setup()))
    else:
        print(json.dumps({"error": "usage: updates.py status|flatpak|ultimit|setup"}))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
