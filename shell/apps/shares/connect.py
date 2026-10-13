#!/usr/bin/env python3
"""connect.py - the "connect to other computers' shares" half of SHARES (JSON on stdout, no admin rights).

Uses gvfs through Python Gio (smb://, and sftp/ftp/dav for free). Mounts live in the user's session; saved
passwords are stored by gvfs in the secret service when "remember" is on, never by this program.

  connect.py caps                              what works here: gio, smb backend, FUSE paths, avahi, keyring state
  connect.py normalize TEXT                    \\\\host\\share, //host/share, smb://host/share, host/share, host -> smb:// URI
  connect.py discover                          SMB servers on the LAN (avahi, ~3 s)
  connect.py browse HOST [--user U --domain D] [--password-stdin]      shares on a server
  connect.py connect URI [--user U --domain D] [--password-stdin] [--remember] [--no-prompt]
  connect.py mounts                            connected network locations
  connect.py disconnect URI|PATH
  connect.py saved                             saved connections
  connect.py save URI [--name N --user U --domain D --remember --reconnect]
  connect.py unsave URI
  connect.py set-reconnect URI on|off
  connect.py reconnect                         connect every saved entry marked "reconnect at login" (never prompts)

The password, when given, is ONE line on stdin (--password-stdin); it is never put on a command line, in
a file, or in the output. Every result is {ok, ...}; failures carry `code`: needs_password | denied |
not_found | timeout | unsupported | bad_address | failed, plus a human `error`.
Real Gio calls sit behind RealBackend; SHARES_FAKE=1 swaps in FakeBackend (state: fixtures/connect-fake.json
copied into SHARES_FAKE_STATE by make-state.sh), so tests and the UI work without any network.
"""
import json
import os
import re
import signal
import socket
import sys
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import shares as S  # noqa: E402  (fake(), fake_state(), run(), runner - same fake/runner pattern)

GENERIC_SCHEMES = ("sftp", "ftp", "ftps", "dav", "davs", "nfs")
NET_SCHEMES = ("smb",) + GENERIC_SCHEMES
HOST_RE = re.compile(r"^(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9_]([A-Za-z0-9_.\-]*[A-Za-z0-9_])?)(:\d{1,5})?$")


def out(o):
    sys.stdout.write(json.dumps(o))
    sys.stdout.flush()


def fail(code, error, **kw):
    r = {"ok": False, "code": code, "error": error}
    r.update(kw)
    return r


# ---------------------------------------------------------------- addresses

def normalize(text):
    """Any common way of typing a share address -> {ok, uri, scheme, host, share, path, user, domain, kind}.
    kind is "server" (no share: browse it), "share" or "other" (sftp/ftp/dav...)."""
    t = (text or "").strip().strip('"').strip("'")
    if not t:
        return fail("bad_address", "Type the address of a computer or share, like \\\\computer\\share.")
    scheme, user, domain = "smb", "", ""
    m = re.match(r"^([A-Za-z][A-Za-z0-9+.\-]*)://(.*)$", t)
    if m:
        scheme, rest = m.group(1).lower(), m.group(2)
        if scheme not in NET_SCHEMES:
            return fail("bad_address", "Only smb://, sftp://, ftp://, dav:// and nfs:// addresses are supported.")
    else:
        rest = t.replace("\\", "/")
        rest = re.sub(r"^/+", "", rest)
    rest = urllib.parse.unquote(rest) if m else rest
    netloc, _, path = rest.partition("/")
    if "@" in netloc:
        cred, _, netloc = netloc.rpartition("@")
        user = cred
        if ";" in cred:
            domain, _, user = cred.partition(";")
        elif "\\" in cred:
            domain, _, user = cred.partition("\\")
    if not netloc or not HOST_RE.match(netloc):
        return fail("bad_address", "That does not look like a computer name or address.")
    path = "/".join(p for p in path.split("/") if p)
    host = netloc
    if scheme == "smb":
        parts = path.split("/") if path else []
        share = parts[0] if parts else ""
        uri = "smb://" + host + "/" + (urllib.parse.quote("/".join(parts)) if parts else "")
        kind = "share" if share else "server"
    else:
        share = ""
        uri = "%s://%s/%s" % (scheme, host, urllib.parse.quote(path))
        kind = "other"
    return {"ok": True, "uri": uri, "scheme": scheme, "host": host, "share": share, "path": path,
            "user": user, "domain": domain, "kind": kind}


