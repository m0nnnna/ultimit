#!/usr/bin/env python3
"""Mock org.bluez + org.freedesktop.NetworkManager for testing bin/ultimit-agents.

Run it on a PRIVATE bus only (see scripts/test/agents/; never the system bus) (ULTIMIT_AGENTS_BUS == the bus address used here):
  agents-mock.py <bus-address>
It accepts agent registration like the real managers, and exposes a control interface
(name org.ultimit.Mock, path /mock) so the test script can make it call the agent:
  Call(s service, s method, s args_json) -> s     service: bluez|nm
  State() -> s                                    registration counters
  Bluez(b up)                                     stop/start owning org.bluez (restart test)
  Nm(b up)
The reply is JSON {"ok": <value>} or {"err": "<dbus error name>"}.
"""
import json, warnings
warnings.simplefilter("ignore")
import sys

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

addr = sys.argv[1]
conn = Gio.DBusConnection.new_for_address_sync(
    addr, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION,
    None, None)
loop = GLib.MainLoop()
st = {"bz_reg": 0, "bz_default": 0, "bz_unreg": 0, "nm_reg": 0, "nm_unreg": 0,
      "bz_agent": None, "nm_agent": None, "nm_caps": None, "nm_id": None}
names = {}

BZ_SIGS = {  # method -> (in signature, out signature)
    "Release": ("", ""), "RequestPinCode": ("(o)", "(s)"), "DisplayPinCode": ("(os)", ""),
    "RequestPasskey": ("(o)", "(u)"), "DisplayPasskey": ("(ouq)", ""),
    "RequestConfirmation": ("(ou)", ""), "RequestAuthorization": ("(o)", ""),
    "AuthorizeService": ("(os)", ""), "Cancel": ("", "")}
DEV_PROPS = {}   # object path -> props dict


def bz_mgr(c, sender, path, iface, method, params, inv):
    if method == "RegisterAgent":
        p, cap = params.unpack()
        st["bz_reg"] += 1; st["bz_agent"] = (sender, p, cap)
    elif method == "RequestDefaultAgent":
        st["bz_default"] += 1
    elif method == "UnregisterAgent":
        st["bz_unreg"] += 1
    inv.return_value(None)


def dev_props(c, sender, path, iface, method, params, inv):
    if method == "GetAll":
        props = DEV_PROPS.get(path)
        if props is None:
            inv.return_dbus_error("org.freedesktop.DBus.Error.UnknownObject", "no device")
            return
        inv.return_value(GLib.Variant("(a{sv})", ({k: v for k, v in props.items()},)))
    else:
        inv.return_value(None)


def nm_mgr(c, sender, path, iface, method, params, inv):
    if method == "RegisterWithCapabilities":
        ident, caps = params.unpack()
        st["nm_reg"] += 1; st["nm_agent"] = sender; st["nm_id"] = ident; st["nm_caps"] = caps
    elif method == "Unregister":
        st["nm_unreg"] += 1
    inv.return_value(None)


def node(xml):
    return Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0]


conn.register_object("/org/bluez", node(
    '<node><interface name="org.bluez.AgentManager1"><method name="RegisterAgent">'
    '<arg type="o" direction="in"/><arg type="s" direction="in"/></method>'
    '<method name="UnregisterAgent"><arg type="o" direction="in"/></method>'
    '<method name="RequestDefaultAgent"><arg type="o" direction="in"/></method></interface></node>'),
    bz_mgr, None, None)
for dev in ("dev_AA_BB_CC_DD_EE_01", "dev_AA_BB_CC_DD_EE_02"):
    conn.register_object("/org/bluez/hci0/" + dev, node(
        '<node><interface name="org.freedesktop.DBus.Properties"><method name="GetAll">'
        '<arg type="s" direction="in"/><arg type="a{sv}" direction="out"/></method></interface></node>'),
        dev_props, None, None)
DEV_PROPS["/org/bluez/hci0/dev_AA_BB_CC_DD_EE_01"] = {
    "Alias": GLib.Variant("s", "Mock Keyboard"), "Address": GLib.Variant("s", "AA:BB:CC:DD:EE:01"),
    "Paired": GLib.Variant("b", False), "Trusted": GLib.Variant("b", False)}
