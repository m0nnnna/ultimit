#!/usr/bin/python3 -I
"""discord.py - Discord on Ultimit: Vesktop (Discord with Vencord built in, Flathub
dev.vencord.Vesktop) with several accounts signed in at the same time.

Each account is its own Vesktop instance with its own data dir (sign-in, Vencord plugins and
settings), started with Electron's --user-data-dir. Electron's single-instance lock lives in that
dir, so the accounts run side by side; opening an account that is already running brings its
window back. Account 1 uses Vesktop's normal dir, so discord:// links and an existing Vesktop
setup land there.

  discord.py list               JSON: installed, accounts [{id, name, dir, running}]
  discord.py setup              at login: the default accounts (Discord, Discord 2, Discord 3) the
                                first time, a launcher entry per account, the Ultimit theme
  discord.py open ID [URL]      start account ID (or bring its window back); STORE when Vesktop is
                                not installed
  discord.py add [NAME]         a new account (next free number); prints {ok, id}
  discord.py rename ID NAME
  discord.py remove ID          remove the account, its launcher entry and its data (signs it out);
                                not account 1, not while it runs
  discord.py theme              rewrite the Ultimit theme for every account (after a skin change)

Files: ~/.config/ultimit/discord.json (the accounts), launcher entries in
~/.local/share/applications (account 1 overrides the Flatpak's own dev.vencord.Vesktop.desktop,
the others are ultimit-discord-ID.desktop), data in ~/.var/app/dev.vencord.Vesktop/config/vesktop
(account 1) and vesktop-ID. A new account starts with Vesktop's system title bar (the Ultimit
frame), the first-launch tour skipped and the Ultimit theme on; Rich Presence (games shown as your
status) stays on account 1 only, since only one app can hold Discord's RPC socket. Existing
settings files are never changed; the theme file itself follows the skin.
Test hooks: ULTIMIT_DISCORD_FLATPAK=<program used instead of flatpak>.
"""
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys

APP = "dev.vencord.Vesktop"
HERE = os.path.dirname(os.path.abspath(__file__))
SHELL = os.path.normpath(os.path.join(HERE, "../.."))
BIN = os.path.join(SHELL, "bin", "ultimit-discord")
FLATPAK = os.environ.get("ULTIMIT_DISCORD_FLATPAK") or "flatpak"
THEME_FILE = "ultimit.css"
MANAGED = "X-Ultimit-Discord"
HOME = os.path.expanduser("~")
CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
DATA_HOME = os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local/share")
ACCOUNTS_FILE = os.path.join(CONFIG_HOME, "ultimit", "discord.json")
APPS_DIR = os.path.join(DATA_HOME, "applications")
VAR = os.path.join(HOME, ".var/app", APP, "config")
DEFAULT_ACCOUNTS = 3


def out(o, rc=0):
    sys.stdout.write(json.dumps(o) + "\n")
    sys.stdout.flush()
    return rc


def fail(msg):
    return out({"ok": False, "error": msg}, 1)


# ---------------------------------------------------------------------------------- accounts
def default_name(i):
    return "Discord" if i == "1" else "Discord " + i


def load():
    """[{id, name}], in order; None when there is no accounts file yet."""
    try:
        with open(ACCOUNTS_FILE) as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    accs, seen = [], set()
    for a in data.get("accounts", []) if isinstance(data, dict) else []:
        i = str(a.get("id", "")) if isinstance(a, dict) else ""
        if not re.fullmatch(r"[1-9][0-9]{0,2}", i) or i in seen:
            continue
        seen.add(i)
        name = clean_name(a.get("name")) or default_name(i)
        accs.append({"id": i, "name": name})
    if "1" not in seen:
        accs.insert(0, {"id": "1", "name": default_name("1")})
    return accs


def save(accs):
    os.makedirs(os.path.dirname(ACCOUNTS_FILE), exist_ok=True)
    tmp = ACCOUNTS_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"accounts": accs}, f, indent=2)
        f.write("\n")
    os.replace(tmp, ACCOUNTS_FILE)


def accounts():
    accs = load()
    if accs is None:
        accs = [{"id": str(i), "name": default_name(str(i))} for i in range(1, DEFAULT_ACCOUNTS + 1)]
        save(accs)
    return accs


def find(accs, i):
    for a in accs:
        if a["id"] == str(i):
            return a
    return None


def clean_name(name):
    name = re.sub(r"[\x00-\x1f\x7f]", "", str(name or "")).strip()
    return name[:40]


def data_dir(i):
    return os.path.join(VAR, "vesktop" if str(i) == "1" else "vesktop-" + str(i))