def uri_key(uri):
    """Comparable form of a URI (case-insensitive host, no trailing slash)."""
    p = urllib.parse.urlsplit(uri)
    return "%s://%s%s" % (p.scheme.lower(), p.netloc.rpartition("@")[2].lower(), p.path.rstrip("/"))


def uri_label(uri):
    """smb://host/share/dir -> "share on host"."""
    p = urllib.parse.urlsplit(uri)
    host = p.netloc.rpartition("@")[2]
    path = urllib.parse.unquote(p.path).strip("/")
    return ("%s on %s" % (path.split("/")[-1], host)) if path else host


# ---------------------------------------------------------------- discovery

def parse_avahi(text, own_host=""):
    """Parse `avahi-browse -ptr _smb._tcp` -> [{name, host, address, source}], IPv4 preferred, one per machine."""
    found = {}
    for line in text.splitlines():
        f = line.split(";")
        if len(f) < 9 or f[0] != "=":
            continue
        proto, name, hostname, addr = f[2], f[3], f[6], f[7]
        name = re.sub(r"\\(\d{3})", lambda m: chr(int(m.group(1))), name)      # avahi escapes as \032 etc.
        key = hostname.lower() or name.lower()
        entry = {"name": name, "host": hostname, "address": addr, "source": "avahi", "ipv6": proto == "IPv6"}
        old = found.get(key)
        if old is None or (old["ipv6"] and not entry["ipv6"]):
            found[key] = entry
    res = []
    for e in found.values():
        e.pop("ipv6")
        e["self"] = bool(own_host) and e["host"].split(".")[0].lower() == own_host.split(".")[0].lower()
        res.append(e)
    return sorted(res, key=lambda e: e["name"].lower())


def resolvable(name):
    try:
        socket.getaddrinfo(name, 445, socket.AF_INET)
        return True
    except OSError:
        return False


def discover(resolve=resolvable):
    rc, o, e = S.run(["avahi-browse", "-ptr", "_smb._tcp"], None, 8)
    if rc == 127:
        return {"ok": True, "servers": [], "err": "avahi-browse is not installed"}
    if rc not in (0, 124):
        return {"ok": True, "servers": [], "err": (e or "avahi-browse failed").strip()}
    rc2, own, _ = S.run(["hostname"])
    servers = parse_avahi(o, own.strip() if rc2 == 0 else "")
    for s in servers:      # a name that resolves survives address changes; otherwise use the IP
        s["host"] = s["host"] if s["host"] and resolve(s["host"]) else (s["address"] or s["host"])
    return {"ok": True, "servers": servers}


# ---------------------------------------------------------------- saved connections

def config_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(S.home(), ".config")
    return os.path.join(base, "ultimit", "shares")


def saved_path():
    return os.path.join(config_dir(), "connections.json")


def load_saved():
    try:
        with open(saved_path()) as f:
            d = json.load(f)
    except (OSError, ValueError):
        return []
    res = []
    for c in d if isinstance(d, list) else []:
        if isinstance(c, dict) and isinstance(c.get("uri"), str):
            res.append({"name": str(c.get("name") or uri_label(c["uri"])), "uri": c["uri"], "user": str(c.get("user") or ""),
                        "domain": str(c.get("domain") or ""), "remember": bool(c.get("remember")),
                        "reconnectAtLogin": bool(c.get("reconnectAtLogin"))})
    return res


def store_saved(items):
    os.makedirs(config_dir(), exist_ok=True)
    tmp = saved_path() + ".tmp"
    with open(tmp, "w") as f:
        json.dump(items, f, indent=2)
        f.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, saved_path())          # never a password in here: gvfs keeps those in the keyring


def save_connection(uri, name="", user="", domain="", remember=False, reconnect=False):
    n = normalize(uri)
    if not n["ok"]:
        return n
    items = load_saved()
    entry = {"name": name or uri_label(n["uri"]), "uri": n["uri"], "user": user or n["user"], "domain": domain or n["domain"],
             "remember": bool(remember), "reconnectAtLogin": bool(reconnect)}
    for i, c in enumerate(items):
        if uri_key(c["uri"]) == uri_key(n["uri"]):
            entry["reconnectAtLogin"] = bool(reconnect) or c["reconnectAtLogin"]
            entry["name"] = name or c["name"]
            items[i] = entry
            break
    else:
        items.append(entry)
    store_saved(items)
    return {"ok": True, "saved": items}


