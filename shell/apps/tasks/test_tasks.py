#!/usr/bin/env python3
"""Unit tests for tasks.py. Run: python3 -m unittest apps/tasks/test_tasks.py   (from shell/)
Parsers run over the sample /proc files in fixtures/proc; nothing real is signalled."""
import importlib.machinery, importlib.util, os, shutil, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PROC = os.path.join(HERE, "fixtures", "proc")
os.environ.pop("TASKS_FAKE", None)


def load(name, path):
    loader = importlib.machinery.SourceFileLoader(name, path)
    spec = importlib.util.spec_from_loader(name, loader)
    m = importlib.util.module_from_spec(spec)
    loader.exec_module(m)
    return m


tk = load("tasks", os.path.join(HERE, "tasks.py"))


def rd(*p):
    with open(os.path.join(PROC, *p)) as f:
        return f.read()


def put(path, text):
    with open(path, "w") as f:
        f.write(text)


class Parsers(unittest.TestCase):
    def test_cpu(self):
        total, cores = tk.parse_cpu_stat(rd("stat"))
        self.assertEqual(len(cores), 4)
        self.assertEqual(total, (62738 + 20014 + 108, 62738 + 20014 + 702628 + 2379 + 108))   # busy excludes idle + iowait
        self.assertEqual(cores[0][0], 8775 + 2879 + 4)

    def test_meminfo(self):
        m = tk.parse_meminfo(rd("meminfo"))
        self.assertGreater(m["MemTotal"], 1 << 30)
        mem = tk.memory(m)
        self.assertEqual(mem["used"], m["MemTotal"] - m["MemAvailable"])
        self.assertEqual(mem["swap_used"], m["SwapTotal"] - m["SwapFree"])
        self.assertEqual(tk.parse_meminfo("MemTotal:  10 kB\nHugePages_Total:   5\n"), {"MemTotal": 10240, "HugePages_Total": 5})

    def test_pid_stat(self):
        s = tk.parse_pid_stat(rd("100", "stat"))
        self.assertEqual((s["pid"], s["comm"], s["state"], s["ppid"], s["utime"], s["stime"], s["threads"], s["rss_pages"]),
                         (100, "firefox", "S", 1, 5000, 1200, 42, 25600))
        s = tk.parse_pid_stat(rd("300", "stat"))          # a name with spaces and parentheses
        self.assertEqual((s["comm"], s["state"], s["ppid"], s["threads"]), ("Web Content (x)", "R", 100, 7))
        self.assertIsNone(tk.parse_pid_stat("garbage"))
        self.assertIsNone(tk.parse_pid_stat("1 (x) S 0"))

    def test_status_cmdline(self):
        s = tk.parse_status(rd("100", "status"))
        self.assertEqual((s["name"], s["uid"], s["threads"], s["rss"]), ("firefox", 1000, 42, 102400 * 1024))
        with open(os.path.join(PROC, "100", "cmdline"), "rb") as f:
            self.assertEqual(tk.parse_cmdline(f.read()), "/usr/lib/firefox/firefox --new-window https://example.org")
        self.assertEqual(tk.parse_cmdline(b""), "")

    def test_disk_net_load(self):
        rd_, wr = tk.parse_diskstats(rd("diskstats"), {"nvme0n1"})      # partitions are not counted again
        self.assertEqual((rd_, wr), (4516086 * 512, 6494954 * 512))
        self.assertEqual(tk.parse_diskstats(rd("diskstats"), set()), (0, 0))
        rx, tx = tk.parse_net_dev(rd("net", "dev"))
        self.assertGreater(rx, 0)
        self.assertEqual(tk.parse_net_dev("a\nb\n    lo: 5 0 0 0 0 0 0 0 7 0\n  eth0: 100 0 0 0 0 0 0 0 40 0\n"), (100, 40))
        load, running, total = tk.parse_loadavg("0.52 0.58 0.59 2/1013 14350\n")
        self.assertEqual((load, running, total), ([0.52, 0.58, 0.59], 2, 1013))
        self.assertEqual(tk.parse_uptime("350735.47 234388.90\n"), 350735.47)

    def test_nvidia(self):
        g = tk.parse_nvidia_gpu("NVIDIA GeForce RTX 4070, 33, 1128, 12282, 47, 27.48\n")
        self.assertEqual(g, [{"name": "NVIDIA GeForce RTX 4070", "util": 33.0, "mem_used": 1128 << 20, "mem_total": 12282 << 20,
                              "temp": 47.0, "power": 27.48}])
        g = tk.parse_nvidia_gpu("Some GPU, 5, [N/A], 4096, 40, [Not Supported]")
        self.assertIsNone(g[0]["mem_used"])
        self.assertIsNone(g[0]["power"])
        self.assertEqual(tk.parse_nvidia_gpu(""), [])
        self.assertEqual(tk.parse_nvidia_apps("3421, 420\n3500, 12\n3421, 5\nbad\n"), {3421: 425 << 20, 3500: 12 << 20})

    def test_drm(self):
        d = tempfile.mkdtemp()
        dev = os.path.join(d, "card0", "device")
        os.makedirs(os.path.join(dev, "hwmon", "hwmon3"))
        for n, v in (("gpu_busy_percent", "42"), ("mem_info_vram_used", "1000"), ("mem_info_vram_total", "8000")):
            put(os.path.join(dev, n), v + "\n")
        put(os.path.join(dev, "hwmon", "hwmon3", "temp1_input"), "61000\n")
        g = tk.read_drm(d)
        self.assertEqual((g["util"], g["mem_used"], g["mem_total"], g["temp"], g["power"]), (42.0, 1000, 8000, 61.0, None))
        self.assertIsNone(tk.read_drm(tempfile.mkdtemp()))
        shutil.rmtree(d)


