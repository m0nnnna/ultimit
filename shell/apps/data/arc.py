"""arc.py - archive support for the Ultimit DATA file manager (stdlib only, 7-Zip backed).

Imported by data.py:
  arc.cmd_arc_ls(path, use_pw)       JSON listing of an archive for the archive view (data.py arc-ls)
  arc.do_extract(job, item)          job op "extract":  mode here | folder | into | selected | open
  arc.do_compress(job, item)         job op "compress": fmt zip | 7z | tar.gz

Security model
  * Passwords only ever travel over a pipe to 7z's stdin (its "Enter password" prompt), never in argv,
    never in the environment, never on disk.
  * Extraction lists the archive first and refuses it when any entry has a ".." component, a leading
    "/" (or "\\") or a drive letter (zip-slip).  It then extracts into a private staging directory
    next to the destination, removes/neutralises any symlink that escapes the staging tree, strips
    setuid/setgid bits, and only then moves the result into place without ever overwriting.
  * 7z is told -snl when compressing (symlinks are stored as links instead of following them out of the
    tree) and -spd (no wildcard expansion of file names).
  * Cancel (SIGTERM from the shell) kills only the 7z children this process started, by pid, and removes
    staging / half-written output.  The children also get PR_SET_PDEATHSIG so they die with the helper.
"""
import os, sys, re, json, time, stat, shutil, signal, hashlib, tempfile, subprocess, selectors, ctypes, tarfile, gzip

LISTCAP = 50000
SEVENZ = os.environ.get("ULTIMIT_7Z") or shutil.which("7zz") or shutil.which("7z") or shutil.which("7za") or "7z"
SEP = "\x01"                       # separates archive path from inner path in the virtual "arc:" locations
CHILDREN = set()                   # live 7z subprocesses started by this helper
_mime = lambda n: "application/octet-stream"
_natkey = lambda s: s.casefold()

def init(mime_fn, natkey_fn):
    global _mime, _natkey
    _mime, _natkey = mime_fn, natkey_fn

class ArcError(Exception):
    def __init__(self, msg, code=""):
        Exception.__init__(self, msg)
        self.code = code

class Cancelled(BaseException):    # BaseException: must not be swallowed by generic `except Exception`
    pass

# ---------------------------------------------------------------- process plumbing
try:
    _libc = ctypes.CDLL(None, use_errno=True)
except Exception:
    _libc = None

def _preexec():
    if _libc is not None:
        _libc.prctl(1, signal.SIGKILL)       # PR_SET_PDEATHSIG: never outlive the helper

def kill_children():
    for p in list(CHILDREN):
        try:
            if p.poll() is None:
                p.kill()
        except Exception:
            pass

def install_cancel_handler():
    def on_term(signum, frame):
        kill_children()
        raise Cancelled()
    signal.signal(signal.SIGTERM, on_term)

def spawn(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=None):
    env = dict(os.environ)
    env["LC_ALL"] = "C.UTF-8"               # names as UTF-8 regardless of the session locale
    p = subprocess.Popen([SEVENZ] + argv, stdin=stdin, stdout=stdout, stderr=stderr, cwd=cwd, env=env,
                         preexec_fn=_preexec)
    CHILDREN.add(p)
    return p

def reap(p):
    try:
        if p.poll() is None:
            p.kill()
        p.wait()
    except Exception:
        pass
    CHILDREN.discard(p)
    for f in (p.stdin, p.stdout, p.stderr):
        try:
            if f:
                f.close()
        except Exception:
            pass

def send_pw(p, pw):
    """Hand the password to 7z's prompt over the pipe, then close so a second prompt sees EOF."""
    try:
        p.stdin.write((pw + "\n").encode("utf-8"))
        p.stdin.flush()
    except OSError:
        pass
    try:
        p.stdin.close()
    except OSError:
        pass

TOK = re.compile(r"[\r\b\n]+")
PCT = re.compile(r"^\s*(\d{1,3})%")