def running(i):
    # Electron's single-instance lock: a symlink in the data dir while that instance runs.
    return os.path.lexists(os.path.join(data_dir(i), "SingletonLock"))


def installed():
    try:
        return subprocess.run([FLATPAK, "info", APP], stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL).returncode == 0
    except OSError:
        return False


# ---------------------------------------------------------------------------------- theme
def skin():
    try:
        with open(os.path.join(CONFIG_HOME, "ultimit", "shell.json")) as f:
            s = json.load(f).get("skin", "")
    except (OSError, ValueError, AttributeError):
        s = ""
    s = os.environ.get("ULTIMIT_SKIN") or s
    return s if s in ("mine", "amber", "silver", "verdant") else "mine"


def palette(name):
    # The GTK theme generator holds the skins' palettes (a mirror of Theme.qml): one source.
    path = os.path.join(SHELL, "theme", "gtk", "build-gtk.py")
    spec = importlib.util.spec_from_file_location("ultimit_build_gtk", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.palette(name)


def theme_css(name):
    v = dict(palette(name))
    a = v["accent"]
    v["hover_a"] = "rgba(%d,%d,%d,0.1)" % (int(a[1:3], 16), int(a[3:5], 16), int(a[5:7], 16))
    return THEME % v


# Discord's colour variables, old and "visual refresh" names both (unknown ones are ignored).
# Square corners and the Ultimit fonts for headings and code; message text keeps Discord's font.
THEME = """/**
 * @name Ultimit
 * @description Ultimit's %(Name)s skin for Discord. Written by ultimit-discord at every start; your edits would be overwritten (put them in QuickCSS).
 * @author Ultimit
 * @version 1.0.0
 */
:root, .theme-dark, .theme-darker, .theme-midnight, .theme-light, .visual-refresh,
.visual-refresh.theme-dark, .visual-refresh.theme-light, .visual-refresh .theme-dark, .visual-refresh .theme-light {
    --font-display: "Chakra Petch", "gg sans", sans-serif !important;
    --font-headline: "Michroma", "Chakra Petch", sans-serif !important;
    --font-code: "Share Tech Mono", monospace !important;

    --background-primary: %(bg)s !important;
    --background-secondary: %(side)s !important;
    --background-secondary-alt: %(deep)s !important;
    --background-tertiary: %(deep)s !important;
    --background-floating: %(deep)s !important;
    --background-nested-floating: %(side)s !important;
    --background-accent: %(card)s !important;
    --background-message-hover: %(hover_a)s !important;
    --background-mentioned: %(accent20)s !important;
    --background-mentioned-hover: %(accent40)s !important;
    --background-modifier-hover: %(hover_a)s !important;
    --background-modifier-active: %(accent20)s !important;
    --background-modifier-selected: %(accent20)s !important;
    --background-modifier-accent: %(line)s !important;
    --channeltextarea-background: %(field)s !important;
    --modal-background: %(side)s !important;
    --modal-footer-background: %(deep)s !important;
    --input-background: %(field)s !important;
    --deprecated-card-bg: %(card)s !important;

    --background-base-lowest: %(deep)s !important;
    --background-base-lower: %(side)s !important;
    --background-base-low: %(bg)s !important;
    --background-surface-high: %(card)s !important;
    --background-surface-higher: %(card)s !important;
    --background-surface-highest: %(hover)s !important;
    --bg-base-primary: %(bg)s !important;
    --bg-base-secondary: %(side)s !important;
    --bg-base-tertiary: %(deep)s !important;
    --bg-surface-raised: %(card)s !important;
    --bg-surface-overlay: %(deep)s !important;
    --bg-mod-subtle: %(hover_a)s !important;
    --bg-mod-strong: %(accent20)s !important;
    --bg-brand: %(accent)s !important;
    --background-mod-subtle: %(hover_a)s !important;
    --background-mod-normal: %(accent20)s !important;
    --background-mod-strong: %(accent40)s !important;
    --chat-background-default: %(bg)s !important;
    --app-frame-background: %(deep)s !important;
    --input-background-default: %(field)s !important;
    --panel-bg: %(side)s !important;
    --home-background: %(bg)s !important;

    --text-normal: %(fg)s !important;
    --text-default: %(fg)s !important;
    --text-strong: %(fg)s !important;
    --text-primary: %(fg)s !important;
    --text-secondary: %(dim)s !important;
    --text-muted: %(dim)s !important;
    --text-subtle: %(dim)s !important;
    --text-tertiary: %(dim)s !important;
    --header-primary: %(fg)s !important;
    --header-secondary: %(dim)s !important;
    --text-link: %(accent)s !important;
    --text-brand: %(accent)s !important;
    --channels-default: %(dim)s !important;
    --channel-icon: %(dim)s !important;
    --interactive-normal: %(dim)s !important;
    --interactive-hover: %(fg)s !important;
    --interactive-active: %(fg)s !important;
    --interactive-text-default: %(dim)s !important;
    --interactive-text-hover: %(fg)s !important;
    --interactive-text-active: %(fg)s !important;
    --icon-default: %(dim)s !important;
    --icon-strong: %(fg)s !important;

    --brand-experiment: %(accent)s !important;
    --brand-500: %(accent)s !important;
    --brand-560: %(accent_hover)s !important;
    --brand-600: %(accent_hover)s !important;
    --control-brand-foreground: %(accent)s !important;
    --control-brand-foreground-new: %(accent)s !important;
    --button-filled-brand-background: %(accent)s !important;
    --button-filled-brand-background-hover: %(accent_hover)s !important;
    --button-filled-brand-text: %(on_acc)s !important;
    --control-primary-background-default: %(accent)s !important;
    --control-primary-background-hover: %(accent_hover)s !important;
    --control-primary-text-default: %(on_acc)s !important;

    --border-faint: %(line)s !important;
    --border-subtle: %(line)s !important;
    --border-normal: %(line)s !important;
    --border-strong: %(line2)s !important;
    --status-positive: %(ok)s !important;
    --status-warning: %(warn)s !important;
    --status-danger: %(bad)s !important;
    --text-positive: %(ok)s !important;
    --text-warning: %(warn)s !important;
    --text-danger: %(bad)s !important;
    --scrollbar-thin-thumb: %(line2)s !important;
    --scrollbar-auto-thumb: %(line2)s !important;
    --scrollbar-auto-track: transparent !important;
    --scrollbar-auto-scrollbar-color-thumb: %(line2)s !important;
    --scrollbar-auto-scrollbar-color-track: transparent !important;

    --radius-xs: 0 !important;
    --radius-sm: 2px !important;
    --radius-md: 2px !important;
    --radius-lg: 2px !important;
}
::selection { background: %(selst)s; color: %(fg)s; }
"""


def write_theme(i, css):
    d = os.path.join(data_dir(i), "themes")
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, THEME_FILE)
    try:
        with open(path) as f:
            if f.read() == css:
                return
    except OSError:
        pass
    with open(path + ".tmp", "w") as f:
        f.write(css)
    os.replace(path + ".tmp", path)


