// ImageWindow.qml - one IMAGE window: a picture and the others in its folder (or the set it was opened
// with), with zoom, pan and rotate. A normal xdg toplevel (the compositor draws the frame).
// Created by ImageApp.qml through a Variants over Viewer.ids.
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../.."
import "../accessory"

FloatingWindow {
    id: win
    required property int winId

    // ---- what is shown ----
    property var files: []              // [{ p, n, size, mtime }] from image.py
    property int index: 0
    property string err: ""             // folder/listing error (nothing to show)
    property bool listing: true
    readonly property var cur: index >= 0 && index < files.length ? files[index] : null
    readonly property string path: cur ? cur.p : ""
    readonly property string name: cur ? cur.n : ""
    readonly property string ext: path.substring(path.lastIndexOf(".") + 1).toLowerCase()
    readonly property bool anim: ext === "gif" || ext === "webp"   // AnimatedImage plays them (one frame is fine too)

    title: (name !== "" ? name + " — " : "") + "IMAGE"
    implicitWidth: 1040
    implicitHeight: 720
    minimumSize: Qt.size(420, 300)
    color: Theme.bg1
    visible: true

    // ---- view state (reset for every picture) ----
    property bool fit: true             // shrink to the window (never enlarged past 100 %)
    property real zoom: 1               // used when !fit
    property int rot: 0                 // 0 / 90 / 180 / 270, view only (the file is never changed)
    property bool bars: true            // toolbar + status line (Tab hides them)
    property string overlay: ""         // "", "trash"
    property string flash: ""           // short note in the corner ("Copied", ...)
    property bool closing: false

    readonly property Item pic: anim ? animPic : stillPic
    readonly property real natW: pic.implicitWidth
    readonly property real natH: pic.implicitHeight
    readonly property bool sideways: rot === 90 || rot === 270
    readonly property real rotW: sideways ? natH : natW
    readonly property real rotH: sideways ? natW : natH
    readonly property real fitScale: rotW > 0 && rotH > 0 ? Math.min(1, flick.width / rotW, flick.height / rotH) : 1
    readonly property real viewScale: fit ? fitScale : zoom
    readonly property bool ready: pic.status === Image.Ready && natW > 0

    function fileUrl(p) { return p === "" ? "" : "file://" + p.split("/").map(encodeURIComponent).join("/"); }

    // ---- loading ----
    function show(o) {
        listing = false;
        if (!o.ok) { err = o.err || "Cannot open"; files = []; return; }
        err = "";
        files = o.files;
        index = o.index;
    }
    Component.onCompleted: {
        const req = Viewer.requests[winId] || {};
        if (req.set) Viewer.run(["set"].concat(req.set), show);
        else Viewer.run(["list", req.path || ""], show);
    }
    onPathChanged: {
        fit = true; zoom = 1; rot = 0;
        Viewer.setCurrent(winId, path);
        Qt.callLater(() => { win.preNext = win.neighbour(1); win.preBack = win.neighbour(-1); });
    }
    function neighbour(d) { return files.length > 1 ? fileUrl(files[(index + d + files.length) % files.length].p) : ""; }
    // Decoded neighbours, so stepping through a folder does not wait on the disk. Set one tick after the
    // picture changes, so the main view picks the decoded image up before these let go of it.
    property string preNext: ""
    property string preBack: ""

    // ---- browsing ----
    function go(d) {
        if (files.length < 2 || overlay !== "") return;
        index = (index + d + files.length) % files.length;
    }
    function goTo(i) { if (files.length && overlay === "") index = Math.max(0, Math.min(files.length - 1, i)); }

    // ---- zoom ----
    function clampZoom(z) { return Math.max(0.02, Math.min(32, z)); }
    // Zoom by `factor`, keeping the picture point under (px, py) (viewport coordinates) where it is.
    function zoomAt(factor, px, py) {
        if (!ready) return;
        const s0 = viewScale, s1 = clampZoom(s0 * factor);
        if (s1 === s0 && !fit) return;
        const ox0 = (flick.contentWidth - rotW * s0) / 2, oy0 = (flick.contentHeight - rotH * s0) / 2;
        const ix = (flick.contentX + px - ox0) / s0, iy = (flick.contentY + py - oy0) / s0;
        fit = false;
        zoom = s1;
        const cw = Math.max(flick.width, rotW * s1), ch = Math.max(flick.height, rotH * s1);
        const ox1 = (cw - rotW * s1) / 2, oy1 = (ch - rotH * s1) / 2;
        flick.contentX = Math.max(0, Math.min(cw - flick.width, ox1 + ix * s1 - px));
        flick.contentY = Math.max(0, Math.min(ch - flick.height, oy1 + iy * s1 - py));
    }
    function zoomStep(dir) { zoomAt(dir > 0 ? 1.25 : 0.8, flick.width / 2, flick.height / 2); }
    function actualSize(px, py) {
        if (!ready) return;
        zoomAt(1 / viewScale, px === undefined ? flick.width / 2 : px, py === undefined ? flick.height / 2 : py);
    }
    function toggleFit(px, py) { if (fit && fitScale < 1) actualSize(px, py); else fit = true; }
    function rotate(d) { rot = (rot + d + 360) % 360; fit = true; }

    // ---- actions ----
    function say(t) { flash = t; flashTimer.restart(); }
    Timer { id: flashTimer; interval: 1600; onTriggered: win.flash = "" }
    readonly property var mimes: ({ png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", jpe: "image/jpeg", jfif: "image/jpeg",
                                    gif: "image/gif", webp: "image/webp", bmp: "image/bmp", svg: "image/svg+xml", tif: "image/tiff",
                                    tiff: "image/tiff", avif: "image/avif", heic: "image/heic", jxl: "image/jxl", ico: "image/x-icon" })
    function copyImage() {
        if (path === "") return;
        const m = mimes[ext];
        if (m) Quickshell.execDetached(["sh", "-c", 'exec wl-copy --type "$1" <"$2"', "sh", m, path]);
        else Quickshell.execDetached(["wl-copy", "--type", "text/uri-list", fileUrl(path)]);
        say(m ? "Image copied" : "File copied");
    }
    function setWallpaper() {
        if (path === "") return;
        Quickshell.execDetached([Quickshell.shellPath("bin/ultimit-wallpaper"), path]);
        say("Set as wallpaper");
    }
    function showInFolder() { if (path !== "") Quickshell.execDetached([Quickshell.shellPath("bin/ultimit-data"), "--reveal", path]); }
    function trash() {
        const p = path;
        overlay = "";
        Viewer.run(["trash", p], o => {
            if (!o.ok) { win.say("Not moved: " + o.err); return; }
            const f = win.files.filter(e => e.p !== p);
            if (f.length === 0) { win.doClose(); return; }
            const i = Math.min(win.index, f.length - 1);
            win.files = f;
            win.index = i;
            win.say("Moved to the Trash");
        });
    }

    function doClose() { closing = true; visible = false; Viewer.closeWin(winId); }
    onClosed: if (!closing) doClose()

    Connections {
        target: Viewer
        function onRaiseChanged() { if (Viewer.raiseId === win.winId) keys.forceActiveFocus(); }
    }

    // ---- shortcuts ----
    Item {
        id: keys
        width: 0; height: 0
        focus: true
        readonly property bool active: win.overlay === ""
        Shortcut { sequences: ["Right", "Space", "PgDown", "N"]; enabled: keys.active; onActivated: win.go(1) }
        Shortcut { sequences: ["Left", "Backspace", "PgUp", "P"]; enabled: keys.active; onActivated: win.go(-1) }
        Shortcut { sequences: ["Home"]; enabled: keys.active; onActivated: win.goTo(0) }
        Shortcut { sequences: ["End"]; enabled: keys.active; onActivated: win.goTo(win.files.length - 1) }
        Shortcut { sequences: ["+", "=", "Ctrl+=", "Ctrl++"]; enabled: keys.active; onActivated: win.zoomStep(1) }
        Shortcut { sequences: ["-", "Ctrl+-"]; enabled: keys.active; onActivated: win.zoomStep(-1) }
        Shortcut { sequences: ["0", "Ctrl+0"]; enabled: keys.active; onActivated: win.fit = true }
        Shortcut { sequences: ["1"]; enabled: keys.active; onActivated: win.actualSize() }
        Shortcut { sequences: ["R"]; enabled: keys.active; onActivated: win.rotate(90) }
        Shortcut { sequences: ["Shift+R"]; enabled: keys.active; onActivated: win.rotate(-90) }
        Shortcut { sequences: ["Ctrl+C"]; enabled: keys.active; onActivated: win.copyImage() }
        Shortcut { sequences: ["Delete"]; enabled: keys.active && win.path !== ""; onActivated: win.overlay = "trash" }
        Shortcut { sequences: ["Tab"]; enabled: keys.active; onActivated: win.bars = !win.bars }
        Shortcut { sequences: ["K"]; enabled: keys.active && win.anim; onActivated: animPic.paused = !animPic.paused }
        Shortcut { sequences: ["Escape", "Ctrl+W", "Q"]; enabled: keys.active; onActivated: win.doClose() }
    }

    // ---- UI ----
    Rectangle {
        anchors.fill: parent
        color: Theme.bg1

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // toolbar
            Rectangle {
                visible: win.bars
                Layout.fillWidth: true; Layout.preferredHeight: tbFlow.implicitHeight + 14
                color: Theme.panel
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                Flow {
                    id: tbFlow
                    x: 10; y: 7; width: parent.width - 20
                    spacing: 6
                    ChamferButton { implicitHeight: 30; text: "Prev"; onClicked: win.go(-1) }
                    ChamferButton { implicitHeight: 30; text: "Next"; onClicked: win.go(1) }
                    Item { width: 8; height: 1 }
                    ChamferButton { implicitHeight: 30; text: "Fit"; primary: win.fit; onClicked: win.fit = true }
                    ChamferButton { implicitHeight: 30; text: "1:1"; primary: !win.fit && Math.abs(win.zoom - 1) < 0.001; onClicked: win.actualSize() }
                    ChamferButton { implicitHeight: 30; text: "−"; onClicked: win.zoomStep(-1) }
                    ChamferButton { implicitHeight: 30; text: "+"; onClicked: win.zoomStep(1) }
                    Item { width: 8; height: 1 }
                    ChamferButton { implicitHeight: 30; text: "↺"; onClicked: win.rotate(-90) }
                    ChamferButton { implicitHeight: 30; text: "↻"; onClicked: win.rotate(90) }
                    ChamferButton { visible: win.anim; implicitHeight: 30; text: animPic.paused ? "Play" : "Pause"; onClicked: animPic.paused = !animPic.paused }
                    Item { width: 8; height: 1 }
                    ChamferButton { implicitHeight: 30; text: "Wallpaper"; onClicked: win.setWallpaper() }
                    ChamferButton { implicitHeight: 30; text: "Show in folder"; onClicked: win.showInFolder() }
                    ChamferButton { implicitHeight: 30; text: "Copy"; onClicked: win.copyImage() }
                    ChamferButton { implicitHeight: 30; text: "Delete"; onClicked: if (win.path !== "") win.overlay = "trash" }
                }
            }

            // the picture
            Item {
                id: stage
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true

                Flickable {
                    id: flick
                    anchors.fill: parent
                    contentWidth: Math.max(width, win.rotW * win.viewScale)
                    contentHeight: Math.max(height, win.rotH * win.viewScale)
                    boundsBehavior: Flickable.StopAtBounds
                    maximumFlickVelocity: 4000
                    interactive: win.ready && (contentWidth > width || contentHeight > height)

                    Item {
                        width: flick.contentWidth; height: flick.contentHeight
                        Image {
                            id: stillPic
                            visible: !win.anim
                            anchors.centerIn: parent
                            width: win.natW * win.viewScale; height: win.natH * win.viewScale
                            rotation: win.rot
                            source: win.anim ? "" : win.fileUrl(win.path)
                            asynchronous: true
                            autoTransform: true
                            smooth: true
                            mipmap: true
                        }
                        AnimatedImage {
                            id: animPic
                            visible: win.anim
                            anchors.centerIn: parent
                            width: win.natW * win.viewScale; height: win.natH * win.viewScale
                            rotation: win.rot
                            source: win.anim ? win.fileUrl(win.path) : ""
                            cache: false
                            smooth: true
                            onSourceChanged: paused = false
                        }
                        TapHandler {
                            onDoubleTapped: eventPoint => win.toggleFit(eventPoint.position.x - flick.contentX,
                                                                         eventPoint.position.y - flick.contentY)
                        }
                    }
                }
                // the wheel zooms around the pointer (clicks and drags go through to the Flickable)
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: flick.interactive ? (flick.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
                    onWheel: wheel => {
                        const d = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                        if (d !== 0) win.zoomAt(Math.pow(1.0015, d), wheel.x, wheel.y);
                    }
                }

                // neighbours, decoded ahead (never shown)
                Image { visible: false; asynchronous: true; autoTransform: true; source: /\.(gif|webp)$/i.test(win.preNext) ? "" : win.preNext }
                Image { visible: false; asynchronous: true; autoTransform: true; source: /\.(gif|webp)$/i.test(win.preBack) ? "" : win.preBack }

                // loading / error / empty
                Column {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 40, 520)
                    spacing: 8
                    visible: win.listing || win.err !== "" || win.pic.status === Image.Error || (win.pic.status === Image.Loading && loadDelay.ok)
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: win.listing || win.pic.status === Image.Loading ? "LOADING" : "CANNOT SHOW THIS IMAGE"
                        color: win.listing || win.pic.status === Image.Loading ? Theme.dim : Theme.bad
                        font.family: Theme.mono; font.pixelSize: 12; font.letterSpacing: 2
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        visible: text !== ""
                        text: win.err !== "" ? win.err + ": " + ((Viewer.requests[win.winId] || {}).path || "")
                            : win.pic.status === Image.Error ? "The format is not supported, or the file is damaged." : ""
                        color: Theme.fg; font.family: Theme.ui; font.pixelSize: 14
                    }
                }
                // "LOADING" only for pictures that take a moment (no flicker when stepping through a folder)
                Timer {
                    id: loadDelay
                    property bool ok: false
                    interval: 250
                    running: win.pic.status === Image.Loading
                    onRunningChanged: if (running) ok = false
                    onTriggered: ok = true
                }

                // short notes ("Image copied", ...)
                Rectangle {
                    visible: win.flash !== ""
                    anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 14
                    width: flashText.implicitWidth + 24; height: 30
                    color: Theme.panel
                    border.width: 1; border.color: Theme.lineStrong
                    Rectangle { anchors.left: parent.left; width: 3; height: parent.height; color: Theme.accent }
                    Text {
                        id: flashText
                        anchors.centerIn: parent; anchors.horizontalCenterOffset: 1
                        text: win.flash.toUpperCase()
                        color: Theme.fg; font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 1.2
                    }
                }
            }

            // status line
            Rectangle {
                visible: win.bars
                Layout.fillWidth: true; Layout.preferredHeight: 26
                color: Theme.panel
                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 12; anchors.right: info.left; anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideMiddle
                    text: win.path
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
                }
                Text {
                    id: info
                    anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (!win.cur) return "";
                        const parts = [(win.index + 1) + " / " + win.files.length];
                        if (win.ready) parts.push(Math.round(win.natW) + " × " + Math.round(win.natH));
                        parts.push(win.humanSize(win.cur.size));
                        if (win.anim && animPic.frameCount > 1) parts.push(animPic.frameCount + " FRAMES");
                        if (win.ready) parts.push((win.fit ? "FIT " : "") + Math.round(win.viewScale * 100) + "%");
                        if (win.rot) parts.push(win.rot + "°");
                        return parts.join("   ");
                    }
                    color: Theme.dim
                    font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 0.8
                }
            }
        }

        // ---- modal overlay: confirm moving the picture to the Trash ----
        Item {
            id: prompt
            anchors.fill: parent
            visible: win.overlay === "trash"
            onVisibleChanged: if (visible) forceActiveFocus(); else keys.forceActiveFocus()
            Keys.onEscapePressed: win.overlay = ""
            Keys.onReturnPressed: win.trash()
            Keys.onEnterPressed: win.trash()

            Rectangle { anchors.fill: parent; color: Theme.bg1; opacity: 0.6 }
            MouseArea { anchors.fill: parent; hoverEnabled: true; onWheel: wheel => wheel.accepted = true }
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 40, 440)
                height: promptCol.implicitHeight + 40
                color: Theme.panel
                border.width: 1; border.color: Theme.lineStrong
                Rectangle { anchors.fill: parent; color: Theme.bg1; z: -1 }
                Column {
                    id: promptCol
                    x: 20; y: 20; width: parent.width - 40
                    spacing: 14
                    SectionLabel { text: "Move to Trash" }
                    Text {
                        width: parent.width
                        text: "Move \"" + win.name + "\" to the Trash? DATA can restore it from there."
                        color: Theme.fg; wrapMode: Text.Wrap
                        font.family: Theme.ui; font.pixelSize: 14
                    }
                    Row {
                        spacing: 10
                        anchors.right: parent.right
                        ChamferButton { text: "Cancel"; onClicked: win.overlay = "" }
                        ChamferButton { text: "Move to Trash"; primary: true; onClicked: win.trash() }
                    }
                }
            }
        }
    }

    function humanSize(b) {
        if (b < 1024) return b + " B";
        const u = ["KB", "MB", "GB"];
        let i = -1;
        do { b /= 1024; i++; } while (b >= 1024 && i < u.length - 1);
        return (b < 10 ? b.toFixed(1) : Math.round(b)) + " " + u[i];
    }
}