class Stream:
    """Splits 7z's console output into progress percentages and text lines."""
    def __init__(self):
        self.buf = ""
        self.lines = []
        self.pct = None
        self.prompted = False
    def feed(self, data):
        self.buf += data.decode("utf-8", "replace")
        if "Enter password" in self.buf:
            self.prompted = True
        toks = TOK.split(self.buf)
        self.buf = toks.pop()
        for t in toks:
            self.token(t)
    def token(self, t):
        m = PCT.match(t)
        if m:
            self.pct = min(100, int(m.group(1)))
        elif t.strip():
            self.lines.append(t.strip())
            if len(self.lines) > 600:
                del self.lines[100:300]
    def finish(self):
        if self.buf:
            self.token(self.buf)
            self.buf = ""

def pump(readers, on_pct):
    """readers: [(file, Stream, reports_progress)]; read until all hit EOF."""
    sel = selectors.DefaultSelector()
    for f, st, prog in readers:
        sel.register(f, selectors.EVENT_READ, (st, prog))
    open_n = len(readers)
    while open_n:
        for key, _ in sel.select():
            st, prog = key.data
            data = os.read(key.fileobj.fileno(), 65536)
            if not data:
                sel.unregister(key.fileobj)
                open_n -= 1
                st.finish()
                continue
            st.feed(data)
            if prog and st.pct is not None:
                on_pct(st.pct)
    sel.close()

def run_pipeline(argvs, pw=None, on_pct=None, cwd=None):
    """Run one 7z, or two chained (a | b: a decompresses to stdout, b reads a tar from stdin).
    Returns (rc, lines, prompted)."""
    on_pct = on_pct or (lambda p: None)
    procs = []
    try:
        if len(argvs) == 1:
            p = spawn(argvs[0], stdin=subprocess.PIPE if pw is not None else subprocess.DEVNULL, cwd=cwd)
            procs.append(p)
            if pw is not None:
                send_pw(p, pw)
            st = Stream()
            pump([(p.stdout, st, True)], on_pct)
            p.wait()
            return p.returncode, st.lines, st.prompted
        p1 = spawn(argvs[0], stdin=subprocess.PIPE if pw is not None else subprocess.DEVNULL,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=cwd)
        procs.append(p1)
        p2 = spawn(argvs[1], stdin=p1.stdout, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=cwd)
        procs.append(p2)
        p1.stdout.close()
        if pw is not None:
            send_pw(p1, pw)
        s1, s2 = Stream(), Stream()
        pump([(p1.stderr, s1, True), (p2.stdout, s2, False)], on_pct)
        p1.wait(); p2.wait()
        rc = p2.returncode if p1.returncode in (0, 1) else max(p1.returncode, p2.returncode)
        return rc, s1.lines + s2.lines, s1.prompted or s2.prompted
    finally:
        for p in procs:
            reap(p)

def analyze(rc, lines, prompted, had_pw):
    """Turn a 7z result into (warning_count) or raise ArcError."""
    text = "\n".join(lines)
    if "Wrong password" in text or "Cannot open encrypted archive" in text:
        raise ArcError("Wrong password" if had_pw else "Password required", "wrongpw" if had_pw else "needpw")
    if prompted and not had_pw:
        raise ArcError("Password required", "needpw")
    errs = [l for l in lines if l.startswith("ERROR")]
    if rc in (0, 1):
        return len([l for l in errs if "Dangerous link" in l])
    if rc == 2 and errs and all("Dangerous link path was ignored" in l for l in errs):
        return len(errs)
    if any("Dangerous link" in l for l in errs):
        raise ArcError("refused, the archive contains an unsafe symbolic link", "unsafe")
    msg = errs[0] if errs else (lines[-1] if lines else "7z failed (code %d)" % rc)
    msg = re.sub(r"^ERROR:\s*", "", msg)
    if "Can not open the file as" in msg or "Is not archive" in msg or "Cannot open the file as" in msg:
        msg = "Not a valid or supported archive"
    raise ArcError(msg, "failed")

# ---------------------------------------------------------------- names
ARC_EXTS = sorted(["tar.gz", "tar.bz2", "tar.xz", "tar.zst", "tar.lzma", "tar.z", "tgz", "tbz2", "tbz", "txz", "tzst",
                   "taz", "tar", "zip", "7z", "rar", "gz", "bz2", "xz", "zst", "lzma", "z", "iso", "cab", "jar", "apk",
                   "deb", "rpm", "war", "ear", "whl", "cpio", "lzh", "lha"], key=len, reverse=True)

