#!/usr/bin/python3 -I
"""Tests for audio.py (Settings > Sound, display audio) with a fake pw-dump/wpctl: python3 apps/settings/test_audio.py"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import audio  # noqa: E402

FIXTURE = os.path.join(HERE, "fixtures/pw-dump-hdmi.json")


def load():
    with open(FIXTURE) as f:
        return json.load(f)


class Parse(unittest.TestCase):
    def test_only_hdmi_cards(self):
        cards = audio.cards(load())
        self.assertEqual([c["id"] for c in cards], [50])

    def test_outputs_named_by_monitor(self):
        outs = audio.cards(load())[0]["outputs"]
        self.assertEqual([(o["index"], o["label"]) for o in outs[:2]], [(1, "100027813"), (2, "LG ULTRAGEAR")])
        lg = outs[1]
        self.assertEqual((lg["port"], lg["kind"], lg["connected"], lg["active"]), ("HDMI / DisplayPort 2", "Stereo", True, False))
        self.assertTrue(outs[0]["active"])

    def test_unplugged_last_with_surround(self):
        outs = audio.cards(load())[0]["outputs"]
        self.assertEqual([o["connected"] for o in outs], [True, True] + [False] * 6)
        self.assertEqual([o["kind"] for o in outs[2:5]], ["Stereo", "5.1 surround", "7.1 surround"])
        self.assertEqual(outs[2]["label"], "HDMI / DisplayPort 3")

    def test_info_pairs(self):
        self.assertEqual(audio.info_pairs({"info": [1, "a", "b"]}), {"a": "b"})
        self.assertEqual(audio.info_pairs({}), {})

    def test_default_and_sink(self):
        d = load()
        self.assertEqual(audio.default_sink_name(d), "alsa_output.usb-Kraken")
        self.assertEqual(audio.card_sink(d, 50), 140)
        self.assertIsNone(audio.card_sink(d, 99))


class WithFakes(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.log = os.path.join(self.tmp.name, "calls")

    def tearDown(self):
        self.tmp.cleanup()

    def run_audio(self, *args, dump=FIXTURE):
        env = dict(os.environ, AUDIO_PWDUMP=os.path.join(HERE, "fixtures/fake-pw-dump"),
                   AUDIO_WPCTL=os.path.join(HERE, "fixtures/fake-wpctl"), AUDIO_TEST_LOG=self.log, AUDIO_TEST_DUMP=dump)
        p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "audio.py")] + list(args),
                           capture_output=True, text=True, env=env, timeout=20)
        calls = open(self.log).read().splitlines() if os.path.exists(self.log) else []
        return json.loads(p.stdout), calls

    def test_list(self):
        o, calls = self.run_audio("list")
        self.assertTrue(o["ok"])
        self.assertEqual(o["cards"][0]["name"], "AD104 High Definition Audio Controller")
        self.assertEqual(calls, [])

    def test_set_makes_default(self):
        o, calls = self.run_audio("set", "50", "2")
        self.assertEqual(o, {"ok": True, "default": True})
        self.assertEqual(calls, ["set-profile 50 2", "set-default 140"])

    def test_set_keeps_easy_effects(self):
        d = load()
        d[-1]["metadata"][0]["value"]["name"] = "easyeffects_sink"
        path = os.path.join(self.tmp.name, "ee.json")
        with open(path, "w") as f:
            json.dump(d, f)
        o, calls = self.run_audio("set", "50", "2", dump=path)
        self.assertTrue(o["easyEffects"])
        self.assertEqual(calls, ["set-profile 50 2"])

    def test_bad_args(self):
        o, calls = self.run_audio("set", "50", "x")
        self.assertFalse(o["ok"])
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