DEV_PROPS["/org/bluez/hci0/dev_AA_BB_CC_DD_EE_02"] = {
    "Alias": GLib.Variant("s", "Trusted Phone"), "Address": GLib.Variant("s", "AA:BB:CC:DD:EE:02"),
    "Paired": GLib.Variant("b", True), "Trusted": GLib.Variant("b", True)}
conn.register_object(NM_MGR := "/org/freedesktop/NetworkManager/AgentManager", node(
    '<node><interface name="org.freedesktop.NetworkManager.AgentManager">'
    '<method name="RegisterWithCapabilities"><arg type="s" direction="in"/><arg type="u" direction="in"/></method>'
    '<method name="Unregister"/></interface></node>'), nm_mgr, None, None)


def own(name):
    names[name] = Gio.bus_own_name_on_connection(conn, name, Gio.BusNameOwnerFlags.NONE, None, None)


def unown(name):
    if name in names:
        Gio.bus_unown_name(names.pop(name))


def vfrom(sig, args):
    """JSON args -> GLib.Variant of tuple type `sig`. Special: connection dicts as-is."""
    return GLib.Variant(sig, tuple(args))


def conn_variant(d):
    """{setting: {key: ["s"|"ay"|..., value]}} -> a{sa{sv}}"""
    out = {}
    for s, kv in d.items():
        out[s] = {k: GLib.Variant(t, v) for k, (t, v) in kv.items()}
    return out


def do_call(service, method, a, inv):
    def cb(c, res):
        try:
            r = c.call_finish(res).unpack()
            if method == "GetSecrets":
                r = {s: {k: (v if not isinstance(v, bytes) else v.decode()) for k, v in kv.items()}
                     for s, kv in r[0].items()}
            elif len(r) == 1:
                r = r[0]
            else:
                r = None
            out = {"ok": r}
        except GLib.Error as e:
            out = {"err": Gio.DBusError.get_remote_error(e) or e.message}
        inv.return_value(GLib.Variant("(s)", (json.dumps(out),)))
    if service == "bluez":
        sender, path, _ = st["bz_agent"]
        sig = BZ_SIGS[method][0] or None
        params = GLib.Variant(sig, tuple(a)) if sig else None
        conn.call(sender, path, "org.bluez.Agent1", method, params, None,
                  Gio.DBusCallFlags.NONE, 120000, None, cb)
    else:
        sender = st["nm_agent"]
        p = "/org/freedesktop/NetworkManager/SecretAgent"
        if method == "GetSecrets":
            params = GLib.Variant("(a{sa{sv}}osasu)", (conn_variant(a[0]), a[1], a[2], a[3], a[4]))
        elif method == "CancelGetSecrets":
            params = GLib.Variant("(os)", tuple(a))
        else:
            params = GLib.Variant("(a{sa{sv}}o)", (conn_variant(a[0]), a[1]))
        conn.call(sender, p, "org.freedesktop.NetworkManager.SecretAgent", method, params, None,
                  Gio.DBusCallFlags.NONE, 120000, None, cb)


def ctl(c, sender, path, iface, method, params, inv):
    if method == "Call":
        service, m, a = params.unpack()
        try:
            do_call(service, m, json.loads(a), inv)
        except Exception as e:
            inv.return_value(GLib.Variant("(s)", (json.dumps({"err": "mock:" + repr(e)}),)))
    elif method == "State":
        inv.return_value(GLib.Variant("(s)", (json.dumps(st),)))
    elif method in ("Bluez", "Nm"):
        up = params.unpack()[0]
        name = "org.bluez" if method == "Bluez" else "org.freedesktop.NetworkManager"
        (own if up else unown)(name)
        inv.return_value(None)


conn.register_object("/mock", node(
    '<node><interface name="org.ultimit.Mock"><method name="Call"><arg type="s" direction="in"/>'
    '<arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="s" direction="out"/></method>'
    '<method name="State"><arg type="s" direction="out"/></method>'
    '<method name="Bluez"><arg type="b" direction="in"/></method>'
    '<method name="Nm"><arg type="b" direction="in"/></method></interface></node>'), ctl, None, None)
own("org.bluez"); own("org.freedesktop.NetworkManager"); own("org.ultimit.Mock")
print("mock ready", flush=True)
loop.run()