def unsave_connection(uri):
    key = uri_key(normalize(uri).get("uri", uri))
    items = [c for c in load_saved() if uri_key(c["uri"]) != key]
    store_saved(items)
    return {"ok": True, "saved": items}


def set_reconnect(uri, on):
    key = uri_key(normalize(uri).get("uri", uri))
    items = load_saved()
    hit = False
    for c in items:
        if uri_key(c["uri"]) == key:
            c["reconnectAtLogin"] = bool(on)
            hit = True
    if not hit:
        return fail("failed", "That connection is not saved.")
    store_saved(items)
    return {"ok": True, "saved": items}


# ---------------------------------------------------------------- error mapping

def map_error(kind):
    """Gio error kind name -> (code, human text). Kinds: PERMISSION_DENIED, HOST_NOT_FOUND, NOT_FOUND, TIMED_OUT, ..."""
    return {
        "PERMISSION_DENIED": ("denied", "Access denied: the user name or password was not accepted."),
        "HOST_NOT_FOUND": ("not_found", "That computer could not be found on the network."),
        "NOT_FOUND": ("not_found", "That computer or share could not be found."),
        "TIMED_OUT": ("timeout", "The computer did not answer in time."),
        "HOST_UNREACHABLE": ("not_found", "That computer cannot be reached."),
        "NETWORK_UNREACHABLE": ("not_found", "The network cannot be reached."),
        "CONNECTION_REFUSED": ("not_found", "That computer refused the connection (is file sharing on?)."),
        "NOT_SUPPORTED": ("unsupported", "This kind of address is not supported (is gvfs-backends installed?)."),
        "FAILED_HANDLED": ("needs_password", "A password is needed."),
    }.get(kind, ("failed", ""))


# ---------------------------------------------------------------- real backend (Gio / gvfs)

