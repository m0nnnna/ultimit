#!/usr/bin/python3 -I
"""audio.py - display audio for Settings > Sound (PipeWire). One JSON object on stdout.

  audio.py list            {ok, cards: [{id, name, outputs: [{index, label, kind, connected, active}]}]}
  audio.py set ID INDEX    switch card ID to profile INDEX (wpctl set-profile), then make that
                           card's sink the default output unless Easy Effects is the default

A graphics card has one HDMI/DisplayPort audio output per connector, but plays through only one
at a time (the card's profile). WirePlumber picks one by itself, often not the screen with
speakers; this lists them by monitor name so the user can pick. Only cards with HDMI profiles
are listed: analog cards already show up as outputs.
Test hooks (normal user only): AUDIO_PWDUMP=<program used instead of pw-dump>,
AUDIO_WPCTL=<program used instead of wpctl>.
"""
import json
import os
import subprocess
import sys
import time

_dev = os.getuid() != 0
PWDUMP = (_dev and os.environ.get("AUDIO_PWDUMP")) or "pw-dump"
WPCTL = (_dev and os.environ.get("AUDIO_WPCTL")) or "wpctl"
EE_SINK = "easyeffects_sink"


def out(o, rc=0):
    sys.stdout.write(json.dumps(o))
    sys.stdout.flush()
    return rc


def run(argv, timeout=8):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, env=dict(os.environ, LC_ALL="C"))
    except FileNotFoundError:
        return 127, "", argv[0] + " isn't installed."
    except subprocess.TimeoutExpired:
        return 124, "", "PipeWire didn't answer in time."
    return p.returncode, p.stdout, p.stderr


def dump():
    rc, o, err = run([PWDUMP])
    if rc != 0:
        return None, (err.strip() or "pw-dump failed.")
    try:
        d = json.loads(o)
    except ValueError:
        return None, "pw-dump printed something that isn't JSON."
    return (d if isinstance(d, list) else []), ""


def info_pairs(route):
    """A route's `info` is [count, key, value, key, value, ...] -> dict."""
    i = route.get("info")
    if not isinstance(i, list) or not i:
        return {}
    flat = i[1:] if isinstance(i[0], int) else i
    return {str(flat[k]): str(flat[k + 1]) for k in range(0, len(flat) - 1, 2)}


def kind_of(profile_name):
    if "surround71" in profile_name:
        return "7.1 surround"
    if "surround" in profile_name:
        return "5.1 surround"
    return "Stereo"


def connected_of(available):
    return {"yes": True, "no": False}.get(available)   # "unknown" -> None


def cards(d):
    res = []
    for o in d:
        inf = o.get("info") or {}
        props = inf.get("props") or {}
        if o.get("type") != "PipeWire:Interface:Device" or props.get("media.class") != "Audio/Device":
            continue
        params = inf.get("params") or {}
        profiles = [p for p in params.get("EnumProfile") or [] if isinstance(p, dict)]
        hdmi = [p for p in profiles if str(p.get("name", "")).startswith("output:hdmi")]
        if not hdmi:
            continue
        cur = (params.get("Profile") or [{}])[0] or {}
        routes = [r for r in params.get("EnumRoute") or [] if isinstance(r, dict) and r.get("direction") == "Output"]
        # profile index -> the connector (route) it plays to
        by_profile = {}
        for n, r in enumerate(routes):
            for idx in r.get("profiles") or []:
                by_profile.setdefault(idx, (n, r))
        outputs = []
        for p in hdmi:
            n, r = by_profile.get(p.get("index"), (None, {}))
            ip = info_pairs(r)
            monitor = ip.get("device.product.name") or ""
            port = r.get("description") or p.get("description") or p.get("name")
            if n is not None and not monitor and len([x for x in routes if x.get("description") == port]) > 1:
                port = "%s %d" % (port, n + 1)
            avail = r.get("available") if r else p.get("available")
            outputs.append({"index": p.get("index"), "label": monitor or port, "port": port,
                            "kind": kind_of(str(p.get("name", ""))), "connected": connected_of(avail),
                            "active": p.get("index") == cur.get("index")})
        # screens that are plugged in first, then by connector; stereo before surround on each
        rank = {True: 0, None: 1, False: 2}
        outputs.sort(key=lambda x: (rank[x["connected"]], x["port"], x["kind"] != "Stereo", x["kind"]))
        res.append({"id": o.get("id"), "name": props.get("device.description") or props.get("device.name") or "",
                    "outputs": outputs})
    return res


def default_sink_name(d):
    for o in d:
        if o.get("type") != "PipeWire:Interface:Metadata":
            continue
        for m in o.get("metadata") or []:
            v = m.get("value")
            if m.get("key") == "default.audio.sink" and isinstance(v, dict):
                return v.get("name")
    return None


def card_sink(d, card_id):
    for o in d:
        props = (o.get("info") or {}).get("props") or {}
        if props.get("media.class") == "Audio/Sink" and str(props.get("device.id")) == str(card_id):
            return o.get("id")
    return None


def cmd_list():
    d, err = dump()
    if d is None:
        return out({"ok": False, "error": err, "cards": []})
    return out({"ok": True, "cards": cards(d)})


def cmd_set(card_id, index, wait=3.0):
    rc, _, err = run([WPCTL, "set-profile", str(card_id), str(index)])
    if rc != 0:
        return out({"ok": False, "error": err.strip() or "Couldn't switch the output."}, 1)
    # the card's sink is recreated for the new profile; wait for it, then make it the default
    time.sleep(0.5)
    deadline = time.monotonic() + wait
    while True:
        d, _ = dump()
        sink = card_sink(d or [], card_id)
        if sink is not None or time.monotonic() >= deadline:
            break
        time.sleep(0.25)
    if sink is None:
        return out({"ok": True, "default": False})
    if default_sink_name(d) == EE_SINK:   # noise removal: Easy Effects stays the default
        return out({"ok": True, "default": False, "easyEffects": True})
    rc, _, err = run([WPCTL, "set-default", str(sink)])
    return out({"ok": True, "default": rc == 0})


def main(argv):
    if argv[:1] == ["list"]:
        return cmd_list()
    if len(argv) == 3 and argv[0] == "set" and argv[1].isdigit() and argv[2].isdigit():
        return cmd_set(int(argv[1]), int(argv[2]))
    return out({"ok": False, "error": "usage: audio.py list | set ID INDEX"}, 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
