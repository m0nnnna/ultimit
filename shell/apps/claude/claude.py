#!/usr/bin/env python3
"""claude.py - helper for CLAUDE, the Ultimit Claude app (stdlib only). Talks to the official Claude
Code CLI (`claude`); never to the API directly, and never stores a credential itself.

Accounts: each account is its own Claude Code configuration directory (CLAUDE_CONFIG_DIR), so every
account keeps its own login, settings and session history. The account with dir "" is the user's
normal Claude Code setup (~/.claude). Logins live where Claude Code puts them (<dir>/.credentials.json,
mode 0600); this helper only runs `claude auth login|logout|status` in the account's directory.
Every ANTHROPIC_* / CLAUDE_* variable in the environment (ANTHROPIC_API_KEY, CLAUDE_CODE_OAUTH_TOKEN, ...)
is dropped for every run, so an account always means its own login and its own settings.

Projects: a name, a folder Claude works in, the account, a model, a permission mode and notes
(handed to Claude on every chat in it). "system" is built in: troubleshooting this PC, from $HOME,
with the Ultimit system summary attached to new chats.

Chats: <data>/chats/<project>/<chat>.json (title, account, Claude Code session id, times) and
<chat>.jsonl (what the window shows). A chat resumes its Claude Code session with the account it
started with. Claude only ever sees its own chat: nothing reads the other chats' histories. A chat can
move to another project (chat-move); its Claude Code session is copied to where the new project's
folder keeps it, since Claude Code files sessions by working directory.

  claude.py state                        JSON {ok, cli, accounts[], projects[], dataDir}
  claude.py cli                          JSON {ok, path, version}
  claude.py install                      JSON lines {ev: line|done}: Anthropic's installer, for this user
  claude.py account-add <name>           JSON {ok, account}      (a new, empty configuration dir)
  claude.py account-default              JSON {ok, account}      (adds "My Claude Code" = ~/.claude)
  claude.py account-rename <id> <name>   JSON {ok}
  claude.py account-remove <id> [purge]  JSON {ok}               (purge: also delete its directory)
  claude.py auth-status <id>             JSON {ok, loggedIn, method, email, org, raw}
  claude.py login <id> [console]         JSON lines {ev: url|code|line|done}; a line on stdin is the
                                         code the browser shows (when it cannot hand it back itself)
  claude.py logout <id>                  JSON {ok, err}
  claude.py project-save                 stdin: project JSON (no id: new)  -> JSON {ok, project}
  claude.py project-remove <id>          JSON {ok}               (its chats go too)
  claude.py chats <project>              JSON {ok, chats[]}      newest first
  claude.py chat <project> <chat>        JSON {ok, meta, items[]}
  claude.py chat-rename <project> <chat> <title>   JSON {ok}
  claude.py chat-remove <project> <chat>           JSON {ok}
  claude.py chat-move <project> <chat> <to>        JSON {ok, meta}  the chat goes to project <to>
  claude.py chat-account <project> <chat> <account> JSON {ok, meta}  carry on the chat with another account
                                         (its Claude Code session is copied into that account's folder)
  claude.py usage                        JSON {ok, accounts{id: usage}}  each account's plan limits as last
                                         reported (see Usage)
  claude.py sysinfo                      JSON {ok, text}         the system summary (Markdown)
  claude.py dirs <folder>                JSON {ok, dir, parent, dirs[{n, h}]}  the folders in a folder
                                         (the project folder picker; ~ works)
  claude.py paste-image                  JSON {ok, path, w, h} the image on the clipboard (or an image
                                         file copied in DATA), saved for sending; {ok:false, none:true}
                                         when the clipboard holds no image
  claude.py add-image <file>             JSON {ok, path, w, h} the same for a file (dropped on the window)
  claude.py drop-image <path>            JSON {ok} forget an image that wasn't sent
  claude.py session <project> <chat|new> [account]
                                         JSON lines (see Session; account: a new chat's, instead of the
                                         project's); stdin: JSON commands
                                         {op:send,text,sysinfo,images[paths]} {op:permit,rid,allow,always}
                                         {op:interrupt} {op:close}

Images: pasted or dropped images are kept in <data>/images (PNG or JPEG, at most 1568 px on the long
side when Pillow is there: Claude scales anything bigger down to that anyway) and go to Claude Code as
image blocks with the message. A chat's items name the images it sent; removing the chat removes them.

Context: Claude Code compacts a chat by itself when its context fills (autoCompactEnabled, on unless
switched off). Every run drops DISABLE_AUTO_COMPACT / DISABLE_COMPACT from the environment and turns
autoCompactEnabled back on in the account's .claude.json if it was switched off, so a long chat never
stops at a full context; the chat shows a note when it happens. Chats compact at COMPACT_WINDOW tokens
(CLAUDE_CODE_AUTO_COMPACT_WINDOW), not at the edge of the model's window (1M): every turn sends the whole
context again, and those re-reads cost the same on Sonnet as on Opus, so a smaller context is the one
saving no model choice gives. An account's settings.json "env" can set its own window.

Scaling: a chat runs on the project's model, DEFAULT_MODEL (Sonnet) unless it picks one: nearly every turn
of the work is the chat's own, so that is where the model's price counts. Every chat gets three subagents
(--agents, SUBAGENTS): scout (Haiku, low effort, finds and reads), worker (Haiku, medium effort, bulk
mechanical work) and expert (Opus, high effort, the hard problems), and the system prompt tells Claude to
scale down to them for grunt work, so file dumps stay out of the chat and run on the cheapest model, and to
scale up to expert instead of looping on a hard problem. The chat itself runs at the project's effort
(--effort, DEFAULT_EFFORT unless the project picks one).

Usage: Claude Code reports the plan's limits with every turn (rate_limit_event); the last report per
account is kept in <data>/usage/<account>.json: {windows{five_hour|seven_day...: {used 0-1, resets}},
status, overage, t}. A chat's meta keeps its own totals: usage{cost, input, output, cacheRead, cacheWrite,
turns} and context{used, window} (the last turn's prompt + reply, of the model's context window).

Environment: ULTIMIT_CLAUDE_HOME (data dir, default $XDG_DATA_HOME/ultimit/claude),
ULTIMIT_CLAUDE_BIN (the claude binary), ULTIMIT_CLAUDE_FAKE_SYSINFO (text, for tests).
"""
import base64
import json
import os
import re
import secrets
import selectors
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.parse