class RealBackend:
    def __init__(self):
        import gi
        gi.require_version("Gio", "2.0")
        from gi.repository import Gio, GLib
        self.Gio, self.GLib = Gio, GLib

    # -- helpers
    def _kind(self, err):
        Gio = self.Gio
        for name in ("PERMISSION_DENIED", "HOST_NOT_FOUND", "NOT_FOUND", "TIMED_OUT", "HOST_UNREACHABLE", "NETWORK_UNREACHABLE",
                     "CONNECTION_REFUSED", "NOT_SUPPORTED", "FAILED_HANDLED", "ALREADY_MOUNTED"):
            code = getattr(Gio.IOErrorEnum, name, None)
            if code is not None and err.matches(Gio.io_error_quark(), code):
                return name
        return ""

    def _op(self, creds, remember, state, allow_anon=True, prompt=True):
        Gio = self.Gio
        op = Gio.MountOperation()
        pw = creds.get("password") if creds else None

        def ask(o, message, def_user, def_domain, flags):
            state["asked"] += 1
            if pw is not None and state["asked"] == 1:
                o.set_username(creds.get("user") or def_user or "")
                o.set_domain(creds.get("domain") or def_domain or "WORKGROUP")
                o.set_password(pw)
                o.set_password_save(Gio.PasswordSave.PERMANENTLY if remember else Gio.PasswordSave.NEVER)
                o.reply(Gio.MountOperationResult.HANDLED)
            elif pw is None and allow_anon and state["asked"] == 1 and flags & Gio.AskPasswordFlags.ANONYMOUS_SUPPORTED:
                o.set_anonymous(True)
                o.reply(Gio.MountOperationResult.HANDLED)
            else:
                state["refused" if pw is not None else "needs_password"] = True
                o.reply(Gio.MountOperationResult.ABORTED)

        def question(o, message, choices):
            o.set_choice(0)
            o.reply(Gio.MountOperationResult.HANDLED)
        op.connect("ask-password", ask)
        op.connect("ask-question", question)
        return op

    def _mount(self, f, op, timeout):
        """-> (ok, Gio error or None). Already mounted counts as success."""
        Gio, GLib = self.Gio, self.GLib
        loop, res = GLib.MainLoop(), {}

        def done(src, r):
            try:
                src.mount_enclosing_volume_finish(r)
                res["ok"] = True
            except GLib.Error as e:
                res["err"] = e
            loop.quit()
        f.mount_enclosing_volume(Gio.MountMountFlags.NONE, op, None, done)
        GLib.timeout_add_seconds(timeout, loop.quit)
        loop.run()
        if res.get("ok"):
            return True, None
        e = res.get("err")
        if e is None:
            return False, "timeout"
        if self._kind(e) == "ALREADY_MOUNTED":
            return True, None
        return False, e

    def _result_error(self, err, state):
        if err == "timeout":
            return fail(*map_error("TIMED_OUT"))
        if state.get("needs_password"):
            return fail("needs_password", "This computer needs a user name and password.")
        if state.get("refused"):
            return fail("denied", map_error("PERMISSION_DENIED")[1])
        kind = self._kind(err)
        code, text = map_error(kind)
        if code == "failed" or not text:
            text = (err.message or "").strip() or "Could not connect."
        if kind == "FAILED_HANDLED" and not state.get("needs_password"):
            code, text = "failed", "Could not connect."
        return fail(code, text)

    def _mount_info(self, m):
        root = m.get_root()
        uri = root.get_uri()
        path = root.get_path() or ""
        if not path:
            p = urllib.parse.urlsplit(uri)
            cand = os.path.join("/run/user/%d/gvfs" % os.getuid(), "smb-share:server=%s,share=%s" % (p.netloc.lower(), p.path.strip("/").split("/")[0]))
            if p.scheme == "smb" and os.path.isdir(cand):
                path = cand
        return {"uri": uri, "name": m.get_name(), "path": path, "scheme": urllib.parse.urlsplit(uri).scheme}

    def _network_mounts(self):
        res = []
        for m in self.Gio.VolumeMonitor.get().get_mounts():
            try:
                i = self._mount_info(m)
            except Exception:
                continue
            if i["scheme"] not in NET_SCHEMES:
                continue
            if i["scheme"] == "smb" and not urllib.parse.urlsplit(i["uri"]).path.strip("/"):
                continue            # the hidden server-level mount made by browsing
            res.append(i)
        return sorted(res, key=lambda i: i["name"].lower())

    # -- interface
    def caps(self):
        Gio = self.Gio
        schemes = list(Gio.Vfs.get_default().get_supported_uri_schemes())
        return {"gio": True, "smb": "smb" in schemes, "fuse": os.path.isdir("/run/user/%d/gvfs" % os.getuid()),
                "avahi": S.run(["avahi-browse", "-V"])[0] != 127, "keyring": self.keyring()}

    def keyring(self):
        Gio, GLib = self.Gio, self.GLib
        try:
            bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            r = bus.call_sync("org.freedesktop.secrets", "/org/freedesktop/secrets/aliases/default", "org.freedesktop.DBus.Properties",
                              "Get", GLib.Variant("(ss)", ("org.freedesktop.Secret.Collection", "Locked")), None,
                              Gio.DBusCallFlags.NONE, 3000, None)
            return "locked" if r.unpack()[0] else "unlocked"
        except Exception:
            return "unavailable"

    def browse(self, host, creds):
        Gio = self.Gio
        state = {"asked": 0}
        f = Gio.File.new_for_uri("smb://%s/" % host)
        ok, err = self._mount(f, self._op(creds, False, state), 20)
        if not ok:
            return self._result_error(err, state)
        try:
            it = f.enumerate_children("standard::name,standard::display-name,standard::type", Gio.FileQueryInfoFlags.NONE, None)
            names = []
            for info in it:
                n = info.get_name()
                if info.get_file_type() == Gio.FileType.DIRECTORY and not n.endswith("$"):
                    names.append(n)
        except self.GLib.Error as e:
            return self._result_error(e, state)
        return {"ok": True, "host": host, "shares": sorted(names, key=str.lower)}

    def connect(self, uri, creds, remember, prompt):
        Gio = self.Gio
        state = {"asked": 0}
        keyring = "n/a"
        saved = None
        if remember and creds and creds.get("password") is not None:
            keyring = self.keyring()
            if keyring != "unlocked":
                remember, saved = False, False
            else:
                saved = True
        f = Gio.File.new_for_uri(uri)
        ok, err = self._mount(f, self._op(creds, remember, state, True, prompt), 25)
        if not ok:
            return self._result_error(err, state)
        try:
            m = f.find_enclosing_mount(None)
            info = self._mount_info(m)
        except self.GLib.Error as e:
            return self._result_error(e, state)
        r = {"ok": True, "mount": info, "path": info["path"], "name": info["name"], "uri": info["uri"]}
        if saved is not None:
            r["passwordSaved"] = saved
            if saved is False:
                r["note"] = "Connected. The password was not saved because your keyring is %s." % keyring
        if not info["path"]:
            r["note"] = (r.get("note", "") + " Files cannot be opened until gvfs-fuse is installed.").strip()
        return r

    def mounts(self):
        return self._network_mounts()

    def disconnect(self, key):
        Gio, GLib = self.Gio, self.GLib
        want = uri_key(key) if "://" in key else key
        for m in self.Gio.VolumeMonitor.get().get_mounts():
            i = self._mount_info(m)
            if (uri_key(i["uri"]) == want) or (i["path"] and i["path"] == key):
                loop, res = GLib.MainLoop(), {}

                def done(src, r):
                    try:
                        src.unmount_with_operation_finish(r)
                        res["ok"] = True
                    except GLib.Error as e:
                        res["err"] = e
                    loop.quit()
                m.unmount_with_operation(Gio.MountUnmountFlags.NONE, Gio.MountOperation(), None, done)
                GLib.timeout_add_seconds(15, loop.quit)
                loop.run()
                if res.get("ok"):
                    return {"ok": True}
                e = res.get("err")
                return fail("failed", (e.message if e else "") or "Could not disconnect (is something still using it?).")
        return {"ok": True, "note": "Already disconnected."}


