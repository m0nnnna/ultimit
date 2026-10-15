#!/usr/bin/python3 -I
"""Tests for claude.py (CLAUDE's helper) against fixtures/fake-claude: python3 apps/claude/test_claude.py"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FAKE = os.path.join(HERE, "fixtures", "fake-claude")


class ClaudeHelper(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = os.path.join(self.tmp.name, "home")
        os.makedirs(self.home)
        self.proj_dir = os.path.join(self.tmp.name, "src", "game")
        os.makedirs(self.proj_dir)
        self.env = dict(os.environ, HOME=self.home, ULTIMIT_CLAUDE_HOME=os.path.join(self.tmp.name, "data"),
                        ULTIMIT_CLAUDE_BIN=FAKE, ULTIMIT_CLAUDE_FAKE_SYSINFO="## This PC\n- GPU: test",
                        ANTHROPIC_API_KEY="sk-leak", CLAUDE_CODE_OAUTH_TOKEN="leak", XDG_DATA_HOME="", XDG_STATE_HOME="")

    def tearDown(self):
        self.tmp.cleanup()

    def run_helper(self, *args, stdin=""):
        p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "claude.py")] + list(args), input=stdin,
                           capture_output=True, text=True, env=self.env, timeout=60)
        self.assertEqual(p.stderr, "")
        return p.stdout

    def j(self, *args, stdin=""):
        return json.loads(self.run_helper(*args, stdin=stdin))

    def events(self, *args, stdin=""):
        return [json.loads(l) for l in self.run_helper(*args, stdin=stdin).splitlines() if l.strip()]

    def add_logged_in(self, name="Work"):
        acc = self.j("account-add", name)["account"]
        ev = self.events("login", acc["id"], stdin="good-code\n")
        self.assertTrue(ev[-1]["ok"], ev)
        return acc

    def session(self, pid, chat, *sends, answer=None):
        """Drive a chat like the window does: send each message once the previous turn has finished,
        answer permission asks with answer(ask) -> (allow, always), then close. Returns every event."""
        p = subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "claude.py"), "session", pid, chat],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=self.env)
        ev, todo = [], list(sends)

        def send(o):
            p.stdin.write(json.dumps(o) + "\n")
            p.stdin.flush()
        for line in p.stdout:
            e = json.loads(line)
            ev.append(e)
            if e["ev"] in ("started", "result"):
                if todo:
                    send(todo.pop(0))
                else:
                    send({"op": "close"})
            elif e["ev"] == "ask":
                allow, always = answer(e)
                send({"op": "permit", "rid": e["rid"], "allow": allow, "always": always})
        p.wait(timeout=30)
        p.stdin.close()
        p.stdout.close()
        return ev

    # ---- accounts
    def test_accounts_get_their_own_private_dirs(self):
        a = self.j("account-add", "Work stuff")["account"]
        b = self.j("account-add", "Work stuff")["account"]
        self.assertEqual((a["id"], b["id"]), ("work-stuff", "work-stuff-2"))
        self.assertNotEqual(a["dir"], b["dir"])
        self.assertEqual(os.stat(a["dir"]).st_mode & 0o777, 0o700)
        d = self.j("account-default")["account"]
        self.assertEqual(d["dir"], "")
        self.assertEqual(self.j("account-default")["account"]["id"], d["id"])   # only once
        self.assertEqual(len(self.j("state")["accounts"]), 3)

    def test_login_status_logout(self):
        acc = self.j("account-add", "Personal")["account"]
        self.assertFalse(self.j("auth-status", acc["id"])["loggedIn"])
        ev = self.events("login", acc["id"], stdin="wrong\n")
        self.assertIn({"ev": "url", "url": "https://claude.com/cai/oauth/authorize?code=true&state=x"}, ev)
        self.assertIn({"ev": "code"}, ev)
        self.assertFalse(ev[-1]["ok"])
        self.assertIn("invalid code", ev[-1]["err"])
        ev = self.events("login", acc["id"], stdin="good-code\n")
        self.assertTrue(ev[-1]["ok"])
        st = self.j("auth-status", acc["id"])
        self.assertTrue(st["loggedIn"])
        self.assertEqual(st["email"], "noc@example.com")
        # the login landed in the account's own directory, nowhere else
        self.assertTrue(os.path.exists(os.path.join(acc["dir"], ".credentials.json")))
        self.assertFalse(os.path.exists(os.path.join(self.home, ".claude", ".credentials.json")))
        self.assertTrue(self.j("logout", acc["id"])["ok"])
        self.assertFalse(self.j("auth-status", acc["id"])["loggedIn"])

    def test_remove_purges_only_own_dirs(self):
        acc = self.j("account-add", "Temp")["account"]
        d = self.j("account-default")["account"]
        os.makedirs(os.path.join(self.home, ".claude"))
        self.j("account-remove", d["id"], "purge")
        self.assertTrue(os.path.isdir(os.path.join(self.home, ".claude")))
        self.j("account-remove", acc["id"], "purge")
        self.assertFalse(os.path.exists(acc["dir"]))
        self.assertEqual(self.j("state")["accounts"], [])

    # ---- projects
    def test_projects(self):
        st = self.j("state")
        self.assertEqual([p["id"] for p in st["projects"]], ["system"])
        self.assertEqual(st["projects"][0]["dir"], self.home)
        p = self.j("project-save", stdin=json.dumps({"name": "Game", "dir": self.proj_dir, "perm": "acceptEdits",
                                                      "notes": "Godot 4, C#"}))["project"]
        self.assertTrue(p["id"].startswith("game-"))
        self.assertFalse(self.j("project-save", stdin=json.dumps({"name": "X", "dir": "/nope/nowhere"}))["ok"])
        self.assertFalse(self.j("project-save", stdin=json.dumps({"name": "X", "dir": self.proj_dir, "perm": "yolo"}))["ok"])
        self.j("project-save", stdin=json.dumps({"id": "system", "notes": "three screens", "dir": "/etc"}))
        ps = self.j("state")["projects"]
        self.assertEqual(ps[0]["notes"], "three screens")
        self.assertEqual(ps[0]["dir"], self.home)     # the built-in one always works from home
        self.assertEqual(ps[1]["notes"], "Godot 4, C#")
        self.assertFalse(self.j("project-remove", "system")["ok"])
        self.assertTrue(self.j("project-remove", p["id"])["ok"])
        self.assertEqual(len(self.j("state")["projects"]), 1)

    # ---- chats
    def test_chat_isolated_account_and_history(self):
        acc = self.add_logged_in()
        p = self.j("project-save", stdin=json.dumps({"name": "Game", "dir": self.proj_dir, "account": acc["id"]}))["project"]
        ev = self.session(p["id"], "new", {"op": "send", "text": "hello there", "sysinfo": True})
        kinds = [e["ev"] for e in ev]
        self.assertEqual(kinds[0], "started")
        self.assertIn("init", kinds)
        self.assertIn("status", kinds)
        self.assertIn("delta", kinds)
        text = [e for e in ev if e["ev"] == "text"][0]["text"]
        # the account's own config dir, no credential from the desktop's environment, the system summary
        # attached, and the project folder as the working directory
        self.assertEqual(text, "config=%s leaked=none sysinfo=True cwd=%s" % (acc["dir"], self.proj_dir))
        self.assertEqual("".join(e["text"] for e in ev if e["ev"] == "delta"), text)
        res = [e for e in ev if e["ev"] == "result"][0]
        self.assertFalse(res["error"])
        self.assertEqual(ev[-1]["ev"], "exit")
        chat = ev[0]["chat"]

        chats = self.j("chats", p["id"])["chats"]
        self.assertEqual(len(chats), 1)
        self.assertEqual(chats[0]["title"], "hello there")
        self.assertEqual(chats[0]["account"], acc["id"])
        sid = chats[0]["session"]
        self.assertTrue(sid)
        c = self.j("chat", p["id"], chat)
        self.assertEqual([i["k"] for i in c["items"]], ["user", "claude"])
        self.assertTrue(c["items"][0]["sysinfo"])
        self.assertEqual(c["items"][0]["text"], "hello there")    # the summary is not repeated in the history

        # carrying on resumes the same Claude Code session
        ev = self.session(p["id"], chat, {"op": "send", "text": "again"})
        self.assertEqual([e for e in ev if e["ev"] == "init"][0]["session"], sid)
        self.assertEqual(len(self.j("chat", p["id"], chat)["items"]), 4)
        self.assertTrue(self.j("chat-rename", p["id"], chat, "Renamed")["ok"])
        self.assertEqual(self.j("chats", p["id"])["chats"][0]["title"], "Renamed")
        self.assertTrue(self.j("chat-remove", p["id"], chat)["ok"])
        self.assertEqual(self.j("chats", p["id"])["chats"], [])

    def test_usage(self):
        acc = self.add_logged_in()
        p = self.j("project-save", stdin=json.dumps({"name": "Game", "dir": self.proj_dir, "account": acc["id"]}))["project"]
        self.assertEqual(self.j("usage")["accounts"], {})
        ev = self.session(p["id"], "new", {"op": "send", "text": "one"}, {"op": "send", "text": "two"})
        # the plan's limits as Claude Code reported them, for the account, after every turn
        us = [e for e in ev if e["ev"] == "usage"]
        self.assertEqual(len(us), 2)
        self.assertEqual(us[-1]["account"], acc["id"])
        self.assertAlmostEqual(us[-1]["windows"]["five_hour"]["used"], 0.2)
        self.assertEqual(us[-1]["windows"]["seven_day"]["resets"], 1792263600)
        saved = self.j("usage")["accounts"][acc["id"]]
        self.assertAlmostEqual(saved["windows"]["five_hour"]["used"], 0.2)
        # the chat's totals: running cost counted once, tokens per turn, context of the last turn
        res = [e for e in ev if e["ev"] == "result"]
        self.assertAlmostEqual(res[-1]["usage"]["cost"], 0.004)
        self.assertEqual(res[-1]["usage"]["output"], 60)
        self.assertEqual(res[-1]["usage"]["turns"], 2)
        self.assertEqual(res[-1]["context"], {"used": 2 + 2000 + 500 + 30, "window": 200000})
        meta = self.j("chat", p["id"], ev[0]["chat"])["meta"]
        self.assertEqual(meta["usage"]["turns"], 2)
        # a new Claude Code process (resuming the chat) starts its running total again
        ev = self.session(p["id"], ev[0]["chat"], {"op": "send", "text": "three"})
        self.assertAlmostEqual([e for e in ev if e["ev"] == "result"][-1]["usage"]["cost"], 0.006)
        self.assertTrue(self.j("account-remove", acc["id"])["ok"])
        self.assertEqual(self.j("usage")["accounts"], {})

    def test_permission_ask_allow_and_deny(self):
        acc = self.add_logged_in()
        p = self.j("project-save", stdin=json.dumps({"name": "Game", "dir": self.proj_dir, "account": acc["id"]}))["project"]
        for allow, want in ((True, "Wrote it."), (False, "Not written.")):
            ev = self.session(p["id"], "new", {"op": "send", "text": "please write a file"},
                              answer=lambda a, allow=allow: (allow, True))
            ask = [e for e in ev if e["ev"] == "ask"][0]
            self.assertEqual((ask["tool"], ask["summary"], ask["always"]), ("Write", "/tmp/x/hello.txt", True))
            tool = [e for e in ev if e["ev"] == "tool"][0]
            self.assertEqual(tool["name"], "Write")
            tr = [e for e in ev if e["ev"] == "tool_result"][0]
            self.assertEqual(tr["error"], not allow)
            self.assertEqual([e for e in ev if e["ev"] == "text"][0]["text"], want)
            items = self.j("chat", p["id"], ev[0]["chat"])["items"]
            t = [i for i in items if i["k"] == "tool"][0]
            self.assertEqual(t["status"], "ok" if allow else "error")
            self.assertTrue(any(i["k"] == "note" and i["kind"] == "perm" for i in items))

    def test_not_logged_in_and_no_cli(self):
        acc = self.j("account-add", "Empty")["account"]
        self.j("project-save", stdin=json.dumps({"id": "system", "account": acc["id"]}))
        ev = self.session("system", "new", {"op": "send", "text": "hi"})
        res = [e for e in ev if e["ev"] == "result"][0]
        self.assertTrue(res["error"])
        self.assertIn("Not logged in", res["text"])
        self.env["ULTIMIT_CLAUDE_BIN"] = os.path.join(self.tmp.name, "missing")
        self.assertEqual(self.j("cli")["path"], "")
        ev = self.session("system", "new", {"op": "send", "text": "hi"})
        self.assertEqual(ev, [{"ev": "exit", "code": -1, "err": "Claude Code is not installed"}])

    def test_bad_ids_rejected(self):
        self.assertFalse(self.j("chat", "../../etc", "passwd")["ok"])
        self.assertEqual(self.events("session", "nope", "new"), [{"ev": "exit", "code": -1, "err": "No such project"}])

    def test_cli_version(self):
        self.assertEqual(self.j("cli"), {"ok": True, "path": FAKE, "version": "9.9.9"})

    def test_dirs(self):
        os.makedirs(os.path.join(self.home, "src", "b"))
        os.makedirs(os.path.join(self.home, ".config"))
        os.makedirs(os.path.join(self.home, "Apps"))
        open(os.path.join(self.home, "notes.txt"), "w").close()
        os.symlink(os.path.join(self.home, "src"), os.path.join(self.home, "code"))
        o = self.j("dirs", "~")
        self.assertEqual(o["dir"], os.path.realpath(self.home))
        self.assertEqual([d["n"] for d in o["dirs"]], ["Apps", "code", ".config", "src"])
        self.assertTrue(o["dirs"][2]["h"])
        self.assertEqual(self.j("dirs", "/")["parent"], "")
        self.assertFalse(self.j("dirs", os.path.join(self.home, "nope"))["ok"])


if __name__ == "__main__":
    unittest.main()
