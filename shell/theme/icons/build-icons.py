#!/usr/bin/env python3
"""build-icons.py - build the four Ultimit freedesktop icon themes from SVG templates.

    build-icons.py OUTDIR [--skin mine|amber|silver|verdant|sakura|paper|void] [--sheet FILE.html]

Reads ./templates/<context>/<name>.svg (placeholder colours, see make-templates.py),
substitutes the per-skin palette and writes OUTDIR/Ultimit-<Skin>/ :

    index.theme
    names.json                       name -> relative path, for the Quickshell Icons singleton
    scalable/{apps,places,devices,mimetypes}/NAME.svg
    symbolic/{apps,places,devices}/NAME-symbolic.svg     (recolourable, #bebebe)

Aliases are relative symlinks. Colours mirror shell/Theme.qml (keep in sync).
stdlib only.
"""
import argparse
import json
import os
import shutil
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATES = os.path.join(HERE, "templates")

# accent / fg / dim come from Theme.qml; `fill` is the accent, drawn at `fillop`.
# `folder` is a dedicated folder colour (never orange, even on Amber).
SKINS = {
    "mine":    dict(accent="#d4ebff", fg="#eef1f4", dim="#8d949e", fill="#d4ebff", fillop="0.14",
                    folder="#8ec5f5", panel="#0d0f12", inherits="Yaru-dark,Adwaita,hicolor"),
    "amber":   dict(accent="#ffb04a", fg="#fff4e6", dim="#dcb48c", fill="#ffb04a", fillop="0.15",
                    folder="#f3dcc2", panel="#221105", inherits="Yaru-dark,Adwaita,hicolor"),
    "silver":  dict(accent="#2c5b88", fg="#14171b", dim="#5a626d", fill="#2c5b88", fillop="0.14",
                    folder="#2c5b88", panel="#f8f9fb", inherits="Yaru,Adwaita,hicolor"),
    "verdant": dict(accent="#b9ff8c", fg="#effbe9", dim="#a3cc95", fill="#b9ff8c", fillop="0.15",
                    folder="#8fe3b0", panel="#051408", inherits="Yaru-dark,Adwaita,hicolor"),
    "sakura":  dict(accent="#ff5fa2", fg="#fff0f6", dim="#d29bb6", fill="#ff5fa2", fillop="0.15",
                    folder="#f7b6d0", panel="#1e0915", inherits="Yaru-dark,Adwaita,hicolor"),
    "paper":   dict(accent="#0e7c70", fg="#1e1b15", dim="#675f4e", fill="#0e7c70", fillop="0.14",
                    folder="#0e7c70", panel="#fbf8f1", inherits="Yaru,Adwaita,hicolor"),
    "void":    dict(accent="#4f9dff", fg="#e8ecf2", dim="#7c8596", fill="#4f9dff", fillop="0.15",
                    folder="#7fb6ff", panel="#000000", inherits="Yaru-dark,Adwaita,hicolor"),
}
CONTEXTS = {  # directory -> index.theme Context
    "apps": "Applications", "places": "Places", "devices": "Devices", "mimetypes": "MimeTypes",
}
SYMBOLIC = {"places", "devices", "apps"}
SYMBOLIC_COLOR = "#bebebe"