def arc_split(name):
    low = name.lower()
    for e in ARC_EXTS:
        if low.endswith("." + e) and len(name) > len(e) + 1:
            return name[:-(len(e) + 1)], name[-(len(e) + 1):]
    return os.path.splitext(name)

def arc_stem(name):
    return arc_split(name)[0] or name

def unique_path(d, name):
    """d/name, or d/'stem (1).ext' (then (2), ...) when taken."""
    p = os.path.join(d, name)
    if not os.path.lexists(p):
        return p
    stem, ext = arc_split(name)
    k = 1
    while True:
        c = os.path.join(d, "%s (%d)%s" % (stem, k, ext))
        if not os.path.lexists(c):
            return c
        k += 1

def norm_ip(p):
    p = p.replace("\\", "/") if "\\" in p and "/" not in p else p
    while p.startswith("./"):
        p = p[2:]
    return p.strip("/") if p not in ("/",) else p

def unsafe_path(p):
    """zip-slip: '..' component, absolute path, or a drive letter."""
    if p.startswith("/") or p.startswith("\\") or re.match(r"^[A-Za-z]:", p):
        return True
    return any(c == ".." for c in re.split(r"[/\\]", p))

# ---------------------------------------------------------------- listing
COMPRESSORS = {"gzip", "bzip2", "xz", "zstd", "lzma", "Z", "lzma86"}

def parse_time(s):
    s = (s or "").strip()
    if not s:
        return 0
    try:
        return time.mktime(time.strptime(s[:19], "%Y-%m-%d %H:%M:%S"))
    except Exception:
        return 0

def read_listing(proc_out, cap):
    """Parse `7z l -slt` text.  Returns (type, entries, truncated, tail_lines, prompted)."""
    typ = ""
    entries = []
    cur = {}
    in_entries = False
    truncated = False
    tail = []
    prompted = False
    def flush():
        nonlocal cur
        if "Path" in cur:
            entries.append(cur)
        cur = {}
    for line in proc_out:
        line = line.rstrip("\n")
        if "Enter password" in line:
            prompted = True
        if line.startswith("----------"):
            in_entries = True
            continue
        if not in_entries:
            if line.startswith("Type = ") and not typ:
                typ = line[7:].strip()
            elif line.strip() and " = " not in line:
                tail.append(line.strip())
            continue
        if line == "":
            flush()
            continue
        k, sep, v = line.partition(" = ")
        if not sep:
            if line.endswith(" =") and line[:-2] in ("Comment", "Created", "Accessed", "CRC", "Symbolic Link", "Hard Link", "Path"):
                k, v = line[:-2], ""
            else:
                tail.append(line.strip())
                continue
        if k == "Path":
            if "Path" in cur:
                flush()
            if len(entries) >= cap:
                truncated = True
                break
        cur[k] = v
    if not truncated:
        flush()
    return typ, entries, truncated, tail, prompted

