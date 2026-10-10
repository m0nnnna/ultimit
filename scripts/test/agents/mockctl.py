#!/usr/bin/env python3
"""mockctl.py <bus> call <bluez|nm> <Method> '<args json>'   |  state | bluez 0/1 | nm 0/1"""
import sys, gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib
c = Gio.DBusConnection.new_for_address_sync(sys.argv[1], Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
def call(m, p, t):
    return c.call_sync("org.ultimit.Mock", "/mock", "org.ultimit.Mock", m, p, t, Gio.DBusCallFlags.NONE, 130000, None)
cmd = sys.argv[2]
if cmd == "call":
    print(call("Call", GLib.Variant("(sss)", tuple(sys.argv[3:6])), GLib.VariantType("(s)")).unpack()[0])
elif cmd == "state":
    print(call("State", None, GLib.VariantType("(s)")).unpack()[0])
else:
    call({"bluez": "Bluez", "nm": "Nm"}[cmd], GLib.Variant("(b)", (sys.argv[3] == "1",)), None)
