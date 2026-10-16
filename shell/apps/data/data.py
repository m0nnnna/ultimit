#!/usr/bin/env python3
"""data.py - filesystem helper for the Ultimit DATA file manager (stdlib only).

  data.py ls <dir>                 JSON {path, entries[], err}   (<dir> = "trash:" lists the Trash)
  data.py check <dstdir> <src>...  JSON [names that already exist in dstdir]
  data.py props <path>...          JSON lines: {"stat":..} then {"du":..}
  data.py apps <mime>              JSON [{id,name,icon,path,default}]
  data.py mime <path>              JSON {"mime": ..}
  data.py serve                    reads one JSON job spec per stdin line, streams JSON progress lines
                                   (ops: copy move rename delete trash restore mkdir newfile emptytrash,
                                   and the archive ops extract / compress, see arc.py)
  data.py arc-ls <archive> [--pw]  JSON listing of an archive for the archive view (--pw: password on stdin line 1)
  data.py mtp                      JSON {ok, tool, root, devices[], mounts[]}: MTP phones (udev ID_MTP_DEVICE=1) + live mounts
  data.py mtp-mount <id>           start go-mtpfs detached for device <id>, wait until usable -> JSON {ok, mp, err, ...}
  data.py mtp-umount <mp> [lazy]   fusermount3 -u[z] (fallback fusermount), rmdir the mountpoint -> JSON {ok, err}

MTP env gates: ULTIMIT_FAKE_MTP=<json> fakes detection, ULTIMIT_FAKE_MTPFS=<script> replaces go-mtpfs
(called as: script [-dev RE] MOUNTPOINT), ULTIMIT_DRY_RUN=1 only reports the command lines.

Trash follows the freedesktop spec: $XDG_DATA_HOME/Trash for the home filesystem, $topdir/.Trash/$uid or
$topdir/.Trash-$uid on other drives, so trashing is always a rename (never a copy onto the home disk).
"""
import sys, os, json, re, stat, shutil, time, pwd, grp, subprocess, urllib.parse, configparser
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arc

HOME = os.path.expanduser("~")
DATA_HOME = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
TRASH = os.path.join(DATA_HOME, "Trash")
TFILES = os.path.join(TRASH, "files")
TINFO = os.path.join(TRASH, "info")
UID = os.getuid()

def out(o):
    sys.stdout.write(json.dumps(o, ensure_ascii=False) + "\n")
    sys.stdout.flush()