def seed_json(path, data):
    """Write `data` to `path` only when the file does not exist yet (the user's settings win)."""
    if os.path.exists(path):
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=4)


def prepare(i, css):
    """A new account's data dir: Ultimit frame, no tour, the theme on. Then the current theme."""
    d = data_dir(i)
    seed_json(os.path.join(d, "settings.json"), {
        "discordBranch": "stable",
        "nativeTitleBar": True,       # the compositor draws the Ultimit title bar and frame
        "minimizeToTray": True,
        "arRPC": str(i) == "1",       # one Rich Presence server: the RPC socket is shared
    })
    seed_json(os.path.join(d, "state.json"), {"firstLaunch": False})
    seed_json(os.path.join(d, "settings", "settings.json"), {"enabledThemes": [THEME_FILE]})
    write_theme(i, css)


# ---------------------------------------------------------------------------------- launcher
def entry_path(i):
    return os.path.join(APPS_DIR, (APP if str(i) == "1" else "ultimit-discord-" + str(i)) + ".desktop")


def entry_text(a):
    i = a["id"]
    lines = [
        "[Desktop Entry]",
        "Type=Application",
        "Name=" + a["name"],
        "GenericName=Discord with Vencord",
        "Comment=Discord account " + i + " (Vesktop). Each account runs on its own, side by side.",
        "Exec=%s open %s%s" % (BIN, i, " %U" if i == "1" else ""),
        "Icon=" + APP,
        "Terminal=false",
        "StartupWMClass=vesktop",
        "Categories=Network;InstantMessaging;Chat;",
        "Keywords=discord;vencord;vesktop;chat;voice;",
    ]
    if i == "1":   # discord:// links (invites, "open in app") go to the first account
        lines.append("MimeType=x-scheme-handler/discord;")
    lines.append(MANAGED + "=" + i)
    return "\n".join(lines) + "\n"