# ---------------------------------------------------------------- fake backend (tests + UI without a network)

class FakeBackend:
    """State: <fake state>/connect-fake.json {servers, hosts:{host:{auth:{user,password}|null, shares:[...]}}, mounts:[]}.
    SHARES_FAKE_KEYRING=locked simulates a locked keyring."""
    def __init__(self, path=None):
        self.path = path or os.path.join(S.fake_state(), "connect-fake.json")

    def _load(self):
        try:
            with open(self.path) as f:
                return json.load(f)
        except (OSError, ValueError):
            return {"servers": [], "hosts": {}, "mounts": []}

    def _store(self, d):
        with open(self.path, "w") as f:
            json.dump(d, f, indent=1)

    def keyring(self):
        return os.environ.get("SHARES_FAKE_KEYRING", "unlocked")

    def caps(self):
        return {"gio": True, "smb": True, "fuse": True, "avahi": True, "keyring": self.keyring()}

    def servers(self):
        return self._load().get("servers", [])

    def _auth(self, d, host, creds):
        h = d["hosts"].get(host)
        if h is None:
            return fail("not_found", map_error("HOST_NOT_FOUND")[1])
        a = h.get("auth")
        if a:
            if not creds or creds.get("password") is None:
                return fail("needs_password", "This computer needs a user name and password.")
            if creds.get("user") != a["user"] or creds.get("password") != a["password"]:
                return fail("denied", map_error("PERMISSION_DENIED")[1])
        return None

    def browse(self, host, creds):
        d = self._load()
        e = self._auth(d, host, creds)
        return e or {"ok": True, "host": host, "shares": sorted(d["hosts"][host]["shares"])}

    def connect(self, uri, creds, remember, prompt):
        n = normalize(uri)
        d = self._load()
        e = self._auth(d, n["host"], creds)
        if e:
            return e
        if n["share"] not in d["hosts"][n["host"]]["shares"]:
            return fail("not_found", "That share does not exist on %s." % n["host"])
        root = "smb://%s/%s" % (n["host"], n["share"])
        r = {"ok": True}
        for m in d["mounts"]:
            if uri_key(m["uri"]) == uri_key(root):
                r.update(mount=m, path=m["path"], name=m["name"], uri=m["uri"])
                return r
        path = os.path.join(os.path.dirname(self.path), "mnt", "smb-share:server=%s,share=%s" % (n["host"], n["share"]))
        os.makedirs(path, exist_ok=True)
        m = {"uri": root, "name": "%s on %s" % (n["share"], n["host"]), "path": path, "scheme": "smb"}
        d["mounts"].append(m)
        self._store(d)
        r.update(mount=m, path=path, name=m["name"], uri=root)
        if remember and creds and creds.get("password") is not None:
            r["passwordSaved"] = self.keyring() == "unlocked"
            if not r["passwordSaved"]:
                r["note"] = "Connected. The password was not saved because your keyring is %s." % self.keyring()
        return r

    def mounts(self):
        return self._load().get("mounts", [])

    def disconnect(self, key):
        d = self._load()
        want = uri_key(key) if "://" in key else key
        d["mounts"] = [m for m in d["mounts"] if uri_key(m["uri"]) != want and m["path"] != key]
        self._store(d)
        return {"ok": True}


def backend():
    if S.fake():
        return FakeBackend()
    try:
        return RealBackend()
    except Exception as e:            # python3-gi missing
        return None


