#!/usr/bin/env python3
"""nekoshot.py - backend of BACKUP, the Ultimit GUI for NekoShot full-system backups (stdlib only, JSON on stdout).

Anything that needs root goes through /usr/libexec/ultimit/nekoshot-helper via pkexec (polkit action
org.ultimit.nekoshot). Reading the state needs no password.

  nekoshot.py state                       settings, snapshots, running/last backup, schedule, warnings
  nekoshot.py backup                      start a backup in the background (asks for authorization)
  nekoshot.py verify PATH                 check a snapshot against its .sha256
  nekoshot.py prune                       keep only the newest N snapshots
  nekoshot.py schedule-add NAME CRON | schedule-remove NAME
  nekoshot.py set KEY VALUE               output_dir | profile | encrypt | keep | compression
  nekoshot.py passphrase [--generate]     create/show where the encryption passphrase lives
  nekoshot.py recovery                    the commands that restore a snapshot from a rescue USB

A dismissed password prompt is {ok:false, cancelled:true}. Every external program goes through
`runner` (tests replace it). NEKOSHOT_CLI / NEKOSHOT_HELPER override paths for tests run as a user.
"""
import json
import os
import re
import secrets
import shlex
import subprocess
import sys

HOME = os.path.expanduser("~")
CONFIG_DIR = os.path.join(HOME, ".config", "ultimit")
SETTINGS = os.path.join(CONFIG_DIR, "nekoshot.json")
PASSFILE = os.path.join(CONFIG_DIR, "nekoshot.passphrase")
CLI = os.environ.get("NEKOSHOT_CLI") or "/opt/ultimit/nekoshot/nekoshot.py"
HELPER = os.environ.get("NEKOSHOT_HELPER") or "/usr/libexec/ultimit/nekoshot-helper"
DEFAULTS = {"output_dir": "/var/backups/nekoshot", "profile": "desktop", "encrypt": False,
            "keep": 3, "compression": "zstd"}
JOB_NAME = "ultimit-backup"
PKEXEC_CANCEL = (126, 127)  # dismissed / not authorized


def runner(argv, timeout=60):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, "", str(e)


def out(o):
    sys.stdout.write(json.dumps(o))
    sys.stdout.flush()
    return 0


def load_settings():
    s = dict(DEFAULTS)
    try:
        with open(SETTINGS) as f:
            s.update({k: v for k, v in json.load(f).items() if k in DEFAULTS})
    except (OSError, ValueError):
        pass
    return s


def save_settings(s):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    tmp = SETTINGS + ".tmp"
    with open(tmp, "w") as f:
        json.dump(s, f, indent=2)
    os.replace(tmp, SETTINGS)


def validate(key, value):
    """Return (ok, normalized value or error text)."""
    if key == "output_dir":
        # Only what would actually break: a relative path or a parent traversal. Everything is
        # passed as argv (no shell) and scheduled commands are quoted, so spaces are fine:
        # USB drives mount at "/media/you/My Passport" all the time.
        if not value.startswith("/") or ".." in value.split("/"):
            return False, "Pick an absolute folder path."
        return True, value.rstrip("/") or "/"
    if key == "profile":
        return (value in ("desktop", "server"), value) if value in ("desktop", "server") else (False, "Unknown profile.")
    if key == "compression":
        return (True, value) if value in ("zstd", "gzip", "none") else (False, "Unknown compression.")
    if key == "encrypt":
        return True, value in ("1", "true", "on", "yes")
    if key == "keep":
        try:
            n = int(value)
        except ValueError:
            return False, "Keep must be a number."
        return (True, n) if 1 <= n <= 99 else (False, "Keep between 1 and 99 backups.")
    return False, "Unknown setting."


def capture_args(s):
    a = ["capture", "--output", s["output_dir"], "--profile", s["profile"], "--compression", s["compression"]]
    if s["encrypt"]:
        a += ["--encrypt", "--passphrase-file", PASSFILE]
    return a


def privileged(args, timeout=3600):
    """Run the root helper through pkexec. Returns parsed JSON (or an error object)."""
    cmd = [HELPER] + args if os.environ.get("NEKOSHOT_NO_PKEXEC") else ["pkexec", HELPER] + args
    rc, so, se = runner(cmd, timeout)
    if rc in PKEXEC_CANCEL and not so.strip():
        return {"ok": False, "cancelled": True}
    try:
        o = json.loads(so)
    except ValueError:
        return {"ok": False, "error": (se.strip().splitlines() or ["The backup helper failed."])[-1]}
    if isinstance(o, dict):
        o.setdefault("ok", rc == 0)
        return o
    return {"ok": rc == 0, "data": o}


def cli_json(args):
    rc, so, se = runner(["python3", "-I", CLI, "--json"] + args, 120)
    try:
        return json.loads(so)
    except ValueError:
        return None


def same_disk_as_root(path):
    p = path
    while p and not os.path.exists(p):
        p = os.path.dirname(p)
    try:
        return os.stat(p or "/").st_dev == os.stat("/").st_dev
    except OSError:
        return True


def scheduled_drift(command, s):
    """Ways the scheduled command (baked in when the schedule was created) differs from the
    current settings: ["backup folder /old", "encryption off"]. Empty when they agree."""
    try:
        args = shlex.split(command or "")
    except ValueError:
        args = (command or "").split()
    out_dir, encrypt = "", False
    for i, a in enumerate(args):
        if a == "--output" and i + 1 < len(args):
            out_dir = args[i + 1]
        elif a.startswith("--output="):
            out_dir = a.split("=", 1)[1]
        elif a == "--encrypt":
            encrypt = True
    diffs = []
    if out_dir and out_dir.rstrip("/") != s["output_dir"]:
        diffs.append("backup folder " + out_dir)
    if encrypt != bool(s["encrypt"]):
        diffs.append("encryption on" if encrypt else "encryption off")
    return diffs