def sniff_tar(path, pw):
    """Is this single-stream compressed file (gz/xz/zst/...) a tar inside?  Decode only the first block."""
    p = spawn(["x", "-so", "-bso0", "-bse0", "-bsp0", path],
              stdin=subprocess.PIPE if pw is not None else subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        if pw is not None:
            send_pw(p, pw)
        head = p.stdout.read(512)
        return len(head) == 512 and head[257:262] == b"ustar"
    finally:
        reap(p)

def list_archive(path, pw=None, cap=LISTCAP):
    """List an archive.  Returns dict(type, entries[], truncated, compound, enc, unsafe[], names{norm: raw}).
    Raises ArcError (code needpw / wrongpw / failed)."""
    base_args = ["l", "-slt", "-bso1", "-bse1", "-bsp0"]
    pw_mode = subprocess.PIPE if pw is not None else subprocess.DEVNULL
    p = spawn(base_args + [path], stdin=pw_mode)
    try:
        if pw is not None:
            send_pw(p, pw)
        out = (l.decode("utf-8", "replace") for l in p.stdout)
        typ, ents, trunc, tail, prompted = read_listing(out, cap or 10 ** 9)
        if trunc:
            p.kill()
        p.wait()
        rc = p.returncode
    finally:
        reap(p)
    if not ents and (rc not in (0, 1) or prompted):
        analyze(rc if rc not in (0, 1) else 2, tail, prompted, pw is not None)
    compound = False
    if typ in COMPRESSORS and len(ents) <= 1:
        if sniff_tar(path, pw):
            compound = True
    if compound:
        p1 = spawn(["x", "-so", "-bso0", "-bse0", "-bsp0", path],
                   stdin=subprocess.PIPE if pw is not None else subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        p2 = None
        try:
            if pw is not None:
                send_pw(p1, pw)
            p2 = spawn(["l", "-slt", "-ttar", "-si", "-bso1", "-bse1", "-bsp0"], stdin=p1.stdout)
            p1.stdout.close()
            out = (l.decode("utf-8", "replace") for l in p2.stdout)
            typ, ents, trunc, tail, prompted = read_listing(out, cap or 10 ** 9)
        finally:
            if p2:
                reap(p2)
            reap(p1)
        typ = "tar (compressed)"
    elif typ in COMPRESSORS:
        # single compressed file: some formats (xz, zst) store no name
        for e in ents:
            if not e.get("Path"):
                e["Path"] = arc_stem(os.path.basename(path))
        if not ents:
            ents = [{"Path": arc_stem(os.path.basename(path)), "Folder": "-", "Size": "0"}]
    res = {"type": typ or "archive", "entries": [], "truncated": trunc, "compound": compound, "enc": False,
           "unsafe": [], "names": {}}
    for e in ents:
        raw = e.get("Path", "")
        ip = norm_ip(raw)
        if ip in ("", ".", "/"):
            continue
        if unsafe_path(raw) or unsafe_path(ip):
            res["unsafe"].append(raw)
            continue
        attrs = (e.get("Attributes", "") + " " + e.get("Mode", ""))
        link = bool(re.search(r"(^|\s)l[rwxsStT-]{9}", attrs)) or bool(e.get("Symbolic Link")) or bool(e.get("Hard Link"))
        isd = e.get("Folder") == "+"
        enc = e.get("Encrypted") == "+"
        res["enc"] = res["enc"] or enc
        try:
            size = int(e.get("Size") or 0)
        except ValueError:
            size = 0
        res["entries"].append({"ip": ip, "d": isd, "s": size, "m": parse_time(e.get("Modified")), "enc": enc, "l": link})
        res["names"][ip] = raw
    return res

def build_index(path, L):
    """Group a flat listing into {dir_ip: [entry,...]} for the archive view (synthesises implied folders)."""
    dirs = {"": {}}
    def ent(ip, d, s, m, enc, link):
        n = ip.rsplit("/", 1)[-1]
        return {"n": n, "ip": ip, "p": "arc:" + path + SEP + ip, "k": _natkey(n), "s": -1 if d else s, "m": m, "d": d,
                "l": link, "t": "inode/directory" if d else _mime(n), "h": n.startswith("."), "x": False, "enc": enc, "ar": True}
    def ensure(ip):
        if ip in dirs:
            return
        dirs[ip] = {}
        par = ip.rsplit("/", 1)[0] if "/" in ip else ""
        ensure(par)
        dirs[par].setdefault(ip.rsplit("/", 1)[-1], ent(ip, True, 0, 0, False, False))
    for e in L["entries"]:
        ip = e["ip"]
        par = ip.rsplit("/", 1)[0] if "/" in ip else ""
        ensure(par)
        n = ip.rsplit("/", 1)[-1]
        if e["d"]:
            ensure(ip)
            dirs[par][n] = ent(ip, True, 0, e["m"], False, False)
        else:
            dirs[par][n] = ent(ip, False, e["s"], e["m"], e["enc"], e["l"])
    return {k: list(v.values()) for k, v in dirs.items()}

def cmd_arc_ls(path, use_pw):
    pw = None
    if use_pw:
        pw = sys.stdin.readline().rstrip("\n")
    install_cancel_handler()
    try:
        L = list_archive(path, pw, LISTCAP)
    except ArcError as ex:
        return {"ok": False, "err": str(ex), "needpw": ex.code == "needpw", "wrongpw": ex.code == "wrongpw"}
    except OSError as ex:
        return {"ok": False, "err": ex.strerror or str(ex)}
    idx = build_index(path, L)
    return {"ok": True, "err": "", "dirs": idx, "count": len(L["entries"]), "size": sum(e["s"] for e in L["entries"] if not e["d"]),
            "truncated": L["truncated"], "cap": LISTCAP, "enc": L["enc"], "unsafe": len(L["unsafe"]), "type": L["type"],
            "compound": L["compound"]}

# ---------------------------------------------------------------- extract
def mtp_root():
    rd = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
    return os.path.join(rd, "ultimit-mtp")

def on_mtp(p):
    r = mtp_root()
    return os.path.abspath(p).startswith(r + os.sep)

def cache_dir():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    d = os.path.join(base, "ultimit-data")
    os.makedirs(d, mode=0o700, exist_ok=True)
    return d

def runtime_dir():
    rd = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
    d = os.path.join(rd, "ultimit-data")
    os.makedirs(d, mode=0o700, exist_ok=True)
    return d

def remove_any(p):
    if os.path.isdir(p) and not os.path.islink(p):
        shutil.rmtree(p, onerror=lambda f, pp, e: _force_rm(f, pp))
    else:
        os.unlink(p)

def _force_rm(func, path):
    try:
        os.chmod(os.path.dirname(path), 0o700)
        os.chmod(path, 0o700)
        func(path)
    except OSError:
        pass

def clean_stale(d):
    """Staging dirs left behind by a killed helper (older than a day)."""
    try:
        for n in os.listdir(d):
            if n.startswith(".ultimit-extract-") or n.startswith(".ultimit-part-"):
                p = os.path.join(d, n)
                if time.time() - os.lstat(p).st_mtime > 86400:
                    remove_any(p)
    except OSError:
        pass

def sanitize_tree(stage):
    """Make the staged tree safe: drop symlinks that leave it, strip setuid/setgid, keep dirs traversable."""
    root = os.path.realpath(stage)
    dropped = 0
    for cur, dirs, files in os.walk(stage, topdown=True, followlinks=False):
        try:
            os.chmod(cur, os.lstat(cur).st_mode | 0o700)
        except OSError:
            pass
        for n in list(dirs) + files:
            p = os.path.join(cur, n)
            try:
                st = os.lstat(p)
            except OSError:
                continue
            if stat.S_ISLNK(st.st_mode):
                t = os.readlink(p)
                tgt = os.path.realpath(os.path.join(cur, t))     # absolute targets override the join
                if os.path.isabs(t) or not (tgt == root or tgt.startswith(root + os.sep)):
                    os.unlink(p)
                    dropped += 1
                    if n in dirs:
                        dirs.remove(n)
            elif stat.S_ISREG(st.st_mode):
                if st.st_mode & 0o6000:
                    os.chmod(p, st.st_mode & ~0o6000)
            elif not stat.S_ISDIR(st.st_mode):
                os.unlink(p)             # devices / fifos / sockets never belong in a user extraction
                dropped += 1
    return dropped

def umask_mode():
    m = os.umask(0)
    os.umask(m)
    return 0o777 & ~m

def move_any(job, s, d):
    try:
        os.rename(s, d)
    except OSError:
        job.copyany(s, d)
        remove_any(s)

def emit_frac(job, frac, label):
    now = time.time()
    if now - job.last > 0.1 or frac >= 1:
        job.last = now
        print(json.dumps({"p": job.idx, "n": len(job.items), "name": label, "bytes": int(frac * 1000), "total": 1000},
                         ensure_ascii=False), flush=True)

def do_extract(job, it):
    src = it["src"]
    mode = it.get("mode", "here")
    pw = it.get("pw") or None
    name = os.path.basename(src)
    sel = [norm_ip(s) for s in it.get("sel", [])]
    emit_frac(job, 0, "Reading " + name)
    L = list_archive(src, pw, None)
    if L["unsafe"]:
        raise ArcError("refused, unsafe path in archive: “%s” (path traversal)" % L["unsafe"][0], "unsafe")
    if L["enc"] and pw is None:
        raise ArcError("Password required", "needpw")
    if not L["entries"]:
        raise ArcError("the archive is empty", "failed")
    names = []
    for s in sel:
        if s not in L["names"] and not any(e["ip"].startswith(s + "/") for e in L["entries"]):
            raise ArcError("“%s” is not in the archive" % s, "failed")
        names.append(L["names"].get(s, s))
    # where the staging dir lives: beside the destination (atomic rename) unless that is a phone
    if mode in ("here", "folder"):
        dest = it["dst"]
    elif mode == "into":
        dest = os.path.dirname(it["into"].rstrip("/")) or "/"
    elif mode == "selected":
        dest = it["into"]
    else:  # open
        h = hashlib.sha1(("%s|%s|%s" % (os.path.realpath(src), os.stat(src).st_mtime_ns, os.stat(src).st_size)).encode()).hexdigest()[:12]
        dest = os.path.join(runtime_dir(), "arc-" + h)
        for n in os.listdir(runtime_dir()):          # old opened-file caches
            q = os.path.join(runtime_dir(), n)
            if n.startswith("arc-") and q != dest and time.time() - os.lstat(q).st_mtime > 86400:
                remove_any(q)
    os.makedirs(dest, exist_ok=True)
    if not os.access(dest, os.W_OK):
        raise ArcError("cannot write to %s" % (os.path.basename(dest.rstrip("/")) or "/"), "failed")
    stage_parent = cache_dir() if on_mtp(dest) else dest
    clean_stale(stage_parent)
    stage = tempfile.mkdtemp(prefix=".ultimit-extract-", dir=stage_parent)
    moved = False
    try:
        common = ["-spd", "-aoa", "-bsp1", "-bso1", "-bse1"]
        if L["compound"]:
            a1 = ["x", "-so", "-bsp2", "-bso0", "-bse1", src]
            a2 = ["x", "-si", "-ttar", "-spd", "-aoa", "-bsp0", "-bso0", "-bse1", "-o" + stage] + (["--"] + names if names else [])
            argvs = [a1, a2]
        else:
            argvs = [["x"] + common + ["-o" + stage, src] + (["--"] + names if names else [])]
        warns = analyze(*(run_pipeline(argvs, pw, lambda p: emit_frac(job, p / 100.0 * (0.9 if on_mtp(dest) else 0.97), name + " · %d%%" % p)) + (pw is not None,)))
        warns += sanitize_tree(stage)
        top = sorted(os.listdir(stage))
        if not top:
            raise ArcError("nothing was extracted", "failed")
        results = []
        cross = on_mtp(dest)
        if cross:
            job.total_bytes = 0
            job.done_bytes = 0
            for r, ds, fs in os.walk(stage):
                for f in fs:
                    try: job.total_bytes += os.lstat(os.path.join(r, f)).st_size
                    except OSError: pass
        if mode in ("here", "folder"):
            if mode == "here" and len(top) == 1:
                final = unique_path(dest, top[0])
                move_any(job, os.path.join(stage, top[0]), final)
                results.append(final)
            else:
                final = unique_path(dest, arc_stem(name))
                try:
                    os.rename(stage, final)
                    moved = True
                    try: os.chmod(final, umask_mode())
                    except OSError: pass
                except OSError:
                    os.mkdir(final)
                    for t in top:
                        move_any(job, os.path.join(stage, t), os.path.join(final, t))
                results.append(final)
        elif mode == "into":
            into = it["into"].rstrip("/") or "/"
            if os.path.isdir(into):
                for t in top:
                    final = unique_path(into, t)
                    move_any(job, os.path.join(stage, t), final)
                    results.append(final)
            elif os.path.lexists(into):
                raise ArcError("“%s” exists and is not a folder" % os.path.basename(into), "failed")
            else:
                try:
                    os.rename(stage, into)
                    moved = True
                    try: os.chmod(into, umask_mode())
                    except OSError: pass
                except OSError:
                    os.mkdir(into)
                    for t in top:
                        move_any(job, os.path.join(stage, t), os.path.join(into, t))
                results.append(into)
        elif mode == "selected":
            for s in sel:
                p = os.path.join(stage, s)
                if os.path.lexists(p):
                    final = unique_path(dest, os.path.basename(s))
                    move_any(job, p, final)
                    results.append(final)
        else:  # open: a single file, placed with its inner path under the cache dir
            s = sel[0]
            p = os.path.join(stage, s)
            if not os.path.isfile(p):
                raise ArcError("“%s” is not a file" % s, "failed")
            final = os.path.join(dest, s)
            os.makedirs(os.path.dirname(final), exist_ok=True)
            if os.path.lexists(final):
                remove_any(final)
            os.rename(p, final)
            os.chmod(final, 0o600)
            results.append(final)
        emit_frac(job, 1, name)
        job.results.extend(results)
        if warns:
            job.warns.append("%s: %d unsafe link%s skipped" % (name, warns, "" if warns == 1 else "s"))
    finally:
        if not moved:
            remove_any(stage) if os.path.lexists(stage) else None

# ---------------------------------------------------------------- compress
class Counting:
    def __init__(self, f, job, total, base_label):
        self.f, self.job, self.total, self.label = f, job, max(1, total), base_label
    def read(self, n=-1):
        b = self.f.read(n)
        self.job.done_bytes += len(b)
        emit_frac(self.job, min(0.98, self.job.done_bytes / self.total), self.label)
        return b

def tar_add(tf, job, total, path, arcname, label):
    ti = tf.gettarinfo(path, arcname)
    if ti is None:
        return
    if ti.isreg():
        with open(path, "rb") as f:
            tf.addfile(ti, Counting(f, job, total, label))
    else:
        tf.addfile(ti)
    if ti.isdir():
        for n in sorted(os.listdir(path)):
            tar_add(tf, job, total, os.path.join(path, n), arcname + "/" + n, label)

def do_compress(job, it):
    srcs = [s.rstrip("/") or "/" for s in it["srcs"]]
    fmt = it.get("fmt", "zip")
    pw = it.get("pw") or None
    if fmt not in ("zip", "7z", "tar.gz"):
        raise ArcError("unknown format “%s”" % fmt, "failed")
    if pw and fmt == "tar.gz":
        raise ArcError("tar.gz archives cannot be password protected", "failed")
    req = it["dst"]
    outdir = os.path.dirname(req)
    parents = {os.path.dirname(s) for s in srcs}
    if len(parents) != 1:
        raise ArcError("items must be in one folder", "failed")
    cwd = parents.pop()
    names = [os.path.basename(s) for s in srcs]
    final = unique_path(outdir, os.path.basename(req))
    label = os.path.basename(final)
    if not os.access(outdir, os.W_OK):
        raise ArcError("cannot write to %s" % (os.path.basename(outdir) or "/"), "failed")
    for s in srcs:
        if os.path.realpath(final) == os.path.realpath(s):
            raise ArcError("cannot compress an archive into itself", "failed")
    tmp_parent = cache_dir() if on_mtp(outdir) else outdir
    clean_stale(tmp_parent)
    ext = "." + fmt
    tmp = os.path.join(tmp_parent, ".ultimit-part-%s%s" % (os.urandom(4).hex(), ext))
    emit_frac(job, 0, label)
    warns = 0
    try:
        if fmt == "tar.gz":
            total = 0
            for s in srcs:
                for r, ds, fs in os.walk(s, followlinks=False):
                    for f in fs:
                        try: total += os.lstat(os.path.join(r, f)).st_size
                        except OSError: pass
            job.done_bytes = 0
            # gzip header gets the real archive name, not our hidden temp name
            inner = label[:-3] if label.endswith(".gz") else label
            with open(tmp, "wb") as raw, gzip.GzipFile(filename=inner, fileobj=raw, mode="wb", compresslevel=6) as gz, \
                    tarfile.open(fileobj=gz, mode="w") as tf:
                for s, n in zip(srcs, names):
                    tar_add(tf, job, total, s, n, label)
        else:
            args = ["a", "-t" + fmt, "-snl", "-spd", "-bsp1", "-bso1", "-bse1", "-mx5"]
            if pw:
                args += ["-mem=AES256", "-p"] if fmt == "zip" else ["-mhe=on", "-p"]
            args += [tmp, "--"] + ["./" + n for n in names]
            rc, lines, prompted = run_pipeline([args], pw, lambda p: emit_frac(job, p / 100.0 * 0.98, label + " · %d%%" % p), cwd=cwd)
            warns = analyze(rc, lines, prompted, pw is not None)
            if rc == 1:
                warns = max(warns, 1)
        if on_mtp(outdir):
            job.total_bytes = os.path.getsize(tmp)
            job.done_bytes = 0
            job.copyany(tmp, final)
            os.unlink(tmp)
        else:
            os.rename(tmp, final)
        emit_frac(job, 1, label)
        job.results.append(final)
        if warns and fmt != "tar.gz":
            job.warns.append("%s: some files could not be read" % label)
    finally:
        if os.path.lexists(tmp):
            try: os.unlink(tmp)
            except OSError: pass
