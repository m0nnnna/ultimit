pragma Singleton

// Frames.qml - photo frames: pictures left on the desktop (components/PhotoFrame.qml, drawn by
// Wallpaper on the background layer, under every window). Each one is
//   { id, path, screen, x, y, w, h, locked }
// x/y are the frame's top-left on that screen, w/h the picture's size (h 0 = not known yet: the
// frame takes it from the picture's aspect once it loads). A locked frame can't be moved or resized.
// Saved in shell.json ("frames", see Persist.qml). Frames on an unplugged screen are kept and come
// back with it.

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var list: []
    // Frame ids, changed only when a frame is added or removed, so Wallpaper's Repeater keeps its
    // frames (and their loaded pictures) while one is moved or resized.
    property var ids: []

    readonly property int defaultWidth: 360
    readonly property int minSize: 80
    readonly property var imageRe: /\.(jpe?g|jfif|png|webp|gif|bmp|avif|heic|jxl|tiff?)$/i

    function isImage(path) { return typeof path === "string" && path.startsWith("/") && imageRe.test(path); }

    // Settings file -> frames: keep well-formed entries only.
    function clean(arr) {
        const out = [];
        for (const f of (arr || [])) {   // a JsonAdapter list is no Array.isArray() array
            if (!f || typeof f.id !== "string" || f.id === "" || !isImage(f.path)) continue;
            if (out.some(o => o.id === f.id)) continue;
            out.push({ id: f.id, path: f.path, screen: typeof f.screen === "string" ? f.screen : "",
                       x: Math.round(+f.x || 0), y: Math.round(+f.y || 0),
                       w: Math.max(minSize, Math.round(+f.w || defaultWidth)), h: Math.max(0, Math.round(+f.h || 0)),
                       locked: !!f.locked });
        }
        return out;
    }
    function set(arr) { list = arr; ids = arr.map(f => f.id); }

    function byId(id) { return list.find(f => f.id === id) || null; }
    function newId() { return Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36); }

    // A new frame on screen `screen` ("" = the main one) with its top-left at x, y (-1 = centred).
    function add(path, screen, x, y) {
        if (!isImage(path)) return "";
        let name = screen || "";
        const scr = Quickshell.screens.find(s => s.name === name)
                 || Quickshell.screens.find(s => Config.isMainScreen(s.name)) || Quickshell.screens[0];
        if (scr) name = scr.name;
        const w = defaultWidth;
        const step = 32 * (list.filter(o => o.screen === name).length % 8);   // centred ones fan out
        const px = x >= 0 ? x : (scr ? Math.round((scr.width - w) / 2) : 200) + step;
        const py = y >= 0 ? y : (scr ? Math.round((scr.height - w) / 2) : 200) + step;
        const f = { id: newId(), path: path, screen: name, x: Math.round(px), y: Math.round(py), w: w, h: 0, locked: false };
        set(list.concat([f]));
        return f.id;
    }
    function update(id, changes) {
        let hit = false;
        const out = list.map(f => { if (f.id !== id) return f; hit = true; return Object.assign({}, f, changes); });
        if (hit) list = out;
        return hit;
    }
    function remove(id) {
        if (!byId(id)) return false;
        set(list.filter(f => f.id !== id));
        return true;
    }
    function setLocked(id, on) { return update(id, { locked: !!on }); }
    // A new picture keeps the frame's longer side; its height comes from the picture (h 0).
    function setPicture(id, path) {
        const f = byId(id);
        return !!f && isImage(path) && update(id, { path: path, w: Math.max(f.w, f.h), h: 0 });
    }
    function openInImage(id) {
        const f = byId(id);
        if (f) Quickshell.execDetached([Quickshell.shellPath("bin/ultimit-image"), f.path]);
    }

    // "Add photo frame…" / "Change picture…": pick a picture with zenity, then add a frame at
    // (x, y) on `screen`, or give frame `replace` the new picture.
    property var pickFor: null
    function pick(screen, x, y, replace) {
        if (picker.running) return;
        pickFor = { screen: screen || "", x: x, y: y, replace: replace || "" };
        picker.running = true;
    }
    Process {
        id: picker
        command: ["sh", "-c", 'cd "$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME")" 2>/dev/null; exec zenity --file-selection '
            + '--title="Choose a picture for the frame" --filename="$PWD/" '
            + '"--file-filter=Pictures | *.jpg *.jpeg *.png *.webp *.gif *.bmp *.avif *.JPG *.JPEG *.PNG *.WEBP *.GIF"']
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim(), r = root.pickFor;
                root.pickFor = null;
                if (!r || !root.isImage(p)) return;
                if (r.replace !== "") root.setPicture(r.replace, p);
                else root.add(p, r.screen, r.x, r.y);
            }
        }
    }
}
