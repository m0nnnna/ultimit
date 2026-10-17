#!/usr/bin/env python3
"""Tests for ember.py: provider message shapes, tool checks, and a chat session against EMBER_FAKE.
    python3 shell/apps/ember/test_ember.py"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TMP = tempfile.mkdtemp(prefix="ember-test-")
os.environ.update(XDG_CONFIG_HOME=os.path.join(TMP, "cfg"), XDG_DATA_HOME=os.path.join(TMP, "data"), EMBER_FAKE="1")
sys.path.insert(0, HERE)
import ember  # noqa: E402

HISTORY = [
    {"role": "user", "text": "list my home"},
    {"role": "assistant", "text": "Certainly.", "calls": [{"id": "toolu_1", "name": "list_dir", "args": {"path": "~"}}],
     "raw": [{"type": "thinking", "thinking": "", "signature": "sig"}, {"type": "text", "text": "Certainly."},
             {"type": "tool_use", "id": "toolu_1", "name": "list_dir", "input": {"path": "~"}}]},
    {"role": "tool", "id": "toolu_1", "name": "list_dir", "out": "dir  Documents", "error": False},
    {"role": "user", "text": "thanks"},
    {"role": "assistant", "text": "From GPT", "calls": [{"id": "call_2", "name": "windows", "args": {}}]},
    {"role": "tool", "id": "call_2", "name": "windows", "out": "", "error": True},
]


class Shapes(unittest.TestCase):
    def test_anthropic_keeps_raw_blocks_and_groups_results(self):
        m = ember.anthropic_messages(HISTORY)
        self.assertEqual([x["role"] for x in m], ["user", "assistant", "user", "assistant", "user"])
        self.assertEqual(m[1]["content"][0]["type"], "thinking")           # sent back unchanged
        self.assertEqual(m[2]["content"][0]["type"], "tool_result")        # the result, then the next text
        self.assertEqual(m[2]["content"][1], {"type": "text", "text": "thanks"})
        self.assertEqual(m[3]["content"][1]["type"], "tool_use")           # rebuilt from another provider
        self.assertTrue(m[4]["content"][0]["is_error"])

    def test_openai_shape(self):
        m = ember.openai_messages(HISTORY)
        self.assertEqual(m[0]["role"], "system")
        self.assertEqual(m[2]["tool_calls"][0]["function"], {"name": "list_dir", "arguments": '{"path": "~"}'})
        self.assertEqual(m[3], {"role": "tool", "tool_call_id": "toolu_1", "content": "dir  Documents"})

    def test_display_items(self):
        it = ember.display_items(HISTORY)
        self.assertEqual([x["k"] for x in it], ["user", "ember", "tool", "user", "ember", "tool"])
        self.assertEqual(it[2]["status"], "ok")
        self.assertEqual(it[5]["status"], "error")

    def test_validate(self):
        self.assertIsNone(ember.validate("read_file", {"path": "/etc/hostname"}))
        self.assertIn("Missing", ember.validate("read_file", {}))
        self.assertIn("integer", ember.validate("run_command", {"command": "x", "timeout": "5"}))
        self.assertIn("one of", ember.validate("window", {"id": 1, "action": "explode"}))
        self.assertIn("no tool", ember.validate("nope", {}))

    def test_ask_rules(self):
        self.assertTrue(ember.needs_ask("run_command", {}))
        self.assertTrue(ember.needs_ask("window", {"action": "close"}))
        self.assertFalse(ember.needs_ask("window", {"action": "focus"}))
        self.assertFalse(ember.needs_ask("read_file", {}))

    def test_effort_models(self):
        self.assertTrue(ember.effort_ok("claude-opus-5-5"))
        self.assertTrue(ember.effort_ok("claude-sonnet-5-5"))
        self.assertFalse(ember.effort_ok("claude-haiku-4-5"))

    def test_tools(self):
        stop = ember.threading.Event()
        p = os.path.join(TMP, "note.txt")
        self.assertTrue(ember.run_tool("write_file", {"path": p, "content": "a\nb\n"}, stop)[0])
        ok, text = ember.run_tool("read_file", {"path": p, "offset": 2}, stop)
        self.assertTrue(ok)
        self.assertIn("2  b", text)
        ok, text = ember.run_tool("run_command", {"command": "echo hi; exit 3"}, stop)
        self.assertFalse(ok)
        self.assertIn("hi", text)
        self.assertIn("exit code 3", text)
        ok, text = ember.run_tool("run_command", {"command": "sleep 5", "timeout": 1}, stop)
        self.assertIn("timed out", text)
        self.assertIn("note.txt", ember.run_tool("list_dir", {"path": TMP}, stop)[1])

    def test_persona(self):
        self.assertIn("tsundere", ember.system_prompt())
        ember.write_json(ember.CONF, {})
        with open(ember.MY_PERSONA, "w") as f:
            f.write("You are Ember, but cheerful, {user}.")
        try:
            p = ember.system_prompt()
            self.assertTrue(p.startswith("You are Ember, but cheerful, "))
            self.assertNotIn("{user}", p)
            self.assertIn("# Care", p)                       # the rules stay whatever the persona
        finally:
            os.remove(ember.MY_PERSONA)

    def test_html_text(self):
        self.assertEqual(ember.html_text("<style>x</style><p>Hi &amp; bye</p><script>y</script>"), "Hi & bye")


# a stand-in API server: answers /v1/messages (Claude) and /chat/completions (OpenAI) with a canned
# stream that says something and calls a tool with its input split across chunks
def sse(events):
    return "".join("data: %s\n\n" % (e if isinstance(e, str) else json.dumps(e)) for e in events).encode()


ANTHROPIC = sse([
    {"type": "message_start", "message": {"usage": {"input_tokens": 5, "cache_read_input_tokens": 7}}},
    {"type": "content_block_start", "index": 0, "content_block": {"type": "thinking", "thinking": "", "signature": ""}},
    {"type": "content_block_delta", "index": 0, "delta": {"type": "signature_delta", "signature": "abc"}},
    {"type": "content_block_stop", "index": 0},
    {"type": "content_block_start", "index": 1, "content_block": {"type": "text", "text": ""}},
    {"type": "content_block_delta", "index": 1, "delta": {"type": "text_delta", "text": "Allow "}},
    {"type": "content_block_delta", "index": 1, "delta": {"type": "text_delta", "text": "me."}},
    {"type": "content_block_stop", "index": 1},
    {"type": "content_block_start", "index": 2, "content_block": {"type": "tool_use", "id": "toolu_9", "name": "list_dir", "input": {}}},
    {"type": "content_block_delta", "index": 2, "delta": {"type": "input_json_delta", "partial_json": '{"pa'}},
    {"type": "content_block_delta", "index": 2, "delta": {"type": "input_json_delta", "partial_json": 'th": "~"}'}},
    {"type": "content_block_stop", "index": 2},
    {"type": "message_delta", "delta": {"stop_reason": "tool_use"}, "usage": {"output_tokens": 12}},
    {"type": "message_stop"},
])
OPENAI = sse([
    {"choices": [{"delta": {"role": "assistant", "content": "Allow "}}]},
    {"choices": [{"delta": {"content": "me."}}]},
    {"choices": [{"delta": {"tool_calls": [{"index": 0, "id": "call_9", "function": {"name": "list_dir", "arguments": '{"pa'}}]}}]},
    {"choices": [{"delta": {"tool_calls": [{"index": 0, "function": {"arguments": 'th": "~"}'}}]}, "finish_reason": "tool_calls"}]},
    {"choices": [], "usage": {"prompt_tokens": 3, "completion_tokens": 4}},
    "[DONE]",
])


class Api(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import http.server
        import threading
        cls.seen = []

        class H(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["content-length"])))
                Api.seen.append((self.path, {k.lower(): v for k, v in self.headers.items()}, body))
                data = ANTHROPIC if self.path == "/v1/messages" else OPENAI
                self.send_response(200)
                self.send_header("content-type", "text/event-stream")
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(json.dumps({"data": [{"id": "m-chat"}, {"id": "text-embedding-3"}]}).encode())

            def log_message(self, *a):
                pass
        cls.srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()
        cls.base = "http://127.0.0.1:%d" % cls.srv.server_port

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()

    def test_anthropic_stream(self):
        evs = []
        t = ember.stream_anthropic({"model": "claude-opus-5-5", "base": self.base, "effort": "high"}, "k",
                                   HISTORY[:1], evs.append, ember.threading.Event())
        self.assertEqual(t.text, "Allow me.")
        self.assertEqual(t.calls, [{"id": "toolu_9", "name": "list_dir", "args": {"path": "~"}, "bad": None}])
        self.assertEqual(t.raw[0], {"type": "thinking", "thinking": "", "signature": "abc"})
        self.assertEqual(t.raw[2]["input"], {"path": "~"})
        self.assertEqual((t.stop, t.usage), ("tool_use", {"input": 12, "output": 12}))
        self.assertIn({"ev": "thinking"}, evs)
        path, headers, body = self.seen[-1]
        self.assertEqual(headers["x-api-key"], "k")
        self.assertEqual(body["output_config"], {"effort": "high"})
        self.assertTrue(all(x["eager_input_streaming"] for x in body["tools"]))
        self.assertNotIn("fallbacks", body)              # only on Anthropic's own API

    def test_openai_stream(self):
        evs = []
        t = ember.stream_openai("local", {"model": "m", "base": self.base}, "", HISTORY[:1], evs.append,
                                ember.threading.Event())
        self.assertEqual(t.text, "Allow me.")
        self.assertEqual(t.calls[0]["args"], {"path": "~"})
        self.assertEqual(t.stop, "tool_use")
        self.assertEqual(t.usage, {"input": 3, "output": 4})
        self.assertNotIn("authorization", self.seen[-1][1])

    def test_models_list_skips_non_chat(self):
        os.environ.pop("EMBER_FAKE")
        try:
            ember.write_json(ember.CONF, {"providers": {"local": {"base": self.base}}})
            self.assertEqual(ember.models("local"), {"ok": True, "models": ["m-chat"]})
        finally:
            os.environ["EMBER_FAKE"] = "1"
            ember.write_json(ember.CONF, {})


class Session(unittest.TestCase):
    def talk(self, lines, answer=None):
        p = subprocess.Popen([sys.executable, os.path.join(HERE, "ember.py"), "session"], stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, text=True)
        evs = []
        for l in lines:
            p.stdin.write(json.dumps(l) + "\n")
            p.stdin.flush()
            while True:
                o = json.loads(p.stdout.readline())
                evs.append(o)
                if o["ev"] == "ask" and answer is not None:
                    p.stdin.write(json.dumps({"type": "permit", "id": o["id"], "allow": answer}) + "\n")
                    p.stdin.flush()
                if o["ev"] == "done":
                    break
        p.stdin.close()
        p.stdout.close()
        p.wait(5)
        return evs

    def test_reply_and_saved_chat(self):
        evs = self.talk([{"type": "send", "text": "Hello"}])
        cid = evs[0]["id"]
        self.assertIn("Good day", "".join(e.get("delta", "") for e in evs))
        r = ember.main(["", "chat", cid])
        self.assertEqual([i["k"] for i in r["items"]], ["user", "ember"])

    def test_allowed_command_runs(self):
        evs = self.talk([{"type": "send", "text": "run: echo allowed-ok"}], answer=True)
        done = [e for e in evs if e["ev"] == "tool_done"][0]
        self.assertTrue(done["ok"])
        self.assertIn("allowed-ok", done["out"])

    def test_denied_command_does_not_run(self):
        marker = os.path.join(TMP, "should-not-exist")
        evs = self.talk([{"type": "send", "text": "run: touch " + marker}], answer=False)
        self.assertFalse(os.path.exists(marker))
        self.assertIn("declined", [e for e in evs if e["ev"] == "tool_done"][0]["out"])

    def test_trust_skips_the_ask(self):
        ember.write_json(ember.CONF, {"trust": True})
        try:
            evs = self.talk([{"type": "send", "text": "run: echo trusted"}])
        finally:
            ember.write_json(ember.CONF, {})
        self.assertFalse([e for e in evs if e["ev"] == "ask"])
        self.assertIn("trusted", [e for e in evs if e["ev"] == "tool_done"][0]["out"])


if __name__ == "__main__":
    unittest.main()
