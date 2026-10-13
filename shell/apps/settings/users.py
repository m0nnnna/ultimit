#!/usr/bin/python3 -I
"""users.py - what Settings > Users needs without root. One JSON object on stdout.

  users.py list        people accounts (UID 1000-59999 with a login shell): user, name, admin, you
  users.py mypassword  change your own password with passwd; current and new password on stdin
                       (two lines). Works for standard accounts too; passwd checks the current one.
  users.py setup       the argv that installs the root helper and its polkit policy (run with pkexec)

Changes to other accounts go through /usr/libexec/ultimit/users-helper via pkexec (UsersPage.qml).
Test hooks (normal user only): USERS_PASSWD=<program used instead of passwd>.
"""
import grp
import json
import os
import pty
import pwd
import select
import shlex
import sys
import time

_dev = os.getuid() != 0
PASSWD = (_dev and os.environ.get("USERS_PASSWD")) or "/usr/bin/passwd"
HELPER = "/usr/libexec/ultimit/users-helper"
SYSTEM = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../distro/system"))
SYSTEM_FILES = [(HELPER, "755"), ("/usr/share/polkit-1/actions/org.ultimit.users.policy", "644")]
ADMIN_GROUPS = ("sudo", "admin")


def out(o, rc=0):
    sys.stdout.write(json.dumps(o))
    sys.stdout.flush()
    return rc


def list_users():
    admin = set()
    for g in ADMIN_GROUPS:
        try:
            gr = grp.getgrnam(g)
            admin |= set(gr.gr_mem) | {p.pw_name for p in pwd.getpwall() if p.pw_gid == gr.gr_gid}
        except KeyError:
            pass
    me = pwd.getpwuid(os.getuid()).pw_name
    users = []
    for p in pwd.getpwall():
        if not 1000 <= p.pw_uid <= 59999 or p.pw_shell.endswith(("nologin", "false")):
            continue
        users.append({"user": p.pw_name, "name": p.pw_gecos.split(",")[0] or p.pw_name, "uid": p.pw_uid,
                      "home": p.pw_dir, "admin": p.pw_name in admin, "you": p.pw_name == me})
    users.sort(key=lambda u: (not u["you"], u["name"].lower()))
    return {"ok": True, "users": users, "helper": os.access(HELPER, os.X_OK),
            "admins": sum(1 for u in users if u["admin"])}


def my_password():
    """Drive passwd on a pseudo-terminal: it asks for the current password, then the new one twice."""
    lines = sys.stdin.read().split("\n")
    if len(lines) < 2 or not lines[0] or not lines[1]:
        return out({"ok": False, "error": "Give the current and the new password."}, 1)
    current, new = lines[0], lines[1]
    pid, fd = pty.fork()
    if pid == 0:
        os.environ["LC_ALL"] = "C"
        os.execv(PASSWD, [PASSWD])
    said, answers = b"", [current, new, new]
    deadline = time.time() + 30
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.5)
        if not r:
            continue
        try:
            chunk = os.read(fd, 1024)
        except OSError:
            break
        if not chunk:
            break
        said += chunk
        if said.rstrip().endswith(b":") and answers:   # a password prompt
            os.write(fd, (answers.pop(0) + "\n").encode())
            said += b"\n"
    _, status = os.waitpid(pid, 0)
    text = said.decode("utf-8", "replace")
    if os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0:
        return out({"ok": True})
    # passwd's last complaint ("Authentication token manipulation error", "BAD PASSWORD: ...")
    msg = [l.strip() for l in text.splitlines() if l.strip() and not l.strip().endswith(":")]
    err = msg[-1] if msg else "passwd failed"
    if "manipulation" in text or "Authentication failure" in text:
        err = "The current password isn't right."
    return out({"ok": False, "error": err}, 1)


def setup():
    install = " && ".join("install -D -m %s %s %s" % (mode, shlex.quote(os.path.join(SYSTEM, p.lstrip("/"))), p)
                          for p, mode in SYSTEM_FILES)
    argv = ["/bin/sh", "-ec", install]
    return {"argv": argv, "display": "pkexec " + " ".join(shlex.quote(a) for a in argv)}


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "list"
    if cmd == "list":
        return out(list_users())
    if cmd == "mypassword":
        return my_password()
    if cmd == "setup":
        return out(setup())
    return out({"ok": False, "error": "usage: users.py list|mypassword|setup"}, 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