# ---------------------------------------------------------------- commands

def creds_from(args, stdin_pw):
    c = {"user": opt(args, "--user"), "domain": opt(args, "--domain")}
    if stdin_pw is not None:
        c["password"] = stdin_pw
    return c if (c["user"] or "password" in c) else None


def do_discover(be):
    if isinstance(be, FakeBackend):
        return {"ok": True, "servers": be.servers()}
    return discover()


def do_browse(be, target, creds):
    n = normalize(target)
    if not n["ok"]:
        return n
    if n["scheme"] != "smb":
        return fail("bad_address", "Only SMB computers can be browsed; type the full address instead.")
    if creds is None and n["user"]:
        creds = None
    return be.browse(n["host"], creds)


def do_connect(be, target, creds, remember, prompt=True):
    n = normalize(target)
    if not n["ok"]:
        return n
    if n["kind"] == "server":
        return fail("bad_address", "Pick a share on that computer, or type \\\\%s\\sharename." % n["host"])
    if creds is None and n["user"]:
        creds = {"user": n["user"], "domain": n["domain"]}
    r = be.connect(n["uri"], creds, remember, prompt)
    if r.get("ok"):
        r["user"] = (creds or {}).get("user", "")
    return r


def do_reconnect(be):
    results = []
    have = {uri_key(m["uri"]) for m in be.mounts()}
    for c in load_saved():
        if not c["reconnectAtLogin"] or uri_key(c["uri"]) in have:
            continue
        creds = {"user": c["user"], "domain": c["domain"]} if c["user"] else None
        r = do_connect(be, c["uri"], creds, False, prompt=False)
        results.append({"uri": c["uri"], "ok": bool(r.get("ok")), "code": r.get("code", "")})
    return {"ok": True, "results": results}


def opt(args, name, default=""):
    return args[args.index(name) + 1] if name in args and args.index(name) + 1 < len(args) else default


def positional(args):
    res, skip = [], False
    for a in args:
        if skip:
            skip = False
        elif a in ("--user", "--domain", "--name"):
            skip = True
        elif not a.startswith("--"):
            res.append(a)
    return res


def _watchdog(sig, frm):
    out(fail("timeout", "The computer did not answer in time."))
    os._exit(0)


def main(argv):
    if not argv:
        out(fail("failed", "usage: connect.py caps|normalize|discover|browse|connect|mounts|disconnect|saved|save|unsave|set-reconnect|reconnect"))
        return 2
    cmd, args = argv[0], argv[1:]
    pos = positional(args)
    stdin_pw = None
    if "--password-stdin" in args:
        stdin_pw = sys.stdin.readline().rstrip("\n")
    signal.signal(signal.SIGALRM, _watchdog)
    signal.alarm(60 if cmd == "reconnect" else 40)
    try:
        if cmd == "normalize" and pos:
            out(normalize(pos[0]))
        elif cmd in ("saved",):
            out({"ok": True, "saved": load_saved()})
        elif cmd == "save" and pos:
            out(save_connection(pos[0], opt(args, "--name"), opt(args, "--user"), opt(args, "--domain"), "--remember" in args, "--reconnect" in args))
        elif cmd == "unsave" and pos:
            out(unsave_connection(pos[0]))
        elif cmd == "set-reconnect" and len(pos) >= 2:
            out(set_reconnect(pos[0], pos[1] == "on"))
        else:
            be = backend()
            if be is None:
                out(fail("unsupported", "python3-gi (Gio) is not installed."))
                return 0
            if cmd == "caps":
                out({"ok": True, "caps": be.caps()})
            elif cmd == "discover":
                out(do_discover(be))
            elif cmd == "browse" and pos:
                out(do_browse(be, pos[0], creds_from(args, stdin_pw)))
            elif cmd == "connect" and pos:
                out(do_connect(be, pos[0], creds_from(args, stdin_pw), "--remember" in args, "--no-prompt" not in args))
            elif cmd == "mounts":
                out({"ok": True, "mounts": be.mounts()})
            elif cmd == "disconnect" and pos:
                out(be.disconnect(pos[0]))
            elif cmd == "reconnect":
                out(do_reconnect(be))
            else:
                out(fail("failed", "bad command or arguments"))
                return 2
    except Exception as e:      # never leave the UI without JSON; never include argv/stdin
        out(fail("failed", "%s: %s" % (type(e).__name__, e)))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