HOME = os.path.expanduser("~")
DATA = os.environ.get("ULTIMIT_CLAUDE_HOME") or os.path.join(
    os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share"), "ultimit", "claude")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "ultimit")

# Nothing Claude Code reads from the environment comes from the desktop: credentials (ANTHROPIC_API_KEY,
# CLAUDE_CODE_OAUTH_TOKEN, ...), endpoints and options all belong to the account, in its own settings.json "env".
COMPACT_WINDOW = "120000"   # chats compact at this many tokens (a plain number: Claude Code reads "200k" as 100k)
DROP_PREFIXES = ("ANTHROPIC_", "CLAUDE_", "CLAUDECODE", "DISABLE_AUTO_COMPACT", "DISABLE_COMPACT")
PERM_MODES = ("default", "acceptEdits", "plan", "auto", "bypassPermissions")
EFFORTS = ("low", "medium", "high", "xhigh", "max")
DEFAULT_EFFORT = "medium"   # the chat's own effort; subagents set theirs in SUBAGENTS
DEFAULT_MODEL = "sonnet"    # the chat's own model when the project picks none; expert escalates to Opus
SYSTEM_ID = "system"


def out(o):
    sys.stdout.write(json.dumps(o, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def new_id():
    return time.strftime("%Y%m%d%H%M%S") + "-" + secrets.token_hex(3)


# ---------------------------------------------------------------------------------------- storage
def path(*p):
    return os.path.join(DATA, *p)


def load_json(p, default):
    try:
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save_json(p, o):
    os.makedirs(os.path.dirname(p), mode=0o700, exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(o, f, ensure_ascii=False, indent=1)
    os.replace(tmp, p)


def safe_id(s):
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,80}", s or "") or s.startswith("."):
        raise ValueError("bad id")
    return s


def accounts():
    return load_json(path("accounts.json"), {}).get("accounts", [])


def save_accounts(a):
    save_json(path("accounts.json"), {"accounts": a})


def account(aid):
    for a in accounts():
        if a["id"] == aid:
            return a
    return None


def usage_path(aid):
    return path("usage", safe_id(aid) + ".json")


def cmd_usage():
    return {"ok": True, "accounts": {a["id"]: load_json(usage_path(a["id"]), None) for a in accounts()
                                     if os.path.exists(usage_path(a["id"]))}}


def plan_usage(r):
    """rate_limit_info -> {windows, status, overage, t}: what the window shows as the account's limits."""
    wins = {}
    for k, w in (r.get("unifiedWindows") or {}).items():
        if isinstance(w, dict) and isinstance(w.get("utilization"), (int, float)):
            wins[k] = {"used": w["utilization"], "resets": w.get("resetsAt")}
    if not wins and isinstance(r.get("utilization"), (int, float)) and r.get("rateLimitType"):
        wins[r["rateLimitType"]] = {"used": r["utilization"], "resets": r.get("resetsAt")}
    return {"windows": wins, "status": r.get("status") or "", "overage": bool(r.get("isUsingOverage")),
            "t": time.time()}


def system_project():
    return {"id": SYSTEM_ID, "name": "This PC", "dir": HOME, "account": "", "model": "", "perm": "default",
            "effort": "", "notes": "", "builtin": True}


def projects():
    stored = load_json(path("projects.json"), {}).get("projects", [])
    sysp = system_project()
    rest = []
    for p in stored:
        if p.get("id") == SYSTEM_ID:   # the user's choices for the built-in one (account, model, notes)
            for k in ("account", "model", "perm", "effort", "notes"):
                if k in p:
                    sysp[k] = p[k]
        else:
            rest.append(p)
    return [sysp] + rest


def project(pid):
    for p in projects():
        if p["id"] == pid:
            return p
    return None


def save_projects(ps):
    save_json(path("projects.json"), {"projects": [{k: v for k, v in p.items() if k != "builtin"} for p in ps]})


# ---------------------------------------------------------------------------------------- the CLI
def find_claude():
    b = os.environ.get("ULTIMIT_CLAUDE_BIN")
    if b:
        return b if os.access(b, os.X_OK) else ""
    w = shutil.which("claude")
    if w:
        return w
    for c in (os.path.join(HOME, ".local", "bin", "claude"), os.path.join(HOME, ".claude", "local", "claude")):
        if os.access(c, os.X_OK):
            return c
    return ""


def account_env(a):
    env = {k: v for k, v in os.environ.items() if not k.startswith(DROP_PREFIXES)}
    if a and a.get("dir"):
        env["CLAUDE_CONFIG_DIR"] = a["dir"]
    local_bin = os.path.join(HOME, ".local", "bin")
    if local_bin not in env.get("PATH", "").split(":"):
        env["PATH"] = env.get("PATH", "/usr/bin:/bin") + ":" + local_bin
    return env


def account_dir(a):
    """The account's Claude Code configuration directory."""
    return (a or {}).get("dir") or os.path.join(HOME, ".claude")


def ensure_auto_compact(a):
    """Auto-compact back on if the account switched it off (Claude Code's /config)."""
    cfg = os.path.join(a["dir"], ".claude.json") if a and a.get("dir") else os.path.join(HOME, ".claude.json")
    c = load_json(cfg, None)
    if isinstance(c, dict) and c.get("autoCompactEnabled") is False:
        c["autoCompactEnabled"] = True
        tmp = cfg + ".ultimit-tmp"
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(c, f, indent=2)
            os.chmod(tmp, os.stat(cfg).st_mode & 0o777)
            os.replace(tmp, cfg)
        except OSError:
            pass


def cmd_cli():
    b = find_claude()
    if not b:
        return {"ok": True, "path": "", "version": ""}
    try:
        p = subprocess.run([b, "--version"], capture_output=True, text=True, timeout=20, env=account_env(None))
        v = p.stdout.strip().split(" ")[0] if p.returncode == 0 else ""
    except (OSError, subprocess.TimeoutExpired):
        v = ""
    return {"ok": True, "path": b, "version": v}


def cmd_state():
    return {"ok": True, "accounts": accounts(), "projects": projects(), "dataDir": DATA,
            "defaultUsed": any(a.get("dir", "") == "" for a in accounts())}


INSTALL_CMD = "curl -fsSL https://claude.ai/install.sh | bash"   # the official native installer, per user


def cmd_install():
    """Install Claude Code for this user with Anthropic's own installer (~/.local/bin/claude; it keeps
    itself up to date). JSON lines {ev: line|done}."""
    try:
        p = subprocess.Popen(["sh", "-c", INSTALL_CMD], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             stdin=subprocess.DEVNULL, env=account_env(None), cwd=HOME)
    except OSError as ex:
        out({"ev": "done", "ok": False, "err": str(ex)})
        return
    log = []
    for raw in p.stdout:
        line = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", raw.decode("utf-8", "replace")).rstrip()
        if line.strip():
            log.append(line)
            out({"ev": "line", "text": line})
    p.wait()
    cli = cmd_cli()
    ok = p.returncode == 0 and bool(cli["path"])
    out({"ev": "done", "ok": ok, "cli": cli, "err": "" if ok else "\n".join(log[-5:]) or "The installer failed"})


# ---------------------------------------------------------------------------------------- accounts
def slug(name):
    s = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")[:32]
    return s or "account"


def cmd_account_add(name):
    name = name.strip() or "Account"
    a = accounts()
    base = slug(name)
    aid, n = base, 2
    while any(x["id"] == aid for x in a) or os.path.exists(path("accounts", aid)):
        aid, n = "%s-%d" % (base, n), n + 1
    d = path("accounts", aid)
    os.makedirs(d, mode=0o700, exist_ok=True)
    os.chmod(d, 0o700)
    acc = {"id": aid, "name": name, "dir": d}
    save_accounts(a + [acc])
    return {"ok": True, "account": acc}


def cmd_account_default():
    a = accounts()
    for x in a:
        if x.get("dir", "") == "":
            return {"ok": True, "account": x}
    aid = "default"
    while any(x["id"] == aid for x in a):
        aid += "-1"
    acc = {"id": aid, "name": "My Claude Code", "dir": ""}
    save_accounts(a + [acc])
    return {"ok": True, "account": acc}


def cmd_account_rename(aid, name):
    a = accounts()
    for x in a:
        if x["id"] == aid:
            x["name"] = name.strip() or x["name"]
    save_accounts(a)
    return {"ok": True}


def cmd_account_remove(aid, purge=False):
    a = accounts()
    gone = [x for x in a if x["id"] == aid]
    save_accounts([x for x in a if x["id"] != aid])
    try:
        os.unlink(usage_path(aid))
    except (OSError, ValueError):
        pass
    # only ever delete a directory this app created (never ~/.claude)
    if purge and gone and gone[0].get("dir") and os.path.dirname(os.path.abspath(gone[0]["dir"])) == path("accounts"):
        shutil.rmtree(gone[0]["dir"], ignore_errors=True)
    return {"ok": True}


def cmd_auth_status(aid):
    a = account(aid)
    b = find_claude()
    if not a:
        return {"ok": False, "err": "No such account"}
    if not b:
        return {"ok": False, "err": "Claude Code is not installed"}
    try:
        p = subprocess.run([b, "auth", "status"], capture_output=True, text=True, timeout=30, env=account_env(a),
                           stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as ex:
        return {"ok": False, "err": str(ex)}
    try:
        raw = json.loads(p.stdout)
    except ValueError:
        raw = {}
    def find(o, words):          # the fields differ by login type; look for them anywhere
        if isinstance(o, dict):
            for k, v in o.items():
                if isinstance(v, str) and v and any(w in k.lower() for w in words):
                    return v
            for v in o.values():
                r = find(v, words)
                if r:
                    return r
        return ""
    email = find(raw, ("email",))
    org = find(raw, ("orgname", "organizationname", "organization_name"))
    return {"ok": True, "loggedIn": bool(raw.get("loggedIn")) and p.returncode == 0,
            "method": raw.get("authMethod", ""), "email": email or "", "org": org or "", "raw": raw}


URL_RE = re.compile(r"https://\S+")


def cmd_login(aid, console=False):
    """Run `claude auth login` for one account, relaying what it prints. The browser normally hands the
    login back by itself; when it shows a code instead, the window sends that code as a line on stdin."""
    a = account(aid)
    b = find_claude()
    if not a or not b:
        out({"ev": "done", "ok": False, "err": "No such account" if not a else "Claude Code is not installed"})
        return
    if a.get("dir"):
        os.makedirs(a["dir"], mode=0o700, exist_ok=True)
    args = [b, "auth", "login"] + (["--console"] if console else [])
    try:
        p = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             env=account_env(a), start_new_session=True)
    except OSError as ex:
        out({"ev": "done", "ok": False, "err": str(ex)})
        return
    signal.signal(signal.SIGTERM, lambda *_: (p.terminate(), sys.exit(1)))   # the window cancelled
    sel = selectors.DefaultSelector()
    sel.register(p.stdout, selectors.EVENT_READ, "child")
    try:
        sel.register(sys.stdin, selectors.EVENT_READ, "us")
    except (ValueError, OSError):
        pass
    buf, seen_url, asked, log = "", False, False, []
    while True:
        if p.poll() is not None and not sel.get_map().get(p.stdout.fileno()):
            break
        for key, _ in sel.select(timeout=0.5):
            if key.data == "child":
                chunk = os.read(p.stdout.fileno(), 4096)
                if not chunk:
                    sel.unregister(p.stdout)
                    continue
                buf += chunk.decode("utf-8", "replace")
                while "\n" in buf:
                    line, buf = buf.split("\n", 1)
                    line = line.rstrip("\r")
                    m = URL_RE.search(line)
                    if re.search(r"(?i)paste code", line):
                        line = re.sub(r"(?i).*paste code here if prompted\s*>?\s*", "", line)
                        if not asked:
                            asked = True
                            out({"ev": "code"})
                    if m and not seen_url:
                        seen_url = True
                        out({"ev": "url", "url": m.group(0)})
                    elif line.strip() and not m:
                        log.append(line)
                        out({"ev": "line", "text": line})
                if not asked and re.search(r"(?i)paste code", buf):
                    asked = True
                    out({"ev": "code"})
            else:
                line = sys.stdin.readline()
                if not line:           # the window went away; the login stays up until it is killed
                    sel.unregister(sys.stdin)
                    continue
                try:
                    p.stdin.write(line.strip().encode() + b"\n")
                    p.stdin.flush()
                except OSError:
                    pass
        if p.poll() is not None and not sel.get_map().get(p.stdout.fileno()):
            break
    p.wait()
    st = cmd_auth_status(aid)
    ok = p.returncode == 0 and st.get("loggedIn", False)
    out({"ev": "done", "ok": ok, "status": st,
         "err": "" if ok else ("\n".join(l for l in log[-6:] if l.strip()) or "Sign-in did not finish")})


def cmd_logout(aid):
    a = account(aid)
    b = find_claude()
    if not a or not b:
        return {"ok": False, "err": "No such account" if not a else "Claude Code is not installed"}
    p = subprocess.run([b, "auth", "logout"], capture_output=True, text=True, timeout=30, env=account_env(a),
                       stdin=subprocess.DEVNULL)
    return {"ok": p.returncode == 0, "err": (p.stderr or p.stdout).strip()[-400:]}


# ---------------------------------------------------------------------------------------- projects
def cmd_project_save(o):
    ps = projects()
    pid = o.get("id") or ""
    if o.get("effort") and o["effort"] not in EFFORTS:
        return {"ok": False, "err": "Unknown effort level"}
    if pid == SYSTEM_ID:
        p = ps[0]
        for k in ("account", "model", "perm", "effort", "notes"):
            if k in o:
                p[k] = o[k]
    else:
        d = os.path.abspath(os.path.expanduser(o.get("dir") or HOME))
        if not os.path.isdir(d):
            return {"ok": False, "err": "Not a folder: " + d}
        if o.get("perm", "default") not in PERM_MODES:
            return {"ok": False, "err": "Unknown permission mode"}
        p = {"id": pid, "name": (o.get("name") or os.path.basename(d) or "Project").strip(), "dir": d,
             "account": o.get("account", ""), "model": o.get("model", ""), "perm": o.get("perm", "default"),
             "effort": o.get("effort", ""), "notes": o.get("notes", "")}
        if pid and any(x["id"] == pid for x in ps):
            ps = [p if x["id"] == pid else x for x in ps]
        else:
            p["id"] = slug(p["name"])[:24] + "-" + secrets.token_hex(2)
            ps.append(p)
    save_projects(ps)
    return {"ok": True, "project": p}


def cmd_project_remove(pid):
    if pid == SYSTEM_ID:
        return {"ok": False, "err": "This PC is built in"}
    save_projects([p for p in projects() if p["id"] != pid])
    for f in os.listdir(path("chats", safe_id(pid))) if os.path.isdir(path("chats", safe_id(pid))) else []:
        if f.endswith(".jsonl"):
            for p in chat_images(pid, f[:-6]):
                cmd_drop_image(p)
    shutil.rmtree(path("chats", safe_id(pid)), ignore_errors=True)
    return {"ok": True}


# ---------------------------------------------------------------------------------------- chats
def chat_meta_path(pid, cid):
    return path("chats", safe_id(pid), safe_id(cid) + ".json")


def chat_items_path(pid, cid):
    return path("chats", safe_id(pid), safe_id(cid) + ".jsonl")


def cmd_chats(pid):
    d = path("chats", safe_id(pid))
    res = []
    try:
        names = os.listdir(d)
    except OSError:
        names = []
    for n in names:
        if n.endswith(".json"):
            m = load_json(os.path.join(d, n), None)
            if m:
                res.append(m)
    res.sort(key=lambda m: m.get("updated", 0), reverse=True)
    return {"ok": True, "chats": res}


def read_items(pid, cid):
    items, by_tool = [], {}
    try:
        with open(chat_items_path(pid, cid), encoding="utf-8") as f:
            for line in f:
                try:
                    it = json.loads(line)
                except ValueError:
                    continue
                if it.get("k") == "tool_result":     # merged into its tool row
                    t = by_tool.get(it.get("id"))
                    if t is not None:
                        t["status"] = "error" if it.get("error") else "ok"
                        t["out"] = it.get("out", "")
                    continue
                if it.get("k") == "tool":
                    by_tool[it.get("id")] = it
                items.append(it)
    except OSError:
        pass
    return items


def cmd_chat(pid, cid):
    m = load_json(chat_meta_path(pid, cid), None)
    if m is None:
        return {"ok": False, "err": "No such chat"}
    return {"ok": True, "meta": m, "items": read_items(pid, cid)}


def cmd_chat_rename(pid, cid, title):
    p = chat_meta_path(pid, cid)
    m = load_json(p, None)
    if m is None:
        return {"ok": False, "err": "No such chat"}
    m["title"] = title.strip() or m.get("title", "")
    save_json(p, m)
    return {"ok": True}


def chat_images(pid, cid):
    return [p for it in read_items(pid, cid) if it.get("k") == "user" for p in it.get("images") or []]


def session_files(a, sid):
    """The account's transcript of Claude Code session sid ([<dir>/projects/<cwd>/<sid>.jsonl] and the
    folder of the same name beside it, subagents' transcripts), as (path, relative path) pairs."""
    root = os.path.join(account_dir(a), "projects")
    found = []
    try:
        dirs = os.listdir(root)
    except OSError:
        return found
    for d in dirs:
        for name in (sid + ".jsonl", sid):
            p = os.path.join(root, d, name)
            if os.path.exists(p):
                found.append((p, os.path.join("projects", d, name)))
    return found


def cmd_chat_account(pid, cid, aid):
    m = load_json(chat_meta_path(pid, cid), None)
    if m is None:
        return {"ok": False, "err": "No such chat"}
    new, old = account(aid), account(m.get("account", ""))
    if not new:
        return {"ok": False, "err": "No such account"}
    sid = m.get("session") or ""
    if sid and old and old["id"] != new["id"]:
        if not re.fullmatch(r"[A-Za-z0-9-]{1,80}", sid):
            return {"ok": False, "err": "bad session id"}
        files = session_files(old, sid)
        if not files and not session_files(new, sid):
            return {"ok": False, "err": "Claude Code's record of this chat is gone, so it can't move to another account"}
        for src, rel in files:
            dst = os.path.join(account_dir(new), rel)
            os.makedirs(os.path.dirname(dst), mode=0o700, exist_ok=True)
            if os.path.isdir(src):
                shutil.copytree(src, dst, dirs_exist_ok=True)
            else:
                shutil.copy2(src, dst)
    m["account"] = new["id"]
    save_json(chat_meta_path(pid, cid), m)
    return {"ok": True, "meta": m}


def cwd_key(d):
    """The folder name Claude Code files a working directory's sessions under (/home/x -> -home-x)."""
    return "".join(c if c.isalnum() else "-" for c in d)


def cmd_chat_move(pid, cid, to):
    m = load_json(chat_meta_path(pid, cid), None)
    if m is None:
        return {"ok": False, "err": "No such chat"}
    src, dst = project(pid), project(to)
    if not dst:
        return {"ok": False, "err": "No such project"}
    if safe_id(to) == safe_id(pid):
        return {"ok": True, "meta": m}
    a, sid = account(m.get("account", "")), m.get("session") or ""
    if sid and a and src and src["dir"] != dst["dir"]:
        if not re.fullmatch(r"[A-Za-z0-9-]{1,80}", sid):
            return {"ok": False, "err": "bad session id"}
        root = os.path.join(account_dir(a), "projects")
        old, new = os.path.join(root, cwd_key(src["dir"])), os.path.join(root, cwd_key(dst["dir"]))
        if not os.path.exists(os.path.join(old, sid + ".jsonl")) and not os.path.exists(os.path.join(new, sid + ".jsonl")):
            return {"ok": False, "err": "Claude Code's record of this chat is gone, so it can't move to another project"}
        os.makedirs(new, mode=0o700, exist_ok=True)
        for name in (sid + ".jsonl", sid):
            p = os.path.join(old, name)
            if os.path.isdir(p):
                shutil.copytree(p, os.path.join(new, name), dirs_exist_ok=True)
            elif os.path.exists(p):
                shutil.copy2(p, os.path.join(new, name))
    m["project"] = to
    os.makedirs(path("chats", safe_id(to)), exist_ok=True)
    save_json(chat_meta_path(to, cid), m)
    os.unlink(chat_meta_path(pid, cid))
    if os.path.exists(chat_items_path(pid, cid)):
        os.replace(chat_items_path(pid, cid), chat_items_path(to, cid))
    return {"ok": True, "meta": m}


def cmd_chat_remove(pid, cid):
    for p in chat_images(pid, cid):
        cmd_drop_image(p)
    for p in (chat_meta_path(pid, cid), chat_items_path(pid, cid)):
        try:
            os.unlink(p)
        except OSError:
            pass
    return {"ok": True}


# ---------------------------------------------------------------------------------------- images
IMAGE_TYPES = {"image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/gif": "gif"}
IMAGE_EXT = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp", "gif": "image/gif"}
IMAGE_MAX_BYTES = 3750000          # the API takes 5 MB of base64 per image
IMAGE_MAX_SIDE = 1568


def image_dir():
    return path("images")


def image_size(data):
    """(w, h) of PNG, GIF, JPEG or WebP bytes, or (0, 0)."""
    if data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 24:
        return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return int.from_bytes(data[6:8], "little"), int.from_bytes(data[8:10], "little")
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        if data[12:16] == b"VP8X":
            return int.from_bytes(data[24:27], "little") + 1, int.from_bytes(data[27:30], "little") + 1
        if data[12:16] == b"VP8L":
            b = int.from_bytes(data[21:25], "little")
            return (b & 0x3FFF) + 1, ((b >> 14) & 0x3FFF) + 1
        if data[12:16] == b"VP8 ":
            return int.from_bytes(data[26:28], "little") & 0x3FFF, int.from_bytes(data[28:30], "little") & 0x3FFF
    if data[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            m = data[i + 1]
            if m in (0xC0, 0xC1, 0xC2):
                return int.from_bytes(data[i + 7:i + 9], "big"), int.from_bytes(data[i + 5:i + 7], "big")
            i += 2 + int.from_bytes(data[i + 2:i + 4], "big")
    return 0, 0


def shrink_image(data, ext):
    """Scale down to IMAGE_MAX_SIDE and keep it under IMAGE_MAX_BYTES, with Pillow if it's installed.
    -> (data, ext)"""
    w, h = image_size(data)
    if max(w, h) <= IMAGE_MAX_SIDE and len(data) <= IMAGE_MAX_BYTES:
        return data, ext
    try:
        import io
        from PIL import Image
    except ImportError:
        return data, ext
    try:
        im = Image.open(io.BytesIO(data))
        im.load()
        im.thumbnail((IMAGE_MAX_SIDE, IMAGE_MAX_SIDE))
        buf = io.BytesIO()
        im.save(buf, "PNG", optimize=True)         # screenshots: text stays sharp
        ext = "png"
        if buf.tell() > IMAGE_MAX_BYTES:
            buf = io.BytesIO()
            im.convert("RGB").save(buf, "JPEG", quality=88)
            ext = "jpg"
        return buf.getvalue(), ext
    except Exception:          # a file Pillow can't read: send it as it is
        return data, ext


def save_image(data, ext):
    data, ext = shrink_image(data, ext)
    if len(data) > IMAGE_MAX_BYTES:
        return {"ok": False, "err": "That image is too big to send (%.1f MB; the limit is 3.7 MB)" % (len(data) / 1e6)}
    w, h = image_size(data)
    os.makedirs(image_dir(), mode=0o700, exist_ok=True)
    p = os.path.join(image_dir(), new_id() + "." + ext)
    with open(p, "wb") as f:
        f.write(data)
    return {"ok": True, "path": p, "w": w, "h": h}


def cmd_add_image(f):
    ext = os.path.splitext(f)[1].lower().lstrip(".")
    if ext not in IMAGE_EXT:
        return {"ok": False, "err": "Only PNG, JPEG, WebP and GIF images can be sent"}
    try:
        with open(os.path.expanduser(f), "rb") as fh:
            data = fh.read(50 * 1000 * 1000)
    except OSError as ex:
        return {"ok": False, "err": ex.strerror or str(ex)}
    return save_image(data, "jpg" if ext == "jpeg" else ext)


def cmd_paste_image():
    try:
        types = subprocess.run(["wl-paste", "--list-types"], capture_output=True, text=True, timeout=5,
                               stdin=subprocess.DEVNULL).stdout.split()
    except (OSError, subprocess.TimeoutExpired):
        return {"ok": False, "none": True}
    for t, ext in IMAGE_TYPES.items():
        if t in types:
            try:
                data = subprocess.run(["wl-paste", "--no-newline", "--type", t], capture_output=True, timeout=10,
                                      stdin=subprocess.DEVNULL).stdout
            except (OSError, subprocess.TimeoutExpired):
                return {"ok": False, "err": "Could not read the clipboard"}
            if data:
                return save_image(data, ext)
    if "text/uri-list" in types:         # an image file copied in DATA
        try:
            uris = subprocess.run(["wl-paste", "--no-newline", "--type", "text/uri-list"], capture_output=True,
                                  text=True, timeout=5, stdin=subprocess.DEVNULL).stdout.split()
        except (OSError, subprocess.TimeoutExpired):
            uris = []
        files = [urllib.parse.unquote(u[7:]) for u in uris if u.startswith("file://")]
        if len(files) == 1 and os.path.splitext(files[0])[1].lower().lstrip(".") in IMAGE_EXT:
            return cmd_add_image(files[0])
    return {"ok": False, "none": True}


def own_image(p):
    """p if it is one of ours (in <data>/images), else None."""
    d = os.path.realpath(image_dir())
    r = os.path.realpath(p or "")
    return r if os.path.dirname(r) == d and os.path.isfile(r) else None


def cmd_drop_image(p):
    r = own_image(p)
    if r:
        os.unlink(r)
    return {"ok": True}


def image_block(p):
    r = own_image(p)
    if not r:
        return None
    with open(r, "rb") as f:
        data = f.read()
    return {"type": "image", "source": {"type": "base64", "media_type": IMAGE_EXT.get(r.rsplit(".", 1)[-1], "image/png"),
                                        "data": base64.b64encode(data).decode()}}


# ---------------------------------------------------------------------------------------- system info
def cmd_dirs(d):
    d = os.path.realpath(os.path.expanduser(d or "~"))
    names = []
    with os.scandir(d) as it:
        for e in it:
            try:
                if e.is_dir():          # follows links to folders
                    names.append(e.name)
            except OSError:
                pass
    names.sort(key=lambda n: (n.lstrip(".").lower(), n))
    return {"ok": True, "dir": d, "parent": os.path.dirname(d) if d != "/" else "",
            "dirs": [{"n": n, "h": n.startswith(".")} for n in names]}


def sh(args, timeout=8):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
        return p.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def read(p, limit=200000):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read(limit)
    except OSError:
        return ""


def tail(p, n):
    t = read(p, 4 << 20)
    return "\n".join(t.splitlines()[-n:]) if t else ""


def sysinfo():
    fake = os.environ.get("ULTIMIT_CLAUDE_FAKE_SYSINFO")
    if fake is not None:
        return fake
    L = []
    osr = dict(re.findall(r'^(\w+)="?([^"\n]*)"?$', read("/etc/os-release"), re.M))
    L.append("Ultimit: %s (session %s)" % (read("/opt/ultimit/VERSION").strip() or "not in /opt/ultimit",
                                           os.environ.get("ULTIMIT_VERSION", "?")))
    L.append("OS: %s   Kernel: %s" % (osr.get("PRETTY_NAME", "?"), os.uname().release))
    L.append("Session: %s %s on %s" % (os.environ.get("XDG_SESSION_TYPE", "?"), os.environ.get("XDG_CURRENT_DESKTOP", "?"),
                                       os.environ.get("WAYLAND_DISPLAY", "no display")))
    cpu = re.search(r"model name\s*:\s*(.*)", read("/proc/cpuinfo"))
    L.append("CPU: %s (%d threads)" % (cpu.group(1) if cpu else "?", os.cpu_count() or 0))
    mem = dict(re.findall(r"^(\w+):\s+(\d+) kB", read("/proc/meminfo"), re.M))
    if mem:
        L.append("Memory: %.1f GB total, %.1f GB available" % (int(mem.get("MemTotal", 0)) / 1048576,
                                                               int(mem.get("MemAvailable", 0)) / 1048576))
    gpus = [l for l in sh(["lspci"]).splitlines() if re.search(r"VGA compatible|3D controller|Display controller", l)]
    for g in gpus:
        L.append("GPU: " + g.split(": ", 1)[-1])
    nv = read("/proc/driver/nvidia/version").splitlines()
    if nv:
        L.append("NVIDIA driver: " + nv[0].strip())
    try:
        st = json.loads(sh(["ultimitctl", "state"]) or "{}")
        for o in st.get("outputs", []):
            m = o.get("mode") or {}
            L.append("Monitor %s: %sx%s @ %.0f Hz, scale %s%s%s" % (
                o.get("name", "?"), m.get("width", "?"), m.get("height", "?"), (o.get("refresh_mhz") or 0) / 1000,
                o.get("scale", "?"), ", primary" if o.get("primary") else "", "" if o.get("enabled", True) else ", off"))
    except ValueError:
        pass
    df = sh(["df", "-h", "--output=target,size,avail,pcent", "/", HOME])
    text = "## This PC\n" + "\n".join("- " + l for l in L)
    if df:
        text += "\n\n### Disks\n```\n" + df + "\n```"
    failed = sh(["systemctl", "--failed", "--no-legend", "--plain"]) + "\n" + sh(["systemctl", "--user", "--failed", "--no-legend", "--plain"])
    if failed.strip():
        text += "\n\n### Failed services\n```\n" + failed.strip() + "\n```"
    log = tail(os.path.join(STATE, "session.log"), 40)
    if log:
        text += "\n\n### Last lines of the session log (%s)\n```\n%s\n```" % (os.path.join(STATE, "session.log"), log)
    errs = sh(["journalctl", "-b", "-p", "err", "-n", "25", "--no-pager", "-o", "short-monotonic"])
    if errs:
        text += "\n\n### Errors in this boot's journal (last 25)\n```\n" + errs + "\n```"
    return text


ULTIMIT_PROMPT = """This session runs in the Claude app built into Ultimit (its window is titled CLAUDE). Ultimit is a gaming-first Linux \
desktop on Ubuntu 26.04 LTS: its own Wayland compositor (wlroots) and a Quickshell (QML) desktop shell, installed in \
/opt/ultimit (source: https://github.com/m0nnnna/ultimit). Its native apps (DATA files, MEMO text, IMAGE, SETTINGS, \
STORE, FIREWALL, DISKS, BROADCAST) are QML in /opt/ultimit/shell/apps with Python helpers.

The person talks to you in a chat window, not a terminal. Commands you run cannot be answered interactively, so never \
start editors, pagers or anything that waits for input. For a step that needs root, run it through pkexec (the \
desktop shows its own password dialog) or give the exact command and say why it needs root.

Where things are on this PC:
- Session log: ~/.local/state/ultimit/session.log (the previous session: session.log.old); crash notes in \
~/.local/state/ultimit/crashes/
- User settings: ~/.config/ultimit/ (shell.json skin and look, displays.conf monitors, compositor.ini input)
- Compositor state (monitors, windows): `ultimitctl state`; keybindings: `ultimitctl keys`
- A full problem report: `ultimit-report` (writes a .tar.gz and prints its path)
- Ubuntu's own logs: `journalctl --user -b`, `journalctl -b -p warning`
- Install and update logs: ~/.local/state/ultimit/install-*.log, /var/log/ultimit-update.log"""


SUBAGENTS = {
    "scout": {"description": "Cheap and fast (Haiku, low effort). Finds and reads: locating files or code, grepping, "
                             "sweeping long logs or journals, checking state or versions. Answers in a few lines.",
              "prompt": "You find things for another Claude. Search and read only what the brief needs, change nothing, "
                        "and answer in a few lines: the facts, paths and line numbers, short quotes of the lines that "
                        "matter. No file dumps, no advice unless asked.",
              "model": "haiku", "effort": "low", "tools": ["Read", "Grep", "Glob", "Bash"]},
    "worker": {"description": "Cheap (Haiku, medium effort). Bulk or mechanical work to a known pattern: edits "
                              "across many files, reading many files to summarise them, running tests or builds and "
                              "reporting what failed.",
               "prompt": "You do a well-defined job for another Claude. Follow the brief exactly; if it turns out wrong "
                         "or unclear, stop and say so rather than guessing. Finish with a short report: what you "
                         "changed (paths), what you ran and the result, anything left undone. No file dumps.",
               "model": "haiku", "effort": "medium"},
    "expert": {"description": "Top tier (Opus, high effort), costly: only for a problem that has resisted a couple of "
                              "attempts, or needs deep reasoning across a lot of code (a subtle bug, a tricky design).",
               "prompt": "Another Claude hands you a hard problem with a brief. Work it out properly, check your "
                         "reasoning against the code or logs, and answer with the cause or design, the evidence, and "
                         "the concrete fix. Keep the answer tight.",
               "model": "opus", "effort": "high"},
}

SUBAGENT_PROMPT = """The person wants this chat to save their plan's limits and is fine with work taking longer for \
it. Scale the effort to the job instead of running at one pace:
- Scale down: hand grunt work to a subagent with the Agent tool, so the file dumps stay out of this chat and run on a \
cheaper model. subagent_type "scout" (Haiku) for finding and reading: locating code, grepping, sweeping logs, \
checking state. "worker" (Haiku) for bulk mechanical edits to a known pattern, summarising many files, running \
tests or builds. Give a self-contained brief (a subagent knows nothing of this chat) and ask for a short answer: \
facts, paths, line numbers. Don't re-read what a subagent already reported unless you need the exact lines to edit.
- Stay inline for a quick lookup, a single file, or anything that needs this chat's reasoning: a subagent costs a \
cold start, so it only pays off for jobs bigger than that.
- Scale up: when a problem resists two honest attempts, or needs deep reasoning over a lot of code, give it to \
"expert" (Opus, high effort) with a tight brief of what you know and what you tried, rather than looping on it here. \
It is costly; use it rarely.
- Run independent subagents in parallel; run one in the background when you have other work meanwhile.
- Keep your own replies short and don't restate what the person can already see."""


def system_prompt(proj):
    parts = [ULTIMIT_PROMPT]
    if proj["id"] == SYSTEM_ID:
        parts.append("This chat is for troubleshooting and looking after this PC. Start from what the person says "
                     "and the system summary in their first message; check logs and state before changing anything, "
                     "and say what you changed and how to undo it.")
    else:
        parts.append('This chat belongs to the project "%s" in %s.' % (proj["name"], proj["dir"]))
    parts.append(SUBAGENT_PROMPT)
    if (proj.get("notes") or "").strip():
        parts.append("Project notes from the person (keep to them):\n" + proj["notes"].strip())
    return "\n\n".join(parts)


# ---------------------------------------------------------------------------------------- session
def questions_of(req):
    """AskUserQuestion's questions, cleaned for the window: [{question, header, multi, options[{label, description}]}]."""
    if req.get("tool_name") != "AskUserQuestion":
        return []
    out = []
    for q in (req.get("input") or {}).get("questions") or []:
        if not isinstance(q, dict) or not q.get("question"):
            continue
        opts = [{"label": str(o.get("label", "")), "description": str(o.get("description", ""))}
                for o in q.get("options") or [] if isinstance(o, dict) and o.get("label")]
        out.append({"question": str(q["question"]), "header": str(q.get("header", "")),
                    "multi": bool(q.get("multiSelect")), "options": opts})
    return out


def summarize(name, inp):
    if not isinstance(inp, dict):
        return ""
    for k in ("command", "file_path", "notebook_path", "path", "pattern", "url", "query", "description", "prompt", "skill"):
        v = inp.get(k)
        if isinstance(v, str) and v:
            return v if len(v) < 400 else v[:400] + "…"
    for v in inp.values():
        if isinstance(v, str) and v:
            return v[:200]
    return ""


def clip(s, n):
    return s if len(s) <= n else s[:n] + "\n…(%d more characters)" % (len(s) - n)


def result_text(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(b.get("text", "") if isinstance(b, dict) and b.get("type") == "text" else
                         ("[image]" if isinstance(b, dict) and b.get("type") == "image" else "") for b in c).strip()
    return ""


class Session:
    """One running chat: `claude -p` with stream-json in and out, the window on the other side.

    Out (one JSON per line): {ev: started|init|delta|thinking|status|text|tool|tool_result|ask|asked|result|
    retry|limit|usage|note|exit}. The window answers asks with {op: permit}."""

    def __init__(self, pid, cid, aid=""):
        self.proj = project(pid)
        if not self.proj:
            raise ValueError("No such project")
        self.new = cid == "new"
        self.cid = new_id() if self.new else safe_id(cid)
        self.meta = {"id": self.cid, "project": pid, "title": "", "session": "", "created": time.time(),
                     "updated": time.time(), "account": (aid if self.new and account(aid) else "") or self.proj.get("account", "")}
        if not self.new:
            m = load_json(chat_meta_path(pid, self.cid), None)
            if m is None:
                raise ValueError("No such chat")
            self.meta.update(m)
        self.acc = account(self.meta["account"])
        self.lock = threading.Lock()
        self.asks = {}            # request id -> request (for "always")
        self.req = 0
        self.child = None
        self.busy = False
        self.cost_seen = 0.0      # total_cost_usd is a running total for this Claude Code process

    # -- persistence
    def save_meta(self):
        self.meta["updated"] = time.time()
        save_json(chat_meta_path(self.proj["id"], self.cid), self.meta)

    def record(self, item):
        if self.new and not self.meta.get("title"):
            return            # nothing is written for a chat until its first message
        p = chat_items_path(self.proj["id"], self.cid)
        os.makedirs(os.path.dirname(p), mode=0o700, exist_ok=True)
        with open(p, "a", encoding="utf-8") as f:
            f.write(json.dumps(item, ensure_ascii=False) + "\n")

    def emit(self, o):
        with self.lock:
            out(o)

    def write(self, o):
        try:
            self.child.stdin.write((json.dumps(o) + "\n").encode())
            self.child.stdin.flush()
        except (OSError, ValueError):
            pass

    def control(self, request):
        self.req += 1
        self.write({"type": "control_request", "request_id": "ul_%d_%s" % (self.req, secrets.token_hex(3)),
                    "request": request})

    # -- start
    def start(self):
        b = find_claude()
        if not b:
            self.emit({"ev": "exit", "code": -1, "err": "Claude Code is not installed"})
            return False
        if not self.acc:
            self.emit({"ev": "exit", "code": -1, "err": "This chat's account is gone; pick an account for the project"})
            return False
        ensure_auto_compact(self.acc)
        perm = self.proj.get("perm") or "default"
        args = [b, "-p", "--output-format", "stream-json", "--input-format", "stream-json", "--verbose",
                "--include-partial-messages", "--permission-prompt-tool", "stdio", "--permission-mode", perm,
                "--append-system-prompt", system_prompt(self.proj),
                "--effort", self.proj.get("effort") or DEFAULT_EFFORT, "--agents", json.dumps(SUBAGENTS)]
        args += ["--model", self.proj.get("model") or DEFAULT_MODEL]
        if self.meta.get("session"):
            args += ["--resume", self.meta["session"]]
        cwd = self.proj["dir"] if os.path.isdir(self.proj["dir"]) else HOME
        env = account_env(self.acc)
        env["CLAUDE_CODE_AUTO_COMPACT_WINDOW"] = COMPACT_WINDOW
        try:
            self.child = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                          cwd=cwd, env=env, start_new_session=True)
        except OSError as ex:
            self.emit({"ev": "exit", "code": -1, "err": str(ex)})
            return False
        self.stderr = []
        signal.signal(signal.SIGTERM, lambda *_: (self.child.terminate(), sys.exit(1)))
        threading.Thread(target=self.read_err, daemon=True).start()
        self.control({"subtype": "initialize", "hooks": None})
        self.emit({"ev": "started", "chat": self.cid, "meta": self.meta, "cwd": cwd,
                   "account": self.acc.get("name", ""), "perm": perm})
        return True

    def read_err(self):
        for line in self.child.stderr:
            self.stderr = (self.stderr + [line.decode("utf-8", "replace").rstrip()])[-20:]

    # -- from the window
    def send(self, text, with_sysinfo, images=()):
        body = text
        if with_sysinfo:
            body = "<system-summary>\n%s\n</system-summary>\n\n%s" % (sysinfo(), text)
        blocks, sent = [], []
        for p in images:
            b = image_block(p)
            if b:
                blocks.append(b)
                sent.append(own_image(p))
        if not text.strip() and not blocks:
            return
        if not self.meta.get("title"):
            t = " ".join(text.split())
            self.meta["title"] = t[:60] + ("…" if len(t) > 60 else "") or ("Image" if blocks else "Chat")
            self.save_meta()
        item = {"k": "user", "text": text, "sysinfo": bool(with_sysinfo), "t": time.time()}
        if sent:
            item["images"] = sent
        self.record(item)
        self.busy = True
        content = body
        if blocks:
            content = blocks + ([{"type": "text", "text": body}] if body.strip() else [])
        self.write({"type": "user", "session_id": "", "parent_tool_use_id": None,
                    "message": {"role": "user", "content": content}})

    def permit(self, rid, allow, always, answers=None):
        req = self.asks.pop(rid, None)
        if req is None:
            return
        if allow and isinstance(answers, dict):     # AskUserQuestion: the picks go back in the tool's input
            answers = {str(k): str(v) for k, v in answers.items()}
            resp = {"behavior": "allow", "updatedInput": dict(req.get("input") or {}, answers=answers)}
            self.write({"type": "control_response",
                        "response": {"subtype": "success", "request_id": rid, "response": resp}})
            self.record({"k": "note", "text": "Answered: " + "; ".join(answers.values()), "kind": "perm"})
            self.emit({"ev": "asked", "rid": rid, "allow": True})
            return
        if allow:
            resp = {"behavior": "allow", "updatedInput": req.get("input") or {}}
            if always and req.get("permission_suggestions"):
                resp["updatedPermissions"] = req["permission_suggestions"]
        else:
            resp = {"behavior": "deny", "message": "The person declined this in the CLAUDE window."}
        self.write({"type": "control_response",
                    "response": {"subtype": "success", "request_id": rid, "response": resp}})
        self.record({"k": "note", "text": ("Allowed" + (" (always)" if always and allow else "") if allow else "Declined")
                     + ": " + req.get("tool_name", "") + " " + summarize(req.get("tool_name", ""), req.get("input")),
                     "kind": "perm"})
        self.emit({"ev": "asked", "rid": rid, "allow": allow})

    # -- from Claude Code
    def handle(self, m):
        t = m.get("type")
        if t == "system":
            st = m.get("subtype")
            if st == "init":
                if m.get("session_id") and m["session_id"] != self.meta.get("session"):
                    self.meta["session"] = m["session_id"]
                    if self.meta.get("title"):
                        self.save_meta()
                self.emit({"ev": "init", "session": m.get("session_id", ""), "model": m.get("model", ""),
                           "mode": m.get("permissionMode", ""), "version": m.get("claude_code_version", "")})
            elif st == "status" and m.get("status") == "compacting":
                self.emit({"ev": "status", "text": "Compacting the conversation"})
            elif st == "compact_boundary":
                cm = m.get("compact_metadata") or {}
                pre = cm.get("pre_tokens") or 0
                text = ("Context compacted automatically" if cm.get("trigger") == "auto" else "Context compacted") + \
                       (" (it was %dK tokens); Claude carries on from a summary" % round(pre / 1000) if pre else "")
                self.record({"k": "note", "text": text, "kind": "compact"})
                self.emit({"ev": "compacted", "text": text, "trigger": cm.get("trigger", ""), "pre": pre})
            elif st == "task_summary":
                self.emit({"ev": "status", "text": m.get("detail") or ""})
            elif st == "api_retry":
                self.emit({"ev": "retry", "attempt": m.get("attempt"), "max": m.get("max_retries"),
                           "error": m.get("error", "")})
        elif t == "stream_event":
            if m.get("parent_tool_use_id"):
                return
            e = m.get("event") or {}
            if e.get("type") == "content_block_delta":
                d = e.get("delta") or {}
                if d.get("type") == "text_delta":
                    self.emit({"ev": "delta", "text": d.get("text", "")})
                elif d.get("type") == "thinking_delta":
                    self.emit({"ev": "thinking"})
        elif t == "assistant":
            if m.get("parent_tool_use_id"):
                return
            for b in (m.get("message") or {}).get("content") or []:
                if b.get("type") == "text" and b.get("text", "").strip():
                    self.record({"k": "claude", "text": b["text"]})
                    self.emit({"ev": "text", "text": b["text"]})
                elif b.get("type") == "tool_use":
                    it = {"k": "tool", "id": b.get("id", ""), "name": b.get("name", ""),
                          "summary": summarize(b.get("name"), b.get("input"))}
                    self.record(it)
                    self.emit(dict(it, ev="tool"))
        elif t == "user":
            if m.get("parent_tool_use_id"):
                return
            content = (m.get("message") or {}).get("content")
            for b in content if isinstance(content, list) else []:
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    o = clip(result_text(b.get("content")), 4000)
                    it = {"k": "tool_result", "id": b.get("tool_use_id", ""), "error": bool(b.get("is_error")), "out": o}
                    self.record(it)
                    self.emit(dict(it, ev="tool_result"))
        elif t == "control_request":
            r = m.get("request") or {}
            rid = m.get("request_id", "")
            if r.get("subtype") == "can_use_tool":
                self.asks[rid] = r
                self.emit({"ev": "ask", "rid": rid, "tool": r.get("tool_name", ""),
                           "title": r.get("title") or r.get("display_name") or "",
                           "summary": summarize(r.get("tool_name"), r.get("input")),
                           "detail": clip(json.dumps(r.get("input") or {}, indent=1, ensure_ascii=False), 3000),
                           "reason": r.get("decision_reason") or r.get("description") or "",
                           "always": bool(r.get("permission_suggestions")),
                           "questions": questions_of(r)})
            else:
                self.write({"type": "control_response", "response": {"subtype": "error", "request_id": rid,
                                                                     "error": "Not supported by CLAUDE"}})
        elif t == "rate_limit_event":
            r = m.get("rate_limit_info") or {}
            u = plan_usage(r)
            if u["windows"] and self.acc:
                save_json(usage_path(self.acc["id"]), u)
                self.emit(dict(u, ev="usage", account=self.acc["id"]))
            if r.get("status") not in (None, "allowed"):
                self.emit({"ev": "limit", "status": r.get("status"), "type": r.get("rateLimitType", ""),
                           "used": r.get("utilization"), "resets": r.get("resetsAt")})
        elif t == "control_cancel_request":
            rid = m.get("request_id", "")
            if self.asks.pop(rid, None) is not None:
                self.emit({"ev": "asked", "rid": rid, "allow": False, "cancelled": True})
        elif t == "result":
            self.busy = False
            err = bool(m.get("is_error")) or (m.get("subtype") not in (None, "success"))
            if m.get("session_id") and m["session_id"] != self.meta.get("session"):
                self.meta["session"] = m["session_id"]
            self.count_usage(m)
            if self.meta.get("title"):
                self.save_meta()
            o = {"ev": "result", "usage": self.meta.get("usage"), "context": self.meta.get("context"), "error": err, "cost": m.get("total_cost_usd"), "turns": m.get("num_turns"),
                 "ms": m.get("duration_ms"), "text": (m.get("result") or "") if err else "",
                 "denied": len(m.get("permission_denials") or [])}
            if err:
                self.record({"k": "note", "text": o["text"] or m.get("subtype", "error"), "kind": "error"})
            self.emit(o)

    def count_usage(self, m):
        """Add one turn's tokens and cost to the chat's totals, and note how full the context is."""
        u = m.get("usage") or {}
        total = m.get("total_cost_usd")
        cost = 0.0
        if isinstance(total, (int, float)):
            cost = total - self.cost_seen if total >= self.cost_seen else total
            self.cost_seen = total
        t = dict({"cost": 0.0, "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "turns": 0},
                 **(self.meta.get("usage") or {}))
        n = lambda v: v if isinstance(v, int) else 0
        t["cost"] = round(t["cost"] + max(cost, 0.0), 6)
        t["input"] += n(u.get("input_tokens"))
        t["output"] += n(u.get("output_tokens"))
        t["cacheRead"] += n(u.get("cache_read_input_tokens"))
        t["cacheWrite"] += n(u.get("cache_creation_input_tokens"))
        t["turns"] += 1 if u or cost else 0
        self.meta["usage"] = t
        last = (u.get("iterations") or [u])[-1] if u else {}
        used = sum(n(last.get(k)) for k in ("input_tokens", "cache_read_input_tokens",
                                             "cache_creation_input_tokens", "output_tokens"))
        window = max([n(x.get("contextWindow")) for x in (m.get("modelUsage") or {}).values()
                      if isinstance(x, dict)] or [0])
        if used:
            self.meta["context"] = {"used": used, "window": window or (self.meta.get("context") or {}).get("window", 0)}

    def read_out(self):
        for line in self.child.stdout:
            try:
                m = json.loads(line)
            except ValueError:
                continue
            try:
                self.handle(m)
            except Exception as ex:  # one odd message must not end the chat
                self.emit({"ev": "note", "text": "Could not read a message from Claude Code: %s" % ex})
        self.child.wait()
        err = "\n".join(l for l in self.stderr if l.strip())[-1500:]
        self.emit({"ev": "exit", "code": self.child.returncode, "err": err if self.child.returncode else ""})

    def run(self):
        if not self.start():
            return
        reader = threading.Thread(target=self.read_out, daemon=True)
        reader.start()
        for line in sys.stdin:
            try:
                c = json.loads(line)
            except ValueError:
                continue
            op = c.get("op")
            if op == "send" and ((c.get("text") or "").strip() or c.get("images")):
                self.send(c.get("text") or "", bool(c.get("sysinfo")), [p for p in c.get("images") or [] if isinstance(p, str)])
            elif op == "permit":
                self.permit(c.get("rid", ""), bool(c.get("allow")), bool(c.get("always")), c.get("answers"))
            elif op == "interrupt":
                self.control({"subtype": "interrupt"})
            elif op == "close":
                break
        if self.busy:          # closing mid-turn stops the turn, like the Stop button
            self.control({"subtype": "interrupt"})
        try:
            self.child.stdin.close()
        except OSError:
            pass
        for _ in range(100):
            if self.child.poll() is not None:
                break
            time.sleep(0.1)
        if self.child.poll() is None:
            self.child.terminate()
        reader.join(timeout=5)


# ---------------------------------------------------------------------------------------- main
def main(argv):
    if not argv:
        print(__doc__.strip())
        return 2
    c, a = argv[0], argv[1:]
    try:
        if c == "state":
            out(cmd_state())
        elif c == "cli":
            out(cmd_cli())
        elif c == "install":
            cmd_install()
        elif c == "account-add":
            out(cmd_account_add(a[0] if a else ""))
        elif c == "account-default":
            out(cmd_account_default())
        elif c == "account-rename":
            out(cmd_account_rename(a[0], a[1]))
        elif c == "account-remove":
            out(cmd_account_remove(a[0], len(a) > 1 and a[1] == "purge"))
        elif c == "auth-status":
            out(cmd_auth_status(a[0]))
        elif c == "login":
            cmd_login(a[0], len(a) > 1 and a[1] == "console")
        elif c == "logout":
            out(cmd_logout(a[0]))
        elif c == "project-save":
            out(cmd_project_save(json.loads(sys.stdin.readline() or "{}")))
        elif c == "project-remove":
            out(cmd_project_remove(a[0]))
        elif c == "chats":
            out(cmd_chats(a[0]))
        elif c == "chat":
            out(cmd_chat(a[0], a[1]))
        elif c == "chat-rename":
            out(cmd_chat_rename(a[0], a[1], a[2]))
        elif c == "chat-account":
            out(cmd_chat_account(a[0], a[1], a[2]))
        elif c == "chat-move":
            out(cmd_chat_move(a[0], a[1], a[2]))
        elif c == "chat-remove":
            out(cmd_chat_remove(a[0], a[1]))
        elif c == "dirs":
            out(cmd_dirs(a[0] if a else ""))
        elif c == "paste-image":
            out(cmd_paste_image())
        elif c == "add-image":
            out(cmd_add_image(a[0]))
        elif c == "drop-image":
            out(cmd_drop_image(a[0]))
        elif c == "usage":
            out(cmd_usage())
        elif c == "sysinfo":
            out({"ok": True, "text": sysinfo()})
        elif c == "session":
            try:
                s = Session(a[0], a[1], a[2] if len(a) > 2 else "")
            except ValueError as ex:
                out({"ev": "exit", "code": -1, "err": str(ex)})
                return 1
            s.run()
        else:
            out({"ok": False, "err": "unknown command " + c})
            return 2
    except (IndexError, ValueError, OSError) as ex:
        out({"ok": False, "err": str(ex) or ex.__class__.__name__})
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