def cmd_state():
    s = load_settings()
    installed = os.path.isfile(CLI)
    helper = os.path.isfile(HELPER)
    st = {"ok": True, "settings": s, "cli": installed, "helper": helper, "snapshots": [],
          "running": None, "last": None, "schedule": [], "warnings": [],
          "passphrase": os.path.isfile(PASSFILE)}
    if not installed:
        return out(st)
    snaps = cli_json(["list", "--path", s["output_dir"]]) if os.path.isdir(s["output_dir"]) else []
    st["snapshots"] = snaps if isinstance(snaps, list) else []
    status = cli_json(["status"])
    if isinstance(status, list) and status:
        rec = status[0]
        if rec.get("state") == "running":
            st["running"] = rec
        else:
            st["last"] = rec
    sched = cli_json(["schedule", "list"])
    if isinstance(sched, dict):
        st["schedule"] = [j for j in sched.get("jobs", []) if j.get("name") == JOB_NAME]
        if sched.get("cron_running") is False:
            st["warnings"].append("The backup scheduler isn't running, so scheduled backups won't fire.")
        for j in st["schedule"]:
            drift = scheduled_drift(j.get("command", ""), s)
            if drift:
                st["warnings"].append("The schedule was set with " + " and ".join(drift)
                                      + "; remove it and add it again to use the current settings.")
    if same_disk_as_root(s["output_dir"]):
        st["warnings"].append("Backups are stored on the same disk as the system. Keep a copy on an external drive, or a failed disk takes both.")
    if s["encrypt"] and not st["passphrase"]:
        st["warnings"].append("Encryption is on but no passphrase exists yet.")
    if not helper:
        st["warnings"].append("The backup helper is not installed.")
    return out(st)


def cmd_backup():
    s = load_settings()
    if s["encrypt"] and not os.path.isfile(PASSFILE):
        return out({"ok": False, "error": "Create the encryption passphrase first (Settings)."})
    return out(privileged(capture_args(s), 120))


def cmd_verify(path):
    snaps = (cli_json(["list", "--path", load_settings()["output_dir"]]) or [])
    if path not in [x.get("path") for x in snaps]:
        return out({"ok": False, "error": "That is not one of your backups."})
    o = cli_json(["verify", "--image", path]) or {"verified": False, "error": "Could not read the checksum."}
    return out({"ok": o.get("verified") is True, "verified": o.get("verified") is True, "error": o.get("error", "")})


def cmd_prune():
    s = load_settings()
    return out(privileged(["prune", "--path", s["output_dir"], "--keep", str(s["keep"])], 300))


def cmd_schedule_add(name, cron):
    if name != JOB_NAME:
        return out({"ok": False, "error": "Unsupported job name."})
    if len(cron.split()) != 5 or not re.match(r"^[0-9*/,\- ]+$", cron):
        return out({"ok": False, "error": "That is not a valid schedule."})
    return out(privileged(["schedule", "add", name, cron, "--"] + capture_args(load_settings()), 60))


def cmd_schedule_remove(name):
    return out(privileged(["schedule", "remove", name], 60))


def cmd_set(key, value):
    ok, v = validate(key, value)
    if not ok:
        return out({"ok": False, "error": v})
    s = load_settings()
    s[key] = v
    save_settings(s)
    return out({"ok": True})


def _read(path):
    with open(path) as f:
        return f.read().strip()


def cmd_passphrase(generate):
    if generate and not os.path.isfile(PASSFILE):
        os.makedirs(CONFIG_DIR, exist_ok=True)
        fd = os.open(PASSFILE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(secrets.token_urlsafe(24) + "\n")
    exists = os.path.isfile(PASSFILE)
    return out({"ok": True, "exists": exists, "path": PASSFILE,
                "passphrase": _read(PASSFILE) if exists else ""})


def cmd_recovery():
    s = load_settings()
    snap = "<backup file>"
    enc = " --passphrase-file /path/to/nekoshot.passphrase" if s["encrypt"] else ""
    steps = [
        "Boot a rescue USB that has NekoShot, rsync, zstd and gpg.",
        "Partition and format the disk (the partition table is saved inside each backup: sfdisk-*.dump).",
        "Mount the new system at /mnt/restore (and its EFI partition at /mnt/restore/boot/efi).",
        "Restore: python3 nekoshot.py restore --image %s --target /mnt/restore --fix-bootloader /dev/DISK --update-fstab --update-initramfs%s" % (snap, enc),
        "Reboot into the restored system.",
    ]
    return out({"ok": True, "steps": steps, "passphrase_file": PASSFILE if s["encrypt"] else ""})


def main(argv):
    if not argv:
        return out({"ok": False, "error": "no command"})
    c, a = argv[0], argv[1:]
    try:
        if c == "state": return cmd_state()
        if c == "backup": return cmd_backup()
        if c == "verify" and len(a) == 1: return cmd_verify(a[0])
        if c == "prune": return cmd_prune()
        if c == "schedule-add" and len(a) == 2: return cmd_schedule_add(*a)
        if c == "schedule-remove" and len(a) == 1: return cmd_schedule_remove(a[0])
        if c == "set" and len(a) == 2: return cmd_set(*a)
        if c == "passphrase": return cmd_passphrase("--generate" in a)
        if c == "recovery": return cmd_recovery()
    except Exception as e:  # the UI shows one calm message, never a traceback
        return out({"ok": False, "error": "Unexpected error: %s" % e})
    return out({"ok": False, "error": "unknown command"})


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