# alias -> (context, target) ; target is in the same or another context
ALIASES = {
    # apps: freedesktop theme names -> Ultimit art
    ("apps", "utilities-terminal"): ("apps", "ultimit-terminal"),
    ("apps", "foot"): ("apps", "ultimit-terminal"),
    ("apps", "org.codeberg.dnkl.foot"): ("apps", "ultimit-terminal"),
    ("apps", "system-file-manager"): ("apps", "ultimit-data"),
    ("apps", "accessories-text-editor"): ("apps", "ultimit-memo"),
    ("apps", "accessories-calculator"): ("apps", "ultimit-calc"),
    ("apps", "preferences-system"): ("apps", "ultimit-settings"),
    ("apps", "applications-games"): ("apps", "ultimit-games"),
    ("apps", "internet-web-browser"): ("apps", "web-browser"),
    ("apps", "dev.vencord.Vesktop"): ("apps", "ultimit-chat"),
    ("apps", "vesktop"): ("apps", "ultimit-chat"),
    ("apps", "com.discordapp.Discord"): ("apps", "ultimit-chat"),
    ("apps", "discord"): ("apps", "ultimit-chat"),
    ("apps", "application-x-generic"): ("mimetypes", "application-x-executable"),
    # places / devices
    ("devices", "smartphone"): ("devices", "phone"),
    ("devices", "multimedia-player"): ("devices", "phone"),
    ("devices", "drive-removable-media-usb"): ("devices", "drive-removable-media"),
    ("devices", "drive-multidisk"): ("devices", "drive-harddisk"),
    ("devices", "media-optical"): ("devices", "drive-optical"),
    ("devices", "input-tablet"): ("devices", "phone"),
    ("places", "inode-directory"): ("places", "folder"),
    ("places", "folder-visiting"): ("places", "folder-open"),
    ("places", "folder-drag-accept"): ("places", "folder-open"),
    ("places", "network-server"): ("places", "network-workgroup"),
    ("places", "network"): ("places", "network-workgroup"),
    ("places", "start-here"): ("apps", "application-default-icon"),
    # mimetypes
    ("mimetypes", "inode-directory"): ("places", "folder"),
    ("mimetypes", "application-x-shellscript"): ("mimetypes", "text-x-script"),
    ("mimetypes", "text-x-sh"): ("mimetypes", "text-x-script"),
    ("mimetypes", "text-x-csrc"): ("mimetypes", "text-x-script"),
    ("mimetypes", "text-x-chdr"): ("mimetypes", "text-x-script"),
    ("mimetypes", "text-css"): ("mimetypes", "text-html"),
    ("mimetypes", "application-xml"): ("mimetypes", "text-html"),
    ("mimetypes", "text-xml"): ("mimetypes", "text-html"),
    ("mimetypes", "text-csv"): ("mimetypes", "x-office-spreadsheet"),
    ("mimetypes", "application-zip"): ("mimetypes", "application-x-archive"),
    ("mimetypes", "application-gzip"): ("mimetypes", "application-x-archive"),
    ("mimetypes", "application-x-tar"): ("mimetypes", "application-x-archive"),
    ("mimetypes", "application-x-compressed-tar"): ("mimetypes", "application-x-archive"),
    ("mimetypes", "application-x-7z-compressed"): ("mimetypes", "application-x-archive"),
    ("mimetypes", "application-vnd.rar"): ("mimetypes", "application-x-archive"),
    ("mimetypes", "application-x-xz-compressed-tar"): ("mimetypes", "application-x-archive"),
    ("mimetypes", "image-svg+xml"): ("mimetypes", "image-x-generic"),
    ("mimetypes", "application-x-generic"): ("mimetypes", "application-x-executable"),
    ("mimetypes", "application-msword"): ("mimetypes", "x-office-document"),
    ("mimetypes", "application-vnd.oasis.opendocument.text"): ("mimetypes", "x-office-document"),
    ("mimetypes", "application-vnd.oasis.opendocument.spreadsheet"): ("mimetypes", "x-office-spreadsheet"),
    ("mimetypes", "application-vnd.oasis.opendocument.presentation"): ("mimetypes", "x-office-presentation"),
    ("mimetypes", "font-ttf"): ("mimetypes", "font-x-generic"),
    ("mimetypes", "font-otf"): ("mimetypes", "font-x-generic"),
    ("mimetypes", "application-x-sharedlib"): ("mimetypes", "application-x-executable"),
    ("mimetypes", "application-x-pie-executable"): ("mimetypes", "application-x-executable"),
}


def load_templates():
    t = {}
    for ctx in sorted(os.listdir(TEMPLATES)):
        for fn in sorted(os.listdir(os.path.join(TEMPLATES, ctx))):
            if fn.endswith(".svg"):
                with open(os.path.join(TEMPLATES, ctx, fn)) as f:
                    t[(ctx, fn[:-4])] = f.read()
    return t


def subst(text, pal):
    for k in ("accent", "fg", "dim", "fillop", "fill", "folder"):
        text = text.replace("{" + k + "}", pal[k])
    if "{" in text:
        raise ValueError("unresolved placeholder in template: " + text[text.index("{"):][:20])
    return text


def symbolic(text):
    for k in ("accent", "fg", "dim", "folder", "fill"):
        text = text.replace("{" + k + "}", SYMBOLIC_COLOR)
    return text.replace("{fillop}", "0.2")


def rel_link(src_dir, dst_dir, name, ext):
    return os.path.relpath(os.path.join(dst_dir, name + ext), src_dir)