# ---------------------------------------------------------------- mime
_globs = None
def load_globs():
    global _globs
    if _globs is not None:
        return _globs
    exts, names = {}, {}
    dirs = [os.path.join(DATA_HOME, "mime")] + [os.path.join(d, "mime") for d in
            (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")]
    for d in reversed(dirs):
        try:
            with open(os.path.join(d, "globs2"), encoding="utf-8", errors="replace") as f:
                for line in f:
                    if line.startswith("#"):
                        continue
                    p = line.rstrip("\n").split(":")
                    if len(p) < 3:
                        continue
                    pat, mime = p[2], p[1]
                    try:
                        w = int(p[0])
                    except ValueError:
                        w = 50
                    if pat.startswith("*.") and not any(c in pat[2:] for c in "*?["):
                        k = pat[2:].lower()
                        if k not in exts or exts[k][1] <= w:
                            exts[k] = (mime, w)
                    elif not any(c in pat for c in "*?["):
                        names[pat] = (mime, w)
        except OSError:
            pass
    _globs = (exts, names)
    return _globs

def mime_of_name(name):
    exts, names = load_globs()
    if name in names:
        return names[name][0]
    low = name.lower()
    i = low.find(".")
    while i != -1 and i < len(low) - 1:   # try longest suffix first (tar.gz, then gz)
        m = exts.get(low[i + 1:])
        if m:
            return m[0]
        i = low.find(".", i + 1)
    return "application/octet-stream" if "." in name else "unknown"

def natkey(s):
    return re.sub(r"\d+", lambda m: m.group().zfill(12), s.casefold())

# ---------------------------------------------------------------- ls
def parse_info(fn):
    cp = configparser.RawConfigParser(interpolation=None)
    cp.optionxform = str
    try:
        cp.read(fn, encoding="utf-8")
        sec = cp["Trash Info"]
        return urllib.parse.unquote(sec.get("Path", "")), sec.get("DeletionDate", "")
    except Exception:
        return "", ""

def iso_epoch(s):
    try:
        return time.mktime(time.strptime(s[:19], "%Y-%m-%dT%H:%M:%S"))
    except Exception:
        return 0

# ---------------------------------------------------------------- trash directories
def mount_top(p):
    """Mount point of the filesystem holding directory p."""
    p = os.path.realpath(p)
    dev = os.stat(p).st_dev
    while p != "/":
        up = os.path.dirname(p)
        if os.stat(up).st_dev != dev:
            return p
        p = up
    return p

def drive_mounts():
    """Mount points of local disks and tmpfs other than the home one (no network/FUSE: those may hang)."""
    try:
        home_dev = os.stat(HOME).st_dev
    except OSError:
        home_dev = None
    mps = []
    try:
        with open("/proc/mounts", encoding="utf-8", errors="replace") as f:
            for ln in f:
                parts = ln.split()
                if len(parts) < 3 or not (parts[0].startswith("/dev/") or parts[2] == "tmpfs"):
                    continue
                mp = parts[1].encode().decode("unicode_escape").encode("latin-1").decode("utf-8", "replace")
                try:
                    if os.stat(mp).st_dev != home_dev and mp not in mps:
                        mps.append(mp)
                except OSError:
                    pass
    except OSError:
        pass
    return mps

def top_trash_dirs(top):
    return [os.path.join(top, ".Trash", str(UID)), os.path.join(top, ".Trash-%d" % UID)]

def trash_dirs():
    """Every existing trash directory: (trash dir, topdir or None for the home trash)."""
    ds = [(TRASH, None)]
    for mp in drive_mounts():
        for t in top_trash_dirs(mp):
            if os.path.isdir(os.path.join(t, "files")) and not os.path.islink(t):
                ds.append((t, mp))
    return ds

def trash_topdir(t):
    """Topdir a non-home trash dir belongs to (relative Path= entries are relative to it)."""
    if t == TRASH:
        return None
    return os.path.dirname(os.path.dirname(t)) if os.path.basename(os.path.dirname(t)) == ".Trash" else os.path.dirname(t)

def is_trash_files(d):
    d = os.path.abspath(d)
    if d == os.path.abspath(TFILES):
        return True
    if os.path.basename(d) != "files":
        return False
    t = os.path.dirname(d)
    return os.path.basename(t) == ".Trash-%d" % UID or (
        os.path.basename(t) == str(UID) and os.path.basename(os.path.dirname(t)) == ".Trash")

def info_of(p):
    """.trashinfo path for an item inside some trash's files/ dir."""
    t = os.path.dirname(os.path.dirname(os.path.abspath(p)))
    return os.path.join(t, "info", os.path.basename(p) + ".trashinfo")

def trash_orig(p):
    orig, dt = parse_info(info_of(p))
    if orig and not orig.startswith("/"):
        top = trash_topdir(os.path.dirname(os.path.dirname(os.path.abspath(p))))
        orig = os.path.join(top or "/", orig)
    return orig, dt

def cmd_ls(d):
    ents = []
    err = ""
    if d == "trash:":
        items = []
        for t, top in trash_dirs():
            try:
                items += [(os.path.join(t, "files", nm), top) for nm in os.listdir(os.path.join(t, "files"))]
            except OSError:
                pass
        for p, top in items:
            nm = os.path.basename(p)
            orig, dt = trash_orig(p)
            n = os.path.basename(orig) if orig else nm
            try:
                st = os.lstat(p)
            except OSError:
                continue
            isd = stat.S_ISDIR(st.st_mode)
            ents.append({"n": n, "p": p, "k": natkey(n), "s": -1 if isd else st.st_size,
                         "m": iso_epoch(dt) or st.st_mtime, "d": isd, "l": stat.S_ISLNK(st.st_mode),
                         "t": "inode/directory" if isd else mime_of_name(n), "o": orig, "id": nm, "dr": top or "",
                         "h": n.startswith(".")})
        out({"path": d, "entries": ents, "err": ""})
        return
    try:
        with os.scandir(d) as it:
            for e in it:
                try:
                    st = e.stat()          # follows symlinks
                    isd = stat.S_ISDIR(st.st_mode)
                except OSError:
                    try:
                        st = e.stat(follow_symlinks=False); isd = False
                    except OSError:
                        continue
                n = e.name
                ents.append({"n": n, "p": e.path, "k": natkey(n), "s": -1 if isd else st.st_size,
                             "m": st.st_mtime, "d": isd, "l": e.is_symlink(),
                             "t": "inode/directory" if isd else mime_of_name(n),
                             "x": bool(st.st_mode & 0o111) and not isd, "h": n.startswith(".")})
    except OSError as ex:
        err = ex.strerror or str(ex)
    out({"path": d, "entries": ents, "err": err})

# ---------------------------------------------------------------- check / props
def cmd_check(dst, srcs):
    res = []
    for s in srcs:
        n = os.path.basename(s.rstrip("/"))
        t = os.path.join(dst, n)
        if os.path.lexists(t):
            res.append({"src": s, "n": n, "same": os.path.realpath(t) == os.path.realpath(s)})
    out(res)

def du(paths):
    size = files = dirs = 0
    for p in paths:
        try:
            st = os.lstat(p)
        except OSError:
            continue
        if stat.S_ISDIR(st.st_mode):
            dirs += 1
            for root, ds, fs in os.walk(p, followlinks=False):
                dirs += len(ds)
                for f in fs:
                    try:
                        size += os.lstat(os.path.join(root, f)).st_size
                        files += 1
                    except OSError:
                        pass
        else:
            size += st.st_size
            files += 1
    return {"size": size, "files": files, "dirs": dirs}

def file_mime(p):
    try:
        r = subprocess.run(["file", "--mime-type", "-b", "--", p], capture_output=True, text=True, timeout=5)
        m = r.stdout.strip()
        if m:
            return m
    except Exception:
        pass
    return mime_of_name(os.path.basename(p))

def cmd_props(paths):
    p = paths[0]
    try:
        st = os.lstat(p)
    except OSError as ex:
        out({"stat": {"err": ex.strerror}}); return
    try:
        owner = pwd.getpwuid(st.st_uid).pw_name
    except KeyError:
        owner = str(st.st_uid)
    try:
        group = grp.getgrgid(st.st_gid).gr_name
    except KeyError:
        group = str(st.st_gid)
    isd = os.path.isdir(p)
    out({"stat": {"name": os.path.basename(p.rstrip("/")) or "/", "path": p, "dir": os.path.dirname(p.rstrip("/")) or "/",
                  "isdir": isd, "link": os.readlink(p) if stat.S_ISLNK(st.st_mode) else "",
                  "size": st.st_size, "mode": stat.filemode(st.st_mode), "octal": "%03o" % (st.st_mode & 0o777),
                  "owner": owner, "group": group, "mtime": st.st_mtime, "atime": st.st_atime, "ctime": st.st_ctime,
                  "mime": "inode/directory" if isd else file_mime(p), "count": len(paths)}})
    out({"du": du(paths)})

# ---------------------------------------------------------------- open with
def desktop_dirs():
    xs = (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":")
    return [os.path.join(DATA_HOME, "applications")] + [os.path.join(d, "applications") for d in xs]

def cmd_apps(mime):
    want = {mime}
    if mime.startswith("text/") or mime.endswith("+xml") or mime.endswith("json") or mime.endswith("script"):
        want.add("text/plain")
    ids = []
    for d in desktop_dirs():
        try:
            with open(os.path.join(d, "mimeinfo.cache"), encoding="utf-8", errors="replace") as f:
                for line in f:
                    k, _, v = line.strip().partition("=")
                    if k in want:
                        for i in v.split(";"):
                            if i and i not in ids:
                                ids.append(i)
        except OSError:
            pass
    try:
        default = subprocess.run(["xdg-mime", "query", "default", mime], capture_output=True, text=True,
                                 timeout=5).stdout.strip()
    except Exception:
        default = ""
    res = []
    for i in ids:
        path = ""
        for d in desktop_dirs():
            c = os.path.join(d, i)
            if os.path.exists(c):
                path = c; break
        if not path:
            continue
        cp = configparser.RawConfigParser(interpolation=None, strict=False)
        cp.optionxform = str
        try:
            cp.read(path, encoding="utf-8")
            s = cp["Desktop Entry"]
        except Exception:
            continue
        if s.get("NoDisplay", "false").lower() == "true" or s.get("Hidden", "false").lower() == "true":
            continue
        res.append({"id": i, "name": s.get("Name", i), "icon": s.get("Icon", ""), "path": path,
                    "default": i == default})
    res.sort(key=lambda a: (not a["default"], a["name"].casefold()))
    out(res)

# ---------------------------------------------------------------- job runner
def unique_name(dst):
    d, n = os.path.split(dst)
    base, ext = os.path.splitext(n)
    if n.startswith(".") and ext == n:
        base, ext = n, ""
    if base.endswith(".tar"):          # keep .tar.gz style double extensions together
        pass
    m = re.match(r"^(.*) \(copy(?: (\d+))?\)$", base)
    root = m.group(1) if m else base
    k = 1
    while True:
        cand = os.path.join(d, "%s (copy%s)%s" % (root, "" if k == 1 else " %d" % k, ext))
        if not os.path.lexists(cand):
            return cand
        k += 1

def remove_any(p):
    if os.path.isdir(p) and not os.path.islink(p):
        shutil.rmtree(p)
    else:
        os.unlink(p)

class Job:
    def __init__(self, spec):
        self.items = spec["items"]
        self.total_bytes = 0
        self.done_bytes = 0
        self.last = 0
        self.errors = []
        self.idx = 0
        self.results = []
        self.warns = []           # non-fatal notes shown in the done toast
        self.codes = []           # machine-readable failure codes (needpw / wrongpw / ...) for the UI to react to
        self.retry = []           # indexes of items that failed with needpw / wrongpw

    def tick(self, name, force=False):
        now = time.time()
        if force or now - self.last > 0.1:
            self.last = now
            out({"p": self.idx, "n": len(self.items), "name": name, "bytes": self.done_bytes, "total": self.total_bytes})

    def copyfile(self, s, d):
        with open(s, "rb") as fi, open(d, "wb") as fo:
            while True:
                b = fi.read(1 << 20)
                if not b:
                    break
                fo.write(b)
                self.done_bytes += len(b)
                self.tick(os.path.basename(s))
        try:
            shutil.copystat(s, d, follow_symlinks=False)
        except OSError:
            pass                      # e.g. MTP/FUSE cannot set times or modes

    def copytree(self, s, d):
        os.makedirs(d, exist_ok=True)
        for e in os.scandir(s):
            t = os.path.join(d, e.name)
            self.copyany(e.path, t)
        try:
            shutil.copystat(s, d, follow_symlinks=False)
        except OSError:
            pass

    def copyany(self, s, d):
        if os.path.islink(s):
            os.symlink(os.readlink(s), d)
        elif os.path.isdir(s):
            self.copytree(s, d)
        else:
            self.copyfile(s, d)

    def resolve(self, it):
        """Return (dst or None to skip)."""
        s, dst = it["src"], it["dst"]
        mode = it.get("mode", "ask")
        if os.path.realpath(s) == os.path.realpath(dst):
            if it["op"] == "move":
                return None
            return unique_name(dst)
        if os.path.lexists(dst):
            if mode == "skip":
                return None
            if mode == "both":
                return unique_name(dst)
            if mode == "replace":
                return dst
            raise OSError("'%s' already exists" % os.path.basename(dst))
        return dst

    def size_of(self, it):
        try:
            return du([it["src"]])["size"] if it["op"] in ("copy", "move") else 0
        except Exception:
            return 0

    def do(self, it):
        op = it["op"]
        s = it.get("src", "")
        if op == "mkdir":
            p = it["dst"]
            os.mkdir(p); self.results.append(p); return
        if op == "newfile":
            p = it["dst"]
            fd = os.open(p, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644); os.close(fd); self.results.append(p); return
        if op == "rename":
            d = it["dst"]
            if os.path.lexists(d):
                raise OSError("'%s' already exists" % os.path.basename(d))
            os.rename(s, d); self.results.append(d); return
        if op == "delete":
            remove_any(s); return
        if op == "trash":
            self.trash(s); return
        if op == "restore":
            self.restore(s); return
        if op == "emptytrash":
            for t, _ in trash_dirs():
                fd, idir = os.path.join(t, "files"), os.path.join(t, "info")
                for n in os.listdir(fd) if os.path.isdir(fd) else []:
                    remove_any(os.path.join(fd, n))
                for n in os.listdir(idir) if os.path.isdir(idir) else []:
                    try: os.unlink(os.path.join(idir, n))
                    except OSError: pass
            return
        if op == "extract":
            arc.do_extract(self, it); return
        if op == "compress":
            arc.do_compress(self, it); return
        if op in ("copy", "move"):
            dst = self.resolve(it)
            if dst is None:
                return
            real_s = os.path.realpath(s)
            if os.path.isdir(s) and not os.path.islink(s) and (os.path.realpath(dst) + os.sep).startswith(real_s + os.sep):
                raise OSError("cannot put a folder inside itself")
            if os.path.lexists(dst) and it.get("mode") == "replace":
                tmp = dst + ".ultimit-old"
                os.rename(dst, tmp)
                try:
                    self.transfer(op, s, dst)
                except BaseException:
                    if os.path.lexists(dst): remove_any(dst)
                    os.rename(tmp, dst); raise
                remove_any(tmp)
            else:
                self.transfer(op, s, dst)
            self.results.append(dst)

    def transfer(self, op, s, dst):
        if op == "move":
            try:
                os.rename(s, dst)
                self.done_bytes += self.size_hint(s, dst)
                return
            except OSError:
                pass
            self.copyany(s, dst)
            remove_any(s)
        else:
            self.copyany(s, dst)

    def size_hint(self, s, d):
        return 0

    def trash_dir_for(self, s):
        """(trash dir, topdir or None) on the same filesystem as s, created if needed."""
        parent = os.path.dirname(s)
        dev = os.stat(parent).st_dev
        os.makedirs(TFILES, mode=0o700, exist_ok=True)
        os.makedirs(TINFO, mode=0o700, exist_ok=True)
        if os.stat(TRASH).st_dev == dev:
            return TRASH, None
        top = mount_top(parent)
        shared = os.path.join(top, ".Trash")
        try:
            st = os.lstat(shared)
            ok = stat.S_ISDIR(st.st_mode) and st.st_mode & stat.S_ISVTX     # spec: shared .Trash must be sticky, no symlink
        except OSError:
            ok = False
        cands = top_trash_dirs(top) if ok else top_trash_dirs(top)[1:]
        why = None
        for t in cands:
            try:
                os.makedirs(os.path.join(t, "files"), mode=0o700, exist_ok=True)
                os.makedirs(os.path.join(t, "info"), mode=0o700, exist_ok=True)
                if not os.path.islink(t) and os.stat(t).st_dev == dev:
                    return t, top
            except OSError as ex:
                why = ex
        if why is not None and why.errno == 30:     # EROFS
            raise OSError("the drive is read-only")
        raise OSError("this drive has no Trash (%s); Shift+Del deletes for good" %
                      (why.strerror if why is not None else "cannot create one"))

    def trash(self, s):
        s = os.path.abspath(s)
        t, top = self.trash_dir_for(s)
        tinfo, tfiles = os.path.join(t, "info"), os.path.join(t, "files")
        base = os.path.basename(s)
        n, k = base, 0
        while True:
            try:
                fd = os.open(os.path.join(tinfo, n + ".trashinfo"), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
                break
            except FileExistsError:
                k += 1
                b, e = os.path.splitext(base)
                n = "%s.%d%s" % (b, k, e)
        rel = os.path.relpath(s, top) if top else s     # relative on drives: survives a new mount point
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("[Trash Info]\nPath=%s\nDeletionDate=%s\n" % (
                urllib.parse.quote(rel, safe="/"), time.strftime("%Y-%m-%dT%H:%M:%S")))
        try:
            os.rename(s, os.path.join(tfiles, n))       # same filesystem by construction: never a copy
        except BaseException:
            try: os.unlink(os.path.join(tinfo, n + ".trashinfo"))
            except OSError: pass
            raise

    def restore(self, tp):
        n = os.path.basename(tp)
        info = info_of(tp)
        orig, _ = trash_orig(tp)
        if not orig:
            raise OSError("no .trashinfo for '%s'" % n)
        os.makedirs(os.path.dirname(orig), exist_ok=True)
        dst = orig
        if os.path.lexists(dst):
            dst = unique_name(dst)
        try:
            os.rename(tp, dst)
        except OSError:
            self.copyany(tp, dst)
            remove_any(tp)
        try: os.unlink(info)
        except OSError: pass
        self.results.append(dst)

    def delete_trash_info(self, p):
        # permanently deleting an item inside the trash also removes its info file
        if is_trash_files(os.path.dirname(os.path.abspath(p))):
            try: os.unlink(info_of(p))
            except OSError: pass

    def run(self):
        for it in self.items:
            if it["op"] in ("copy", "move"):
                self.total_bytes += self.size_of(it)
        for i, it in enumerate(self.items):
            self.idx = i
            name = os.path.basename((it.get("src") or it.get("dst") or "").rstrip("/"))
            self.tick(name, True)
            try:
                self.do(it)
                if it["op"] == "delete":
                    self.delete_trash_info(it["src"])
            except arc.ArcError as ex:
                if ex.code in ("needpw", "wrongpw"):
                    self.codes.append(ex.code); self.retry.append(i)
                self.errors.append("%s: %s" % (name, ex))
            except Exception as ex:
                self.errors.append("%s: %s" % (name, getattr(ex, "strerror", None) or str(ex)))
        out({"done": True, "errors": self.errors, "results": self.results, "count": len(self.items),
             "warns": self.warns, "codes": self.codes, "retry": self.retry})

def cmd_serve():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            Job(json.loads(line)).run()
        except Exception as ex:      # never die silently: the UI would wait forever
            out({"done": True, "errors": ["job failed: %s" % ex], "results": [], "count": 0})

# ---------------------------------------------------------------- MTP phones (go-mtpfs, no gvfs)
def mtp_root():
    rd = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
    return os.path.join(rd, "ultimit-mtp")

def safe_name(s):
    return re.sub(r"[^A-Za-z0-9._-]+", "_", s).strip("._-")[:64] or "phone"

def udev_dec(s):
    return re.sub(r"\\x([0-9a-fA-F]{2})", lambda m: chr(int(m.group(1), 16)), s)

def mk_device(dev_id, vendor, model, serial, bus, devnum):
    label = model or vendor or "Phone"
    return {"id": dev_id, "safe": safe_name(label + "-" + (serial or dev_id)), "label": label, "vendor": vendor,
            "model": model, "serial": serial, "bus": bus, "dev": devnum}

def mtp_devices():
    """List MTP devices. Raises on a hard failure so callers do not mistake it for 'unplugged'."""
    fake = os.environ.get("ULTIMIT_FAKE_MTP")
    if fake:
        with open(fake, encoding="utf-8") as f:
            d = json.load(f)
        if isinstance(d, dict):
            d = d.get("devices", [])
        return [mk_device(str(x.get("id") or x.get("serial") or "fake%d" % i), x.get("vendor", ""), x.get("model", ""),
                          x.get("serial", ""), int(x.get("bus", 1)), int(x.get("dev", i + 2)))
                for i, x in enumerate(d)]
    base = "/sys/bus/usb/devices"
    res = []
    for name in sorted(os.listdir(base)):
        if ":" in name:
            continue                  # interfaces
        p = os.path.join(base, name)
        try:
            with open(os.path.join(p, "bDeviceClass")) as f:
                if f.read().strip() == "09":
                    continue          # hubs
        except OSError:
            pass
        try:
            r = subprocess.run(["udevadm", "info", "-q", "property", "-p", p], capture_output=True, text=True, timeout=5)
        except FileNotFoundError:
            raise
        except Exception:
            continue
        props = {}
        for line in r.stdout.splitlines():
            k, _, v = line.partition("=")
            props[k] = v
        if props.get("ID_MTP_DEVICE") != "1":
            continue
        vendor = props.get("ID_VENDOR_FROM_DATABASE") or udev_dec(props.get("ID_VENDOR_ENC", "")) or props.get("ID_VENDOR", "").replace("_", " ")
        model = udev_dec(props.get("ID_MODEL_ENC", "")) or props.get("ID_MODEL", "").replace("_", " ") or props.get("ID_MODEL_FROM_DATABASE", "")
        try:
            bus, devnum = int(props.get("BUSNUM", "0")), int(props.get("DEVNUM", "0"))
        except ValueError:
            bus = devnum = 0
        res.append(mk_device("usb-" + name if not props.get("ID_SERIAL_SHORT") else props["ID_SERIAL_SHORT"],
                             vendor.strip(), model.strip(), props.get("ID_SERIAL_SHORT", ""), bus, devnum))
    return res

def pid_alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False

def mtp_mounts():
    """Live MTP mounts under mtp_root(): real fuse mounts from /proc/mounts (+ pid-file fakes)."""
    root = mtp_root()
    res = {}
    try:
        with open("/proc/mounts", encoding="utf-8", errors="replace") as f:
            for line in f:
                p = line.split()
                # go-mtpfs mounts show up as fuse.rawBridge
                if len(p) < 3 or not (p[2] == "fuse" or p[2].startswith("fuse.")):
                    continue
                mp = re.sub(r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), p[1])
                if os.path.dirname(mp) == root:
                    res[os.path.basename(mp)] = mp
    except OSError:
        pass
    if os.environ.get("ULTIMIT_FAKE_MTPFS"):
        try:
            for n in os.listdir(root):
                if n.startswith(".fake-") and n.endswith(".pid"):
                    nm = n[6:-4]
                    with open(os.path.join(root, n)) as f:
                        pid = int(f.read().strip() or 0)
                    if pid and pid_alive(pid) and os.path.isdir(os.path.join(root, nm)):
                        res[nm] = os.path.join(root, nm)
        except (OSError, ValueError):
            pass
    return [{"name": k, "mp": v} for k, v in sorted(res.items())]

def mtp_tool():
    fake = os.environ.get("ULTIMIT_FAKE_MTPFS")
    if fake:
        return fake if os.access(fake, os.X_OK) else ""
    return shutil.which("go-mtpfs") or ""

def cmd_mtp():
    try:
        devs = mtp_devices()
    except Exception as ex:
        out({"ok": False, "err": str(ex), "root": mtp_root(), "devices": [], "mounts": [], "tool": bool(mtp_tool())})
        return
    out({"ok": True, "root": mtp_root(), "tool": bool(mtp_tool()), "devices": devs, "mounts": mtp_mounts()})

def mtp_in_root(mp):
    return os.path.dirname(os.path.normpath(mp)) == mtp_root()

def mtp_nonempty(mp):
    try:
        return any(True for _ in os.scandir(mp))
    except OSError:
        return False

def cmd_mtp_mount(dev_id):
    dry = os.environ.get("ULTIMIT_DRY_RUN") == "1"
    try:
        devs = mtp_devices()
    except Exception as ex:
        out({"ok": False, "err": "cannot enumerate USB devices: %s" % ex}); return
    d = next((x for x in devs if x["id"] == dev_id), None)
    if not d:
        out({"ok": False, "err": "phone not found (unplugged?)"}); return
    root = mtp_root()
    mp = os.path.join(root, d["safe"])
    tool = mtp_tool() or "go-mtpfs"
    argv = [tool]
    if len(devs) > 1:
        argv += ["-dev", re.escape(d["serial"] or d["model"] or d["label"])]
    argv.append(mp)
    if dry:
        out({"ok": False, "dry": ["mkdir -p " + mp, " ".join(argv)], "mp": mp}); return
    if not mtp_tool():
        out({"ok": False, "err": "nomtpfs"}); return
    if any(m["name"] == d["safe"] for m in mtp_mounts()):
        out({"ok": True, "mp": mp, "already": True}); return
    os.makedirs(root, mode=0o700, exist_ok=True)
    os.makedirs(mp, exist_ok=True)
    logf = os.path.join(root, ".log-" + d["safe"])
    pidf = os.path.join(root, ".fake-" + d["safe"] + ".pid")
    with open(logf, "wb") as lf:
        pr = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=lf, stderr=lf, start_new_session=True)
    if os.environ.get("ULTIMIT_FAKE_MTPFS"):      # real mounts are tracked via /proc/mounts
        with open(pidf, "w") as f:
            f.write(str(pr.pid))
    t0 = time.time()
    ok = empty = False
    while time.time() - t0 < 15:
        if pr.poll() is not None:
            break
        if mtp_nonempty(mp):
            ok = True; break
        if os.path.ismount(mp):
            for _ in range(8):        # mounted but nothing listed yet (locked phone?): give it a moment
                time.sleep(0.5)
                if mtp_nonempty(mp):
                    break
            ok = True; empty = not mtp_nonempty(mp); break
        time.sleep(0.25)
    try:
        with open(logf, encoding="utf-8", errors="replace") as f:
            tail = [l.strip() for l in f.read().splitlines() if l.strip()][-1:]
    except OSError:
        tail = []
    if ok:
        out({"ok": True, "mp": mp, "empty": empty, "log": tail[0] if tail else ""}); return
    code = pr.poll()
    if code is None:
        pr.terminate()
        try: pr.wait(3)
        except Exception: pr.kill()
    try: os.unlink(pidf)
    except OSError: pass
    try: os.rmdir(mp)
    except OSError: pass
    out({"ok": False, "err": "timeout" if code is None else "exited", "log": tail[0] if tail else "", "code": code})

def cmd_mtp_umount(mp, lazy):
    dry = os.environ.get("ULTIMIT_DRY_RUN") == "1"
    mp = os.path.normpath(mp)
    if not mtp_in_root(mp):
        out({"ok": False, "err": "not an Ultimit MTP mountpoint"}); return
    flag = "-uz" if lazy else "-u"
    cmds = [["fusermount3", flag, mp], ["fusermount", flag, mp]]
    fake = os.environ.get("ULTIMIT_FAKE_MTPFS")
    if dry:
        out({"ok": True, "dry": [" ".join(c) for c in cmds[:1]] + ["rmdir " + mp]}); return
    err = ""
    if fake:
        pidf = os.path.join(os.path.dirname(mp), ".fake-" + os.path.basename(mp) + ".pid")
        try:
            with open(pidf) as f:
                pid = int(f.read().strip())
            os.kill(pid, 15)
        except (OSError, ValueError):
            pass
        try: os.unlink(pidf)
        except OSError: pass
        if os.path.isdir(mp):
            for n in os.listdir(mp):
                remove_any(os.path.join(mp, n))
    else:
        done = False
        for c in cmds:
            try:
                r = subprocess.run(c, capture_output=True, text=True, timeout=30)
            except FileNotFoundError:
                continue
            except subprocess.TimeoutExpired:
                err = "%s timed out" % c[0]; continue
            if r.returncode == 0:
                done = True; break
            lines = (r.stderr or r.stdout).strip().splitlines()
            err = lines[-1] if lines else err
        if not done and not any(m["mp"] == mp for m in mtp_mounts()):
            done = True               # already gone
        if not done:
            out({"ok": False, "err": err or "fusermount not found"}); return
    try:
        os.rmdir(mp)
    except FileNotFoundError:
        pass
    except OSError as ex:
        out({"ok": False, "err": "unmounted, but cannot remove %s: %s" % (mp, ex.strerror)}); return
    out({"ok": True})

def main():
    arc.init(mime_of_name, natkey)
    a = sys.argv[1:]
    try:
        if a[0] == "ls": cmd_ls(a[1])
        elif a[0] == "check": cmd_check(a[1], a[2:])
        elif a[0] == "props": cmd_props(a[1:])
        elif a[0] == "apps": cmd_apps(a[1])
        elif a[0] == "mime": out({"mime": file_mime(a[1])})
        elif a[0] == "serve": arc.install_cancel_handler(); cmd_serve()
        elif a[0] == "arc-ls": out(arc.cmd_arc_ls(a[1], "--pw" in a[2:]))
        elif a[0] == "mtp": cmd_mtp()
        elif a[0] == "mtp-mount": cmd_mtp_mount(a[1])
        elif a[0] == "mtp-umount": cmd_mtp_umount(a[1], len(a) > 2 and a[2] == "lazy")
    except BrokenPipeError:
        pass
    except KeyboardInterrupt:
        pass
    except arc.Cancelled:             # SIGTERM from the shell's Cancel: children and staging are already gone
        pass

if __name__ == "__main__":
    main()
