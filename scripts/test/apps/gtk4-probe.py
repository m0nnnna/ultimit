#!/usr/bin/env python3
# A GTK4/libadwaita test window that belongs to the repo, so the window
# tests don't depend on GNOME apps (purged in phase 4). Like a typical
# GNOME app it draws its own titlebar (CSD header bar) and has a text view
# whose right-click menu is an xdg popup.
#   gtk4-probe.py [TITLE]   (app_id org.ultimit.Probe, one window per run)
import sys
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gio, Gtk


def activate(app):
    win = Adw.ApplicationWindow(application=app, title=sys.argv[1] if len(sys.argv) > 1 else "Probe")
    win.set_default_size(800, 560)
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
    header = Adw.HeaderBar()
    menu = Gio.Menu()
    menu.append("About", "app.about")
    header.pack_end(Gtk.MenuButton(icon_name="open-menu-symbolic", menu_model=menu))
    box.append(header)
    text = Gtk.TextView(monospace=True, left_margin=12, top_margin=12)
    text.get_buffer().set_text("Ultimit test window.\n")
    box.append(Gtk.ScrolledWindow(child=text, vexpand=True))
    win.set_content(box)
    win.present()


app = Adw.Application(application_id="org.ultimit.Probe",
                      flags=Gio.ApplicationFlags.NON_UNIQUE)
app.connect("activate", activate)
app.run([sys.argv[0]])