def build(out, skin, templates):
    pal = SKINS[skin]
    root = os.path.join(out, "Ultimit-" + skin.capitalize())
    if os.path.isdir(root):
        shutil.rmtree(root)
    dirs, names = [], {}

    def wr(sub, fname, text):
        d = os.path.join(root, sub)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, fname), "w") as f:
            f.write(text)

    for (ctx, name), tpl in templates.items():
        wr("scalable/" + ctx, name + ".svg", subst(tpl, pal))
        names[name] = "scalable/%s/%s.svg" % (ctx, name)
        if ctx in SYMBOLIC:
            wr("symbolic/" + ctx, name + "-symbolic.svg", symbolic(tpl))
    for (ctx, name), (tctx, target) in ALIASES.items():
        if (tctx, target) not in templates:
            raise KeyError("alias target missing: %s/%s" % (tctx, target))
        d = os.path.join(root, "scalable", ctx)
        os.makedirs(d, exist_ok=True)
        link = os.path.join(d, name + ".svg")
        os.symlink(rel_link(d, os.path.join(root, "scalable", tctx), target, ".svg"), link)
        names[name] = "scalable/%s/%s.svg" % (ctx, name)
        if ctx in SYMBOLIC and (tctx in SYMBOLIC):
            sd = os.path.join(root, "symbolic", ctx)
            os.makedirs(sd, exist_ok=True)
            os.symlink(rel_link(sd, os.path.join(root, "symbolic", tctx), target, "-symbolic.svg"),
                       os.path.join(sd, name + "-symbolic.svg"))

    for kind in ("scalable", "symbolic"):
        for ctx in CONTEXTS:
            if os.path.isdir(os.path.join(root, kind, ctx)):
                dirs.append((kind + "/" + ctx, CONTEXTS[ctx]))
    idx = ["[Icon Theme]", "Name=Ultimit-" + skin.capitalize(),
           "Comment=Ultimit thin-line icons, %s skin" % skin,
           "Inherits=" + pal["inherits"], "Example=folder",
           "Directories=" + ",".join(d for d, _ in dirs), ""]
    for d, c in dirs:
        idx += ["[%s]" % d, "Context=" + c, "Size=48", "MinSize=8", "MaxSize=512", "Type=Scalable", ""]
    with open(os.path.join(root, "index.theme"), "w") as f:
        f.write("\n".join(idx))
    with open(os.path.join(root, "names.json"), "w") as f:
        json.dump({"theme": "Ultimit-" + skin.capitalize(), "icons": names,
                   "aliases": sorted(a for (_, a) in ALIASES) },
                  f, indent=0, sort_keys=True)
    return root


def check(root):
    """Every SVG parses, every dir with SVGs is in index.theme, no dangling links."""
    errs, indexed = [], set()
    with open(os.path.join(root, "index.theme")) as f:
        for line in f:
            if line.startswith("Directories="):
                indexed = set(line.strip().split("=", 1)[1].split(","))
    found, count = set(), 0
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if not fn.endswith(".svg"):
                continue
            p = os.path.join(dp, fn)
            count += 1
            found.add(os.path.relpath(dp, root))
            if not os.path.exists(p):
                errs.append("dangling: " + p)
                continue
            try:
                ET.parse(p)
            except ET.ParseError as e:
                errs.append("%s: %s" % (p, e))
    if found - indexed:
        errs.append("dirs not in index.theme: %s" % sorted(found - indexed))
    if indexed - found:
        errs.append("index.theme lists empty dirs: %s" % sorted(indexed - found))
    return count, errs


def sheet(out, path):
    """HTML contact sheet: every icon at 16/24/48 px on each skin's panel colour."""
    parts = ["<!doctype html><meta charset=utf-8><title>Ultimit icons</title><style>"
             "body{margin:0;font:10px monospace}section{padding:12px}h2{margin:0 0 8px;font:12px monospace}"
             ".g{display:flex;flex-wrap:wrap}.c{width:150px;height:84px;padding:4px;box-sizing:border-box}"
             ".c img{vertical-align:top;margin-right:4px}.c span{display:block;margin-top:4px;opacity:.7}</style>"]
    for skin, pal in SKINS.items():
        theme = "Ultimit-" + skin.capitalize()
        with open(os.path.join(out, theme, "names.json")) as f:
            j = json.load(f)
        al = set(j["aliases"])
        fg = pal["fg"]
        parts.append('<section style="background:%s;color:%s"><h2>%s</h2><div class=g>' % (pal["panel"], fg, theme))
        for name, rel in sorted(j["icons"].items()):
            if name in al:
                continue
            u = "%s/%s" % (theme, rel)
            parts.append('<div class=c><img src="%s" width=48 height=48><img src="%s" width=24 height=24>'
                         '<img src="%s" width=16 height=16><span>%s</span></div>' % (u, u, u, name))
        parts.append("</div></section>")
    with open(path, "w") as f:
        f.write("".join(parts))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("outdir")
    ap.add_argument("--skin", choices=sorted(SKINS), help="build only this skin")
    ap.add_argument("--sheet", metavar="FILE", help="also write an HTML contact sheet (all skins; needs a full build)")
    ap.add_argument("--check", action="store_true", help="validate after building (always on; kept for clarity)")
    a = ap.parse_args()
    tpl = load_templates()
    bad = 0
    for skin in ([a.skin] if a.skin else list(SKINS)):
        root = build(a.outdir, skin, tpl)
        count, errs = check(root)
        print("%s: %d svg files%s" % (root, count, "" if not errs else "  ERRORS"))
        for e in errs:
            print("  " + e, file=sys.stderr)
        bad += len(errs)
    if a.sheet and not a.skin:
        sheet(a.outdir, a.sheet)
        print("contact sheet: " + a.sheet)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