class Windows(unittest.TestCase):
    P = [dict(pid=10, ppid=1, cmd="bwrap --args 72 -- /app/bin/chromium", names={"bwrap"}),
         dict(pid=11, ppid=10, cmd="/app/chromium/chrome --x", names={"chrome", "chromium", "app"}),
         dict(pid=12, ppid=11, cmd="/app/chromium/chrome --type=renderer", names={"chrome", "chromium", "app"}),
         dict(pid=13, ppid=10, cmd="/app/chromium/chrome_crashpad_handler --monitor", names={"chromium", "chrome_crashpad_handler"}),
         dict(pid=20, ppid=1, cmd="qs -p /opt/ultimit/shell", names={"qs"}),
         dict(pid=21, ppid=1, cmd="qs -p /x/claude-shell.qml", names={"qs", "quickshell"}),
         dict(pid=22, ppid=1, cmd="qs -p /x/disks-shell.qml", names={"qs", "quickshell"})]

    def test_main_process_gets_all_titles(self):
        w = [{"app_id": "io.github.ungoogled_software.ungoogled_chromium", "title": "A"},
             {"app_id": "io.github.ungoogled_software.ungoogled_chromium", "title": "B"}]
        self.assertEqual(tk.match_windows(w, self.P), {11: {"app": w[0]["app_id"], "titles": ["A", "B"]}})

    def test_title_picks_among_several(self):
        w = [{"app_id": "org.quickshell", "title": "CLAUDE"}]
        procs = [dict(p, names=p["names"] | {"quickshell"}) for p in self.P]
        self.assertEqual(list(tk.match_windows(w, procs)), [21])
        self.assertEqual(tk.match_windows([{"app_id": "org.quickshell", "title": "Open File"}], procs), {})   # no guess

    def test_no_match(self):
        self.assertEqual(tk.match_windows([{"app_id": "nothing.here", "title": "x"}, {"app_id": "", "title": ""}], self.P), {})

    def test_critical(self):
        c = tk.is_critical
        self.assertTrue(c(1, "systemd", "/sbin/init"))
        self.assertTrue(c(2564, "ultimit", "/opt/ultimit/bin/ultimit -s"))
        self.assertTrue(c(2689, "qs", "qs -p /opt/ultimit/shell"))
        self.assertTrue(c(2667, "ultimit-shell", "/bin/sh /opt/ultimit/session/ultimit-shell"))
        self.assertFalse(c(7173, "qs", "/opt/ultimit/bin/qs -p /opt/ultimit/shell/claude-shell.qml -n -d"))
        self.assertFalse(c(5, "firefox", "/usr/bin/firefox"))