def managed_entries():
    """{path: account id} of the launcher entries this script wrote."""
    found = {}
    try:
        names = os.listdir(APPS_DIR)
    except OSError:
        return found
    for n in names:
        if n != APP + ".desktop" and not n.startswith("ultimit-discord-"):
            continue
        p = os.path.join(APPS_DIR, n)
        try:
            with open(p) as f:
                m = re.search(r"^" + MANAGED + r"=(\S+)$", f.read(), re.M)
        except OSError:
            continue
        if m:
            found[p] = m.group(1)
    return found


def write_entries(accs, present):
    """Launcher entries for `accs` when Vesktop is installed; none (the Flatpak's own) when not."""
    want = {entry_path(a["id"]): entry_text(a) for a in accs} if present else {}
    for p in managed_entries():
        if p not in want:
            os.remove(p)
    os.makedirs(APPS_DIR, exist_ok=True)
    changed = False
    for p, text in want.items():
        try:
            with open(p) as f:
                if f.read() == text:
                    continue
        except OSError:
            pass
        if os.path.exists(p) and p not in managed_entries():
            continue   # the user's own file with that name: leave it
        with open(p + ".tmp", "w") as f:
            f.write(text)
        os.replace(p + ".tmp", p)
        changed = True
    if changed and shutil.which("update-desktop-database"):   # the discord:// handler
        subprocess.run(["update-desktop-database", "-q", APPS_DIR],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


# ---------------------------------------------------------------------------------- commands
def cmd_list():
    accs = load() or [{"id": str(i), "name": default_name(str(i))} for i in range(1, DEFAULT_ACCOUNTS + 1)]
    return out({"ok": True, "installed": installed(), "app": APP,
                "accounts": [dict(a, dir=data_dir(a["id"]), running=running(a["id"])) for a in accs]})


def cmd_setup():
    accs = accounts()
    present = installed()
    write_entries(accs, present)
    if present:
        css = theme_css(skin())
        for a in accs:
            prepare(a["id"], css)
    return out({"ok": True, "installed": present, "accounts": len(accs)})


def cmd_theme():
    accs = load() or []
    css = theme_css(skin())
    for a in accs:
        if os.path.isdir(data_dir(a["id"])):
            write_theme(a["id"], css)
    return out({"ok": True})


def cmd_open(i, url=None):
    accs = accounts()
    if not find(accs, i):
        return fail("No Discord account " + str(i))
    if not installed():
        store = os.path.join(SHELL, "bin", "ultimit-store")
        subprocess.Popen([store, "--app", APP], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return fail("Discord (Vesktop) is not installed")
    prepare(i, theme_css(skin()))
    argv = [FLATPAK, "run", APP]
    if str(i) != "1":
        argv.append("--user-data-dir=" + data_dir(i))
    if url and url.startswith("discord:"):
        argv.append(url)
    os.execvp(argv[0], argv)


def cmd_add(name=None):
    accs = accounts()
    n = str(max(int(a["id"]) for a in accs) + 1)
    if int(n) > 999:
        return fail("Too many accounts")
    accs.append({"id": n, "name": clean_name(name) or default_name(n)})
    save(accs)
    present = installed()
    write_entries(accs, present)
    if present:
        prepare(n, theme_css(skin()))
    return out({"ok": True, "id": n})


def cmd_rename(i, name):
    accs = accounts()
    a = find(accs, i)
    name = clean_name(name)
    if not a:
        return fail("No Discord account " + str(i))
    if not name:
        return fail("Enter a name")
    a["name"] = name
    save(accs)
    write_entries(accs, installed())
    return out({"ok": True})


def cmd_remove(i):
    accs = accounts()
    if str(i) == "1":
        return fail("The first account stays (discord:// links open in it); rename it instead")
    if not find(accs, i):
        return fail("No Discord account " + str(i))
    if running(i):
        return fail("That account is running; quit it first (tray icon › Quit)")
    accs = [a for a in accs if a["id"] != str(i)]
    save(accs)
    write_entries(accs, installed())
    shutil.rmtree(data_dir(i), ignore_errors=True)
    return out({"ok": True})


def main(argv):
    cmd, args = (argv[0] if argv else "list"), argv[1:]
    if cmd == "list":
        return cmd_list()
    if cmd == "setup":
        return cmd_setup()
    if cmd == "theme":
        return cmd_theme()
    if cmd == "open":
        return cmd_open(args[0] if args else "1", args[1] if len(args) > 1 else None)
    if cmd == "add":
        return cmd_add(" ".join(args) or None)
    if cmd == "rename" and len(args) >= 2:
        return cmd_rename(args[0], " ".join(args[1:]))
    if cmd == "remove" and args:
        return cmd_remove(args[0])
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
