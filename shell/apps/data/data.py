#!/usr/bin/env python3
"""data.py - filesystem helper for the Ultimit DATA file manager (stdlib only).

  data.py ls <dir>                 JSON {path, entries[], err}   (<dir> = "trash:" lists the Trash)
  data.py check <dstdir> <src>...  JSON [names that already exist in dstdir]
  data.py props <path>...          JSON lines: {"stat":..} then {"du":..}
  data.py apps <mime>              JSON [{id,name,icon,path,default}]
  data.py mime <path>              JSON {"mime": ..}
  data.py serve                    reads one JSON job spec per stdin line, streams JSON progress lines, streams JSON progress lines

Trash follows the freedesktop spec under $XDG_DATA_HOME/Trash (always the home trash).
"""
import sys, os, json, re, stat, shutil, time, pwd, grp, subprocess, urllib.parse, configparser

HOME = os.path.expanduser("~")
DATA_HOME = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share")
TRASH = os.path.join(DATA_HOME, "Trash")
TFILES = os.path.join(TRASH, "files")
TINFO = os.path.join(TRASH, "info")

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

def cmd_ls(d):
    ents = []
    err = ""
    if d == "trash:":
        try:
            names = os.listdir(TFILES)
        except OSError:
            names = []
        for nm in names:
            p = os.path.join(TFILES, nm)
            orig, dt = parse_info(os.path.join(TINFO, nm + ".trashinfo"))
            n = os.path.basename(orig) if orig else nm
            try:
                st = os.lstat(p)
            except OSError:
                continue
            isd = stat.S_ISDIR(st.st_mode)
            ents.append({"n": n, "p": p, "k": natkey(n), "s": -1 if isd else st.st_size,
                         "m": iso_epoch(dt) or st.st_mtime, "d": isd, "l": stat.S_ISLNK(st.st_mode),
                         "t": "inode/directory" if isd else mime_of_name(n), "o": orig, "id": nm,
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
class Cancelled(Exception):
    pass

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
        shutil.copystat(s, d, follow_symlinks=False)

    def copytree(self, s, d):
        os.makedirs(d, exist_ok=True)
        for e in os.scandir(s):
            t = os.path.join(d, e.name)
            self.copyany(e.path, t)
        shutil.copystat(s, d, follow_symlinks=False)

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
            for n in os.listdir(TFILES) if os.path.isdir(TFILES) else []:
                remove_any(os.path.join(TFILES, n))
            for n in os.listdir(TINFO) if os.path.isdir(TINFO) else []:
                try: os.unlink(os.path.join(TINFO, n))
                except OSError: pass
            return
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

    def trash(self, s):
        os.makedirs(TFILES, mode=0o700, exist_ok=True)
        os.makedirs(TINFO, mode=0o700, exist_ok=True)
        s = os.path.abspath(s)
        base = os.path.basename(s)
        n, k = base, 0
        while True:
            try:
                fd = os.open(os.path.join(TINFO, n + ".trashinfo"), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
                break
            except FileExistsError:
                k += 1
                b, e = os.path.splitext(base)
                n = "%s.%d%s" % (b, k, e)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("[Trash Info]\nPath=%s\nDeletionDate=%s\n" % (
                urllib.parse.quote(s, safe="/"), time.strftime("%Y-%m-%dT%H:%M:%S")))
        dst = os.path.join(TFILES, n)
        try:
            try:
                os.rename(s, dst)
            except OSError:
                self.copyany(s, dst)
                remove_any(s)
        except BaseException:
            try: os.unlink(os.path.join(TINFO, n + ".trashinfo"))
            except OSError: pass
            raise

    def restore(self, tp):
        n = os.path.basename(tp)
        info = os.path.join(TINFO, n + ".trashinfo")
        orig, _ = parse_info(info)
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
        if os.path.dirname(os.path.abspath(p)) == os.path.abspath(TFILES):
            try: os.unlink(os.path.join(TINFO, os.path.basename(p) + ".trashinfo"))
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
            except Exception as ex:
                self.errors.append("%s: %s" % (name, getattr(ex, "strerror", None) or str(ex)))
        out({"done": True, "errors": self.errors, "results": self.results, "count": len(self.items)})

def cmd_serve():
    for line in sys.stdin:
        line = line.strip()
        if line:
            Job(json.loads(line)).run()

def main():
    a = sys.argv[1:]
    try:
        if a[0] == "ls": cmd_ls(a[1])
        elif a[0] == "check": cmd_check(a[1], a[2:])
        elif a[0] == "props": cmd_props(a[1:])
        elif a[0] == "apps": cmd_apps(a[1])
        elif a[0] == "mime": out({"mime": file_mime(a[1])})
        elif a[0] == "serve": cmd_serve()
    except BrokenPipeError:
        pass
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