class Sample(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        shutil.copytree(PROC, self.d + "/proc")
        self.root = self.d + "/proc"
        self.s = tk.Sampler(self.root, whole={"nvme0n1"}, clk=100, page=4096,
                            extra={"gpu_apps": {100: 1 << 20}, "windows": [{"app_id": "org.mozilla.firefox", "title": "Example"}]})

    def tearDown(self):
        shutil.rmtree(self.d)

    def test_first_tick_has_no_rates(self):
        t = self.s.tick(now=0.0)
        self.assertEqual((t["cpu"]["total"], t["disk"], t["net"]), (0.0, {"read": 0, "write": 0}, {"rx": 0, "tx": 0}))
        self.assertEqual(t["ncpu"], 4)
        self.assertEqual(t["counts"]["procs"], 3)
        self.assertEqual(t["counts"]["threads"], 42 + 1 + 7)
        by = {p["pid"]: p for p in t["procs"]}
        self.assertEqual(by[100]["name"], "firefox")
        self.assertEqual(by[100]["cmd"], "/usr/lib/firefox/firefox --new-window https://example.org")
        self.assertEqual((by[100]["rss"], by[100]["gpu_mem"]), (25600 * 4096, 1 << 20))
        self.assertEqual(by[100]["app"], "org.mozilla.firefox")      # matched by the executable name
        self.assertEqual(by[100]["titles"], ["Example"])
        self.assertEqual(by[300]["app"], "")                         # a --type= helper never gets a window
        self.assertEqual(by[200]["name"], "[kworker/0:1-eve]")       # kernel thread: no command line
        self.assertEqual(by[200]["user"], tk.Sampler().user(os.getuid()))

    def edit(self, name, fn):
        p = os.path.join(self.root, name)
        with open(p) as f:
            text = f.read()
        os.chmod(p, 0o644)
        with open(p, "w") as f:
            f.write(fn(text))

    def test_rates(self):
        self.s.tick(now=0.0)
        # two seconds later: firefox used 100 more ticks (= half a core), cpu0 +75 busy +25 idle, disk and net moved
        self.edit("100/stat", lambda t: t.replace(" 5000 1200 ", " 5080 1220 "))
        self.edit("stat", lambda t: t.replace("cpu0 8775 0 2879 37287", "cpu0 8825 0 2904 37312")
                  .replace("cpu  62738 0 20014 702628", "cpu  62788 0 20039 702653"))
        self.edit("diskstats", lambda t: t.replace("nvme0n1 49270 24337 4516086 19784 38421 27060 6494954",
                                                   "nvme0n1 49270 24337 4516886 19784 38421 27060 6495954"))
        self.edit("net/dev", lambda t: "Inter-|\n face |\n    lo: 5 0 0 0 0 0 0 0 7 0\n  eth9: 1000 0 0 0 0 0 0 0 500 0\n")
        self.s.prev["net"] = (500, 250)
        t = self.s.tick(now=2.0)
        by = {p["pid"]: p for p in t["procs"]}
        self.assertEqual(by[100]["cpu"], 50.0)                       # 100 ticks over 2 s at 100 Hz
        self.assertEqual(t["cpu"]["total"], 75.0)                    # +75 busy, +25 idle ticks
        self.assertEqual(t["cpu"]["cores"][0], 75.0)
        self.assertEqual(t["disk"], {"read": 400 * 512, "write": 500 * 512})
        self.assertEqual((t["net"]["rx"], t["net"]["tx"]), (250, 125))

    def test_pid_reuse_and_exit(self):
        self.s.tick(now=0.0)
        shutil.rmtree(self.root + "/300")
        # a new start time means a new process under the same PID: no CPU figure from the old one's counters
        self.edit("100/stat", lambda t: t.replace(" 9000 3858432000", " 9999 3858432000").replace(" 5000 1200 ", " 9000 9000 "))
        t = self.s.tick(now=1.0)
        self.assertEqual(t["counts"]["procs"], 2)
        self.assertEqual({q["pid"]: q for q in t["procs"]}[100]["cpu"], 0.0)


class GlanceTick(unittest.TestCase):
    def test_glance(self):
        g = tk.Glance(PROC, extra={"gpu": {"util": 33.0, "mem_used": 1 << 30, "mem_total": 4 << 30}})
        t = g.tick(now=0.0)
        self.assertEqual((t["cpu"], t["rx"], t["tx"]), (0.0, 0, 0))     # the first tick has no rates
        self.assertEqual((t["gpu"], t["vram"]), (33.0, 25.0))
        self.assertTrue(0 < t["mem"] < 100)
        g.prev = (0.0, (0, 0), (0, 0))                                  # then rates, from the previous sample
        t = g.tick(now=2.0)
        self.assertTrue(t["rx"] > 0 and t["cpu"] > 0)
        self.assertIsNone(tk.Glance(PROC).tick(now=1.0)["gpu"])        # no GPU known: null, not an error


class Signals(unittest.TestCase):
    def test_signal(self):
        sent = []
        r = tk.signal_pid(4242, "term", kill=lambda p, s: sent.append((p, int(s))))
        self.assertEqual((r, sent), ({"ok": True}, [(4242, 15)]))
        tk.signal_pid(4242, "SIGKILL", kill=lambda p, s: sent.append((p, int(s))))
        self.assertEqual(sent[-1], (4242, 9))

    def test_refusals(self):
        boom = lambda p, s: self.fail("must not signal")
        self.assertFalse(tk.signal_pid(1, "TERM", kill=boom)["ok"])
        self.assertFalse(tk.signal_pid(0, "TERM", kill=boom)["ok"])
        self.assertFalse(tk.signal_pid(-1, "KILL", kill=boom)["ok"])
        self.assertFalse(tk.signal_pid(5, "HUP", kill=boom)["ok"])
        sent = []
        self.assertTrue(tk.signal_pid(1, "STOP", force=True, kill=lambda p, s: sent.append(p))["ok"])
        self.assertEqual(sent, [1])

    def test_gone_and_polkit(self):
        def gone(p, s): raise ProcessLookupError
        self.assertTrue(tk.signal_pid(9, "TERM", kill=gone)["gone"])

        def eperm(p, s): raise PermissionError
        calls = []
        ok = lambda n, p: calls.append((n, p)) or 0
        self.assertEqual(tk.signal_pid(9, "KILL", kill=eperm, helper=ok), {"ok": True})
        self.assertEqual(calls, [("KILL", 9)])
        self.assertEqual(tk.signal_pid(9, "KILL", kill=eperm, helper=lambda n, p: 126), {"ok": False, "cancelled": True})
        r = tk.signal_pid(9, "KILL", kill=eperm, helper=lambda n, p: 127)
        self.assertFalse(r["ok"])
        self.assertNotIn("cancelled", r)


class Fake(unittest.TestCase):
    def test_fake_tick(self):
        t = tk.FakeSampler().tick()
        self.assertTrue(t["ok"])
        self.assertEqual(len(t["cpu"]["cores"]), t["ncpu"])
        self.assertEqual(t["counts"]["procs"], len(t["procs"]))
        self.assertTrue(any(p["critical"] for p in t["procs"]))


if __name__ == "__main__":
    unittest.main()
