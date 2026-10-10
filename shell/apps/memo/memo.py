#!/usr/bin/env python3
"""memo.py - file helper for MEMO, the Ultimit text editor (stdlib only, JSON on stdout).

  memo.py read PATH     -> {ok, text, eol, bom, stamp, size} | {ok:false, err}
  memo.py write         reads ONE JSON line from stdin {path, text, eol, bom}; atomic save
                        (temp file in the same dir + fsync + rename, original mode kept)
  memo.py stat PATH     -> {ok, stamp, size} | {ok:false, err:"missing"}
  memo.py draft-write | draft-rm ID | drafts | draft-read ID   crash-recovery drafts in
                        $XDG_STATE_HOME/ultimit/memo-drafts (default ~/.local/state/...), files mode 600
  memo.py list DIR      -> {ok, dir, entries:[{n, d, s}]}  (dirs first, hidden last)
Text handed to/from QML always uses "\\n"; eol ("lf"/"crlf") and bom are restored on write.
"""
import json
import os
import stat as st
import sys
import tempfile

MAX = 20 * 1024 * 1024


def out(o):
    sys.stdout.write(json.dumps(o))
    sys.stdout.flush()


def stamp(s):
    return "%d:%d" % (s.st_mtime_ns, s.st_size)


def do_read(path):
    try:
        s = os.stat(path)
        if st.S_ISDIR(s.st_mode):
            return {"ok": False, "err": "is a directory"}
        if not st.S_ISREG(s.st_mode):
            return {"ok": False, "err": "not a regular file"}
        if s.st_size > MAX:
            return {"ok": False, "err": "file is too large (%.1f MB, limit 20 MB)" % (s.st_size / 1048576.0)}
        with open(path, "rb") as f:
            data = f.read(MAX + 1)
    except FileNotFoundError:
        return {"ok": False, "err": "no such file", "missing": True}
    except OSError as e:
        return {"ok": False, "err": e.strerror or str(e)}
    if len(data) > MAX:
        return {"ok": False, "err": "file is too large (limit 20 MB)"}
    if b"\0" in data[:65536] or b"\0" in data:
        return {"ok": False, "err": "binary file (contains NUL bytes)"}
    bom = data.startswith(b"\xef\xbb\xbf")
    if bom:
        data = data[3:]
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return {"ok": False, "err": "not valid UTF-8 text"}
    eol = "lf"
    if "\r\n" in text:
        eol = "crlf"
        text = text.replace("\r\n", "\n")
    return {"ok": True, "text": text, "eol": eol, "bom": bom, "stamp": stamp(s), "size": s.st_size}


def do_write():
    try:
        req = json.loads(sys.stdin.readline())
        path = req["path"]
        text = req["text"]
    except Exception as e:
        return {"ok": False, "err": "bad request: %s" % e}
    if req.get("eol") == "crlf":
        text = text.replace("\n", "\r\n")
    data = text.encode("utf-8")
    if req.get("bom"):
        data = b"\xef\xbb\xbf" + data
    if len(data) > MAX:
        return {"ok": False, "err": "document too large (limit 20 MB)"}
    real = os.path.realpath(path)
    d = os.path.dirname(real) or "."
    tmp = None
    try:
        try:
            old = os.stat(real)
        except FileNotFoundError:
            old = None
        if old is not None and not st.S_ISREG(old.st_mode):
            return {"ok": False, "err": "not a regular file"}
        fd, tmp = tempfile.mkstemp(prefix=".memo-", suffix=".tmp", dir=d)
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        if old is not None:
            os.chmod(tmp, st.S_IMODE(old.st_mode))
            try:
                os.chown(tmp, old.st_uid, old.st_gid)
            except OSError:
                pass
        else:
            um = os.umask(0)
            os.umask(um)
            os.chmod(tmp, 0o666 & ~um)
        os.replace(tmp, real)
        tmp = None
        s = os.stat(real)
        return {"ok": True, "stamp": stamp(s), "size": s.st_size}
    except OSError as e:
        return {"ok": False, "err": e.strerror or str(e)}
    finally:
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass


def do_stat(path):
    try:
        s = os.stat(path)
        return {"ok": True, "stamp": stamp(s), "size": s.st_size}
    except FileNotFoundError:
        return {"ok": False, "err": "missing"}
    except OSError as e:
        return {"ok": False, "err": e.strerror or str(e)}


def do_list(d):
    d = os.path.abspath(os.path.expanduser(d))
    try:
        names = os.listdir(d)
    except OSError as e:
        return {"ok": False, "dir": d, "err": e.strerror or str(e), "entries": []}
    ents = []
    for n in names:
        p = os.path.join(d, n)
        try:
            s = os.stat(p)
            isdir = st.S_ISDIR(s.st_mode)
            size = s.st_size
        except OSError:
            isdir, size = False, 0
        ents.append({"n": n, "d": isdir, "s": size})
    ents.sort(key=lambda e: (not e["d"], e["n"].startswith("."), e["n"].lower()))
    return {"ok": True, "dir": d, "entries": ents}


def draft_dir():
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(base, "ultimit", "memo-drafts")


def safe_id(i):
    return bool(i) and all(c.isalnum() or c in "-_" for c in i)


def write_private(path, data):
    fd, tmp = tempfile.mkstemp(prefix=".tmp-", dir=os.path.dirname(path))
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def do_draft_write():
    try:
        req = json.loads(sys.stdin.readline())
        i = req["id"]
        if not safe_id(i):
            return {"ok": False, "err": "bad id"}
        d = draft_dir()
        os.makedirs(d, mode=0o700, exist_ok=True)
        write_private(os.path.join(d, i + ".txt"), req["text"].encode("utf-8"))
        meta = {"id": i, "path": req.get("path", ""), "eol": req.get("eol", "lf"), "bom": bool(req.get("bom"))}
        write_private(os.path.join(d, i + ".json"), json.dumps(meta).encode())
        return {"ok": True}
    except Exception as e:
        return {"ok": False, "err": str(e)}


def do_draft_rm(i):
    if not safe_id(i):
        return {"ok": False, "err": "bad id"}
    for ext in (".txt", ".json"):
        try:
            os.unlink(os.path.join(draft_dir(), i + ext))
        except OSError:
            pass
    return {"ok": True}


def do_drafts():
    d = draft_dir()
    res = []
    try:
        names = sorted(os.listdir(d))
    except OSError:
        return {"ok": True, "drafts": []}
    for n in names:
        if not n.endswith(".json"):
            continue
        try:
            with open(os.path.join(d, n)) as f:
                m = json.load(f)
            if safe_id(m["id"]) and os.path.exists(os.path.join(d, m["id"] + ".txt")):
                res.append(m)
        except (OSError, ValueError, KeyError):
            pass
    return {"ok": True, "drafts": res}


def do_draft_read(i):
    if not safe_id(i):
        return {"ok": False, "err": "bad id"}
    try:
        with open(os.path.join(draft_dir(), i + ".txt"), "rb") as f:
            return {"ok": True, "text": f.read().decode("utf-8")}
    except (OSError, UnicodeDecodeError) as e:
        return {"ok": False, "err": str(e)}


def main():
    a = sys.argv[1:]
    if not a:
        out({"ok": False, "err": "usage"})
    elif a[0] == "read" and len(a) > 1:
        out(do_read(a[1]))
    elif a[0] == "write":
        out(do_write())
    elif a[0] == "stat" and len(a) > 1:
        out(do_stat(a[1]))
    elif a[0] == "draft-write":
        out(do_draft_write())
    elif a[0] == "draft-rm" and len(a) > 1:
        out(do_draft_rm(a[1]))
    elif a[0] == "drafts":
        out(do_drafts())
    elif a[0] == "draft-read" and len(a) > 1:
        out(do_draft_read(a[1]))
    elif a[0] == "list" and len(a) > 1:
        out(do_list(a[1]))
    else:
        out({"ok": False, "err": "usage"})


main()
