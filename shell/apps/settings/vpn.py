#!/usr/bin/python3 -I
"""vpn.py - VPN profiles for Settings > Network (NetworkManager). One JSON object on stdout.

  vpn.py list                       [{uuid, name, kind: wireguard|openvpn|other, active, user, saved}]
  vpn.py import FILE [NAME]         a WireGuard .conf or an OpenVPN .ovpn file -> a new profile
  vpn.py paste [NAME]               a WireGuard config on stdin -> a new profile
  vpn.py login UUID USER save|ask   OpenVPN sign-in; the password (save) comes on stdin
  vpn.py up UUID | down UUID | delete UUID

Imported profiles never connect by themselves at startup (autoconnect off). A saved password
goes into the keyring (Secret Service, NetworkManager's own schema) as an agent-owned secret:
Ubuntu's netplan-backed NetworkManager can't keep VPN passwords, and the Ultimit secret agent
(bin/ultimit-agents) hands it over at connect. "ask" leaves it out and the agent asks every time.
Passwords never go on a command line.
Test hooks (normal user only): VPN_NMCLI=<program used instead of nmcli>.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

_dev = os.getuid() != 0
NMCLI = (_dev and os.environ.get("VPN_NMCLI")) or "nmcli"
OPENVPN = "org.freedesktop.NetworkManager.openvpn"


def out(o, rc=0):
    sys.stdout.write(json.dumps(o))
    sys.stdout.flush()
    return rc


def nm(*args, stdin=None, timeout=60):
    try:
        p = subprocess.run([NMCLI] + list(args), input=stdin, capture_output=True, text=True, timeout=timeout,
                           env=dict(os.environ, LC_ALL="C"))
    except FileNotFoundError:
        return False, "NetworkManager (nmcli) isn't installed."
    except subprocess.TimeoutExpired:
        return False, "NetworkManager didn't answer in time."
    msg = (p.stdout + "\n" + p.stderr).strip()
    return p.returncode == 0, msg


def last_line(msg):
    lines = [l.strip() for l in msg.splitlines() if l.strip()]
    line = lines[-1] if lines else "NetworkManager refused."
    return re.sub(r"^Error:\s*", "", line)


def kind_of(text):
    if re.search(r"^\s*\[Interface\]", text, re.M | re.I) and re.search(r"^\s*\[Peer\]", text, re.M | re.I):
        return "wireguard"
    if re.search(r"^\s*remote\s+\S+", text, re.M) and re.search(r"^\s*(client|tls-client|dev\s+tun)", text, re.M):
        return "openvpn"
    return ""


def iface_name(name):
    """WireGuard profiles are named after the interface: <=15 chars of [a-z0-9_-]."""
    s = re.sub(r"[^a-z0-9_-]+", "-", name.lower()).strip("-") or "vpn"
    return ("wg-" + s)[:15].rstrip("-")


def split_fields(line):
    """nmcli -t output: ':' separates fields, '\\:' is a literal colon."""
    return [f.replace("\\:", ":").replace("\\\\", "\\") for f in re.split(r"(?<!\\):", line)]


def list_vpns():
    ok, msg = nm("-t", "-f", "NAME,UUID,TYPE,ACTIVE", "connection", "show")
    if not ok:
        return {"ok": False, "error": last_line(msg), "vpns": []}
    vpns = []
    for line in msg.splitlines():
        f = split_fields(line)
        if len(f) < 4 or f[2] not in ("vpn", "wireguard"):
            continue
        v = {"name": f[0], "uuid": f[1], "active": f[3] == "yes", "kind": "wireguard" if f[2] == "wireguard" else "other",
             "user": "", "saved": False}
        if f[2] == "vpn":
            ok2, d = nm("-g", "vpn.service-type,vpn.data", "connection", "show", f[1])
            if ok2:
                parts = d.splitlines()
                if parts and parts[0].strip() == OPENVPN:
                    v["kind"] = "openvpn"
                data = dict(kv.split(" = ", 1) for kv in (parts[1] if len(parts) > 1 else "").split(", ") if " = " in kv)
                v["user"] = data.get("username", "")
                v["saved"] = data.get("password-flags", "") in ("0", "1")
                v["needsLogin"] = data.get("connection-type", "") in ("password", "password-tls")
        vpns.append(v)
    return {"ok": True, "vpns": vpns}


def import_file(path, name=None):
    try:
        with open(path, errors="replace") as f:
            text = f.read(1 << 20)
    except OSError as e:
        return {"ok": False, "error": "Can't read %s: %s" % (path, e.strerror)}
    kind = kind_of(text)
    if not kind:
        return {"ok": False, "error": "That isn't a WireGuard (.conf) or OpenVPN (.ovpn) file."}
    base = name or re.sub(r"\.(conf|ovpn)$", "", os.path.basename(path), flags=re.I)
    with tempfile.TemporaryDirectory() as tmp:
        if kind == "wireguard":
            # nmcli names the interface (and the profile) after the file
            src = os.path.join(tmp, iface_name(base) + ".conf")
        else:
            src = os.path.join(tmp, re.sub(r"[^A-Za-z0-9._-]+", "_", base) + ".ovpn")
            # OpenVPN files may point at keys next to them (ca ca.crt): import from beside the original
            if re.search(r"^\s*(ca|cert|key|tls-auth|tls-crypt)\s+\S+", text, re.M):
                src = path
        if src != path:
            shutil.copyfile(path, src)
            os.chmod(src, 0o600)
        ok, msg = nm("connection", "import", "type", kind, "file", src)
    if not ok:
        if "plugin" in msg.lower() and kind == "openvpn":
            return {"ok": False, "error": "OpenVPN support for NetworkManager isn't installed (network-manager-openvpn)."}
        return {"ok": False, "error": last_line(msg)}
    m = re.search(r"\(([0-9a-f-]{36})\)", msg)
    if not m:
        return {"ok": False, "error": "Imported, but NetworkManager didn't say which profile: " + last_line(msg)}
    uuid = m.group(1)
    nm("connection", "modify", uuid, "connection.id", base, "connection.autoconnect", "no")
    if kind == "wireguard":
        nm("connection", "down", uuid)   # NetworkManager brings an imported WireGuard profile up at once
    login = kind == "openvpn" and re.search(r"^\s*auth-user-pass\b", text, re.M) is not None
    return {"ok": True, "uuid": uuid, "kind": kind, "name": base, "needsLogin": login}


def set_login(uuid, user, save, password):
    """username in vpn.data; the password into the profile's secrets over D-Bus (save) or asked at
    every connect (ask)."""
    import gi
    gi.require_version("Gio", "2.0")
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

    def call(path, iface, method, args, ret):
        return bus.call_sync("org.freedesktop.NetworkManager", path, iface, method, args,
                             GLib.VariantType(ret) if ret else None, Gio.DBusCallFlags.NONE, 30000, None)
    try:
        path = call("/org/freedesktop/NetworkManager/Settings", "org.freedesktop.NetworkManager.Settings",
                    "GetConnectionByUuid", GLib.Variant("(s)", (uuid,)), "(o)").unpack()[0]
        # Keep every value exactly as NetworkManager typed it; only vpn.data and vpn.secrets change.
        reply = call(path, "org.freedesktop.NetworkManager.Settings.Connection", "GetSettings", None, "(a{sa{sv}})")
        groups = reply.get_child_value(0)
        new, data = {}, {}
        for i in range(groups.n_children()):
            g = groups.get_child_value(i)
            gname, vals = g.get_child_value(0).get_string(), g.get_child_value(1)
            new[gname] = {}
            for j in range(vals.n_children()):
                e = vals.get_child_value(j)
                k, v = e.get_child_value(0).get_string(), e.get_child_value(1).get_variant()
                if gname == "vpn" and k == "data":
                    data = v.unpack()
                elif not (gname == "vpn" and k == "secrets"):
                    new[gname][k] = v
        data = dict(data)
        data["username"] = user
        data["password-flags"] = "1" if save else "2"   # 1: agent-owned (keyring), 2: ask every time
        new.setdefault("vpn", {})
        new["vpn"]["data"] = GLib.Variant("a{ss}", data)
        new["vpn"]["secrets"] = GLib.Variant("a{ss}", {})
        call(path, "org.freedesktop.NetworkManager.Settings.Connection", "Update",
             GLib.Variant("(a{sa{sv}})", (new,)), None)
    except GLib.Error as e:
        msg = e.message.split(":")[-1].strip()
        return {"ok": False, "error": "NetworkManager refused: " + msg}
    try:
        gi.require_version("Secret", "1")
        from gi.repository import Secret
        schema = Secret.Schema.new("org.freedesktop.NetworkManager.Connection", Secret.SchemaFlags.DONT_MATCH_NAME,
                                   {"connection-uuid": Secret.SchemaAttributeType.STRING,
                                    "setting-name": Secret.SchemaAttributeType.STRING,
                                    "setting-key": Secret.SchemaAttributeType.STRING})
        attrs = {"connection-uuid": uuid, "setting-name": "vpn", "setting-key": "password"}
        if save and password:
            name = new.get("connection", {}).get("id")
            label = "VPN password for “%s”" % (name.unpack() if name else uuid)
            Secret.password_store_sync(schema, attrs, Secret.COLLECTION_DEFAULT, label, password, None)
        else:
            Secret.password_clear_sync(schema, attrs, None)
    except (ValueError, ImportError):
        return {"ok": False, "error": "Can't reach the keyring (libsecret is missing)."}
    except GLib.Error as e:
        return {"ok": False, "error": "The keyring refused: " + e.message}
    return {"ok": True}


def forget_password(uuid):
    """A removed profile's saved password leaves the keyring too."""
    try:
        import gi
        gi.require_version("Secret", "1")
        from gi.repository import Secret
        schema = Secret.Schema.new("org.freedesktop.NetworkManager.Connection", Secret.SchemaFlags.DONT_MATCH_NAME,
                                   {"connection-uuid": Secret.SchemaAttributeType.STRING,
                                    "setting-name": Secret.SchemaAttributeType.STRING,
                                    "setting-key": Secret.SchemaAttributeType.STRING})
        Secret.password_clear_sync(schema, {"connection-uuid": uuid}, None)
    except Exception:
        pass


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "list"
    a = argv[2:]
    if cmd == "list":
        return out(list_vpns())
    if cmd == "import" and a:
        return out(import_file(a[0], a[1] if len(a) > 1 else None))
    if cmd == "paste":
        text = sys.stdin.read()
        if kind_of(text) != "wireguard":
            return out({"ok": False, "error": "That doesn't look like a WireGuard config ([Interface] and [Peer])."})
        with tempfile.TemporaryDirectory() as tmp:
            f = os.path.join(tmp, "pasted.conf")
            with open(f, "w") as fh:
                fh.write(text)
            os.chmod(f, 0o600)
            return out(import_file(f, a[0] if a else "WireGuard"))
    if cmd == "login" and len(a) == 3 and a[2] in ("save", "ask"):
        pw = sys.stdin.readline().rstrip("\n") if a[2] == "save" else ""
        return out(set_login(a[0], a[1], a[2] == "save", pw))
    if cmd in ("up", "down", "delete") and len(a) == 1:
        ok, msg = nm("connection", cmd, a[0], timeout=90)
        if ok and cmd == "delete":
            forget_password(a[0])
        return out({"ok": True} if ok else {"ok": False, "error": last_line(msg)})
    return out({"ok": False, "error": "usage: vpn.py list | import FILE [NAME] | paste [NAME] | login UUID USER save|ask | up|down|delete UUID"}, 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
