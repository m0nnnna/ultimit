// Gallery.qml - IMAGE's library: a folder's pictures as thumbnails, its picture folders as tiles and
// the usual places (Pictures, Screenshots, Downloads, ...) on the left. What IMAGE shows when it is
// started without a file (Pictures), and what G / Grid in the viewer goes back to.
// Listing comes from image.py dir; picking a picture emits openImage with the grid's order, so
// Prev/Next in the viewer walks the pictures in the order they were shown.
import QtQuick
import QtQuick.Layouts
import "../.."
import "../accessory"

Item {
    id: gal

    signal openImage(var files, int index)
    signal closeRequested()

    property string dir: ""
    property string parentDir: ""
    property var dirs: []               // [{ p, n, count, cover }]
    property var files: []              // [{ p, n, size, mtime }], name order
    property var places: []             // [{ p, n }]
    property string err: ""
    property bool loading: false
    property string sort: "date"        // "date": newest first, "name": DATA's name order
    property string focusPath: ""       // put the keyboard cursor here after the next load

    readonly property var shown: sort === "date" ? files.slice().sort((a, b) => b.mtime - a.mtime) : files
    readonly property var tiles: dirs.map(d => ({ d: true, p: d.p, n: d.n, count: d.count, cover: d.cover }))
                                     .concat(shown.map(f => ({ d: false, p: f.p, n: f.n, size: f.size })))
    readonly property string dirName: dir === "" ? "" : (dir === "/" ? "/" : dir.substring(dir.lastIndexOf("/") + 1))

    function fileUrl(p) { return p === "" ? "" : "file://" + p.split("/").map(encodeURIComponent).join("/"); }

    function load(d, focus) {
        focusPath = focus || "";
        loading = true;
        Viewer.run(["dir", d || ""], o => {
            gal.loading = false;
            gal.dir = o.dir || d;
            gal.parentDir = o.parent || "";
            gal.err = o.ok ? "" : (o.err || "Cannot open");
            gal.places = o.places || [];
            gal.dirs = o.dirs || [];
            gal.files = o.files || [];
            const i = gal.focusPath === "" ? -1 : gal.tiles.findIndex(t => t.p === gal.focusPath);
            grid.currentIndex = i >= 0 ? i : 0;
            if (i >= 0) grid.positionViewAtIndex(i, GridView.Contain);
            else grid.positionViewAtBeginning();
            grid.forceActiveFocus();
        });
    }
    function reload() { load(dir, grid.currentItem ? tiles[grid.currentIndex].p : ""); }
    function up() { if (parentDir !== "") load(parentDir, dir); }

    function activate(i) {
        const t = tiles[i];
        if (!t) return;
        if (t.d) { load(t.p); return; }
        openImage(shown, i - dirs.length);
    }

    function focusGrid() { grid.forceActiveFocus(); }

    Shortcut { sequences: ["Escape", "Ctrl+W", "Q"]; enabled: gal.visible; onActivated: gal.closeRequested() }
    Shortcut { sequences: ["Backspace", "Alt+Up"]; enabled: gal.visible; onActivated: gal.up() }
    Shortcut { sequences: ["F5", "Ctrl+R"]; enabled: gal.visible; onActivated: gal.reload() }
    Shortcut { sequences: ["S"]; enabled: gal.visible; onActivated: gal.sort = gal.sort === "date" ? "name" : "date" }

    Rectangle { anchors.fill: parent; color: Theme.panel }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // places
        Rectangle {
            Layout.preferredWidth: 184; Layout.fillHeight: true
            color: "transparent"
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.line }
            Column {
                x: 12; y: 16; width: parent.width - 24
                spacing: 2
                SectionLabel { text: "Places"; bottomPadding: 8 }
                Repeater {
                    model: gal.places
                    delegate: Item {
                        id: place
                        required property var modelData
                        readonly property bool here: gal.dir === modelData.p
                        width: parent.width; height: 30
                        Rectangle {
                            anchors.fill: parent
                            color: place.here ? Theme.panel2 : (placeMa.containsMouse ? Qt.rgba(Theme.panel2.r, Theme.panel2.g, Theme.panel2.b, Theme.panel2.a * 0.6) : "transparent")
                        }
                        Rectangle { visible: place.here; width: 2; height: parent.height; color: Theme.accent }
                        Text {
                            x: 12; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 16
                            text: place.modelData.n
                            elide: Text.ElideRight
                            color: place.here ? Theme.accent : (placeMa.containsMouse ? Theme.fg : Theme.dim)
                            font.family: Theme.ui; font.pixelSize: 13
                        }
                        MouseArea {
                            id: placeMa
                            anchors.fill: parent; hoverEnabled: true
                            onClicked: gal.load(place.modelData.p)
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: 0

            // where we are
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 44
                color: "transparent"
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                    spacing: 6
                    ChamferButton { implicitHeight: 30; text: "Up"; visible: gal.parentDir !== ""; onClicked: gal.up() }
                    Text {
                        Layout.fillWidth: true; Layout.leftMargin: 6
                        text: gal.dir
                        elide: Text.ElideLeft
                        color: Theme.fg; font.family: Theme.mono; font.pixelSize: 12
                    }
                    ChamferButton { implicitHeight: 30; text: "Newest"; primary: gal.sort === "date"; onClicked: gal.sort = "date" }
                    ChamferButton { implicitHeight: 30; text: "Name"; primary: gal.sort === "name"; onClicked: gal.sort = "name" }
                }
            }

            Item {
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true

                GridView {
                    id: grid
                    anchors.fill: parent
                    anchors.margins: 8
                    // as many ~200 px columns as fit, stretched to the full width
                    readonly property int cols: Math.max(1, Math.round(width / 200))
                    cellWidth: Math.floor(width / cols)
                    cellHeight: cellWidth
                    model: gal.tiles
                    focus: true
                    keyNavigationEnabled: true
                    highlightFollowsCurrentItem: false
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: cellHeight * 2
                    Keys.onReturnPressed: gal.activate(currentIndex)
                    Keys.onEnterPressed: gal.activate(currentIndex)

                    delegate: Item {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool isCur: GridView.isCurrentItem && grid.activeFocus
                        width: grid.cellWidth; height: grid.cellHeight

                        Rectangle {
                            id: frame
                            anchors.fill: parent; anchors.margins: 4
                            color: Theme.panel2
                            border.width: tile.isCur || tileMa.containsMouse ? 1 : 0
                            border.color: tile.isCur ? Theme.accent : Theme.lineStrong
                            clip: true

                            Image {
                                id: thumb
                                anchors.fill: parent; anchors.margins: 1
                                source: gal.fileUrl(tile.modelData.d ? tile.modelData.cover : tile.modelData.p)
                                sourceSize: Qt.size(320, 320)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                autoTransform: true
                                smooth: true
                                cache: true
                                // fade in as it decodes, so the grid fills in without popping
                                opacity: status === Image.Ready ? (tile.modelData.d ? 0.55 : 1) : 0
                                Behavior on opacity { NumberAnimation { duration: Config.dur(140); easing.type: Easing.OutCubic } }
                            }
                            Text {
                                visible: thumb.status === Image.Error
                                anchors.centerIn: parent
                                text: "?"
                                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 18
                            }
                            // folder: name and count on a band along the bottom
                            Rectangle {
                                visible: tile.modelData.d
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                anchors.margins: 1
                                height: 40
                                color: Theme.bg1
                                Rectangle { width: 2; height: parent.height; color: Theme.accent }
                                Text {
                                    x: 12; y: 5; width: parent.width - 20
                                    text: tile.modelData.n
                                    elide: Text.ElideRight
                                    color: Theme.fg; font.family: Theme.ui; font.pixelSize: 13
                                }
                                Text {
                                    x: 12; y: 22
                                    text: tile.modelData.d ? tile.modelData.count + (tile.modelData.count === 1 ? " picture" : " pictures") : ""
                                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 10
                                }
                            }
                        }
                        MouseArea {
                            id: tileMa
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { grid.currentIndex = tile.index; grid.forceActiveFocus(); gal.activate(tile.index); }
                        }
                    }
                }

                // loading / error / empty
                Column {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 40, 420)
                    spacing: 8
                    visible: gal.err !== "" || (!gal.loading && gal.tiles.length === 0 && gal.dir !== "")
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: gal.err !== "" ? "CANNOT OPEN THIS FOLDER" : "NO PICTURES HERE"
                        color: gal.err !== "" ? Theme.bad : Theme.dim
                        font.family: Theme.mono; font.pixelSize: 12; font.letterSpacing: 2
                    }
                    Text {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                        text: gal.err !== "" ? gal.err : "Screenshots (Print) are saved to Pictures/Screenshots."
                        color: Theme.fg; font.family: Theme.ui; font.pixelSize: 14
                    }
                }
            }

            // status line
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 26
                color: "transparent"
                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 12; anchors.right: count.left; anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideMiddle
                    text: grid.currentIndex >= 0 && grid.currentIndex < gal.tiles.length ? gal.tiles[grid.currentIndex].n : ""
                    color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
                }
                Text {
                    id: count
                    anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const parts = [];
                        if (gal.dirs.length) parts.push(gal.dirs.length + (gal.dirs.length === 1 ? " FOLDER" : " FOLDERS"));
                        parts.push(gal.files.length + (gal.files.length === 1 ? " PICTURE" : " PICTURES"));
                        return parts.join("   ");
                    }
                    color: Theme.dim
                    font.family: Theme.mono; font.pixelSize: 11; font.letterSpacing: 0.8
                }
            }
        }
    }
}
