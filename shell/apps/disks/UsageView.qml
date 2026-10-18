// UsageView.qml - the USAGE tab: pick a place, scan it, then walk the folders by size.
import QtQuick
import QtQuick.Controls
import "../.."
import "../games"

Item {
    id: root

    readonly property var lst: Disks.listing
    readonly property string base: Disks.usagePath === "/" ? "" : Disks.usagePath
    readonly property var entries: {
        const r = [];
        if (Disks.usageView === "largest") {
            if (Disks.largestFiles) for (const f of Disks.largestFiles.files)
                r.push({ name: f.name, path: f.path, kind: "file", size: f.size, items: 1, errors: 0, pct: lst && lst.size ? 100 * f.size / lst.size : 0, dir: f.dir });
        } else if (lst) {
            for (const e of lst.entries) {
                const rolled = e.kind === "other";
                r.push(rolled ? e : Object.assign({}, e, { path: base + "/" + e.name }));
            }
        }
        return r;
    }
    readonly property real maxSize: entries.length > 0 ? Math.max(1, entries[0].size) : 1
    readonly property var crumbs: { Disks.usageRoot; Disks.usagePath; return Disks.breadcrumbs(); }

    function go() {
        const p = pathField.text.trim();
        if (p !== "") Disks.choose(p);
    }
    Connections {
        target: Disks
        function onUsageRootChanged() { if (pathField.text !== Disks.usageRoot) pathField.text = Disks.usageRoot; }
    }

    // ---- location picker ----
    Item {
        id: picker
        width: parent.width; height: 32
        Flow {
            id: places
            anchors { left: parent.left; right: scanBtns.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            spacing: 6
            height: 28
            clip: true
            Repeater {
                model: [{ path: Disks.home, label: "Home" }].concat(Disks.mounted.filter(m => m.path !== Disks.home && m.label.toLowerCase() !== "home"))
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: Disks.usageRoot === modelData.path
                    width: pl.implicitWidth + 20; height: 28
                    color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : (pm.containsMouse ? Theme.panel2 : "transparent")
                    border.color: on ? Theme.accent : Theme.line
                    Text {
                        id: pl; anchors.centerIn: parent
                        text: modelData.label.toUpperCase()
                        color: parent.on ? Theme.accent : Theme.fg
                        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.2
                    }
                    MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !Disks.scanning
                        onClicked: Disks.choose(modelData.path) }
                }
            }
        }
        Row {
            id: scanBtns
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 8
            GButton {
                visible: !Disks.scanning
                primary: true
                enabled: Disks.usageRoot !== "" && Disks.busy === ""
                text: Disks.listing || Disks.lastScan ? "Rescan" : "Scan"
                onClicked: Disks.rescan()
            }
            GButton { visible: Disks.scanning; text: "Cancel"; onClicked: Disks.cancelScan() }
        }
    }
    GInput {
        id: pathField
        anchors.top: picker.bottom; anchors.topMargin: 8
        width: parent.width
        placeholder: "Or type a folder, like /mnt/games, and press Enter"
        enabled: !Disks.scanning
        onAccepted: root.go()
        Component.onCompleted: text = Disks.usageRoot
    }

    // ---- breadcrumb ----
    Flow {
        id: crumbRow
        anchors.top: pathField.bottom; anchors.topMargin: 10
        width: parent.width
        spacing: 4
        visible: Disks.usageRoot !== "" && !Disks.noCache && !Disks.scanning
        Repeater {
            model: root.crumbs
            delegate: Row {
                required property var modelData
                required property int index
                spacing: 4
                Text {
                    visible: index > 0
                    text: "›"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 12
                }
                Text {
                    readonly property bool last: index === root.crumbs.length - 1
                    text: modelData.label
                    color: last ? Theme.fg : (cm.containsMouse ? Theme.accent : Theme.dim)
                    font.family: Theme.mono; font.pixelSize: 12; font.underline: cm.containsMouse && !last
                    MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: if (!parent.last) Disks.browse(modelData.path) }
                }
            }
        }
    }

    // ---- summary + stacked bar ----
    Item {
        id: summary
        anchors.top: crumbRow.visible ? crumbRow.bottom : pathField.bottom; anchors.topMargin: 10
        width: parent.width
        height: visible ? 74 : 0
        visible: root.lst !== null && !Disks.scanning
        Row {
            id: sumRow
            spacing: 14
            Text {
                text: root.lst ? Disks.fmt(root.lst.size) : ""
                color: Theme.fg; font.family: Theme.display; font.pixelSize: 20
            }
            Text {
                anchors.baseline: parent.children[0].baseline
                text: root.lst ? Disks.count(root.lst.items) + " items · scanned " + Disks.ago(root.lst.scanned) : ""
                color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
            }
        }
        Row {
            anchors { right: parent.right; top: parent.top }
            spacing: 8
            GSeg {
                options: [{ id: "folders", label: "Folders" }, { id: "largest", label: "Largest files" }]
                current: Disks.usageView
                onPicked: id => Disks.setUsageView(id)
            }
        }
        Item {
            id: stack
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 22
            Rectangle { anchors.fill: parent; color: Theme.panel2; border.color: Theme.line }
            Repeater {
                model: {
                    if (!root.lst || root.lst.size <= 0 || Disks.usageView !== "folders") return [];
                    let x = 0;
                    const out = [];
                    root.entries.slice(0, 12).forEach((e, i) => {
                        const w = stack.width * e.size / root.lst.size;
                        out.push({ x: x, w: w, e: e, i: i });
                        x += w;
                    });
                    return out;
                }
                delegate: Rectangle {
                    required property var modelData
                    x: modelData.x; width: Math.max(0, modelData.w - 1); height: stack.height
                    visible: modelData.w >= 1
                    color: {
                        const hue = (Theme.accent.hslHue >= 0 ? Theme.accent.hslHue : 0.55);
                        return Qt.hsla((hue + modelData.i * 0.09) % 1, 0.5, 0.5, modelData.e.kind === "dir" ? 0.85 : 0.5);
                    }
                    ToolTip.visible: sm.containsMouse
                    ToolTip.text: modelData.e.name + " · " + Disks.fmt(modelData.e.size)
                    MouseArea { id: sm; anchors.fill: parent; hoverEnabled: true; cursorShape: modelData.e.kind === "dir" && modelData.e.path ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (modelData.e.kind === "dir" && modelData.e.path) Disks.browse(modelData.e.path) }
                }
            }
        }
    }

    // ---- unreadable note ----
    Text {
        id: unread
        anchors.top: summary.bottom; anchors.topMargin: visible ? 8 : 0
        width: parent.width
        wrapMode: Text.WordWrap
        visible: root.lst !== null && !Disks.scanning && (root.lst.errors > 0 || root.lst.other_fs > 0)
        height: visible ? implicitHeight : 0
        color: Theme.warn
        font.family: Theme.ui; font.pixelSize: 12
        text: root.lst ? (root.lst.errors > 0 ? "Some folders could not be read (" + root.lst.errors + "), so the real total is a little higher. " : "")
                     + (root.lst.other_fs > 0 ? "Other drives mounted inside were left out." : "") : ""
    }

    // ---- list ----
    ListView {
        id: list
        anchors { top: unread.bottom; topMargin: 8; bottom: parent.bottom; left: parent.left; right: parent.right }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: root.lst !== null && !Disks.scanning
        model: root.entries
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        delegate: UsageRow {
            required property var modelData
            width: list.width - 8
            entry: modelData
            maxSize: root.maxSize
            onDrill: Disks.browse(modelData.path)
            onOpenIt: Disks.openInData(modelData.kind === "dir" ? modelData.path : modelData.path.replace(/\/[^\/]*$/, "") || "/")
            onTrashIt: Disks.askTrash(modelData)
        }
    }

    // ---- empty / scanning states ----
    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width, 520)
        spacing: 12
        visible: Disks.scanning
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Scanning…"
            color: Theme.fg; font.family: Theme.display; font.pixelSize: 16
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Disks.count(Disks.progress.files) + " files · " + Disks.fmt(Disks.progress.bytes)
            color: Theme.accent; font.family: Theme.mono; font.pixelSize: 13
        }
        Text {
            width: parent.width
            elide: Text.ElideMiddle
            horizontalAlignment: Text.AlignHCenter
            text: Disks.progress.path
            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 11
        }
    }
    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width, 460)
        spacing: 12
        visible: !Disks.scanning && root.lst === null
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Disks.noCache ? "Not scanned yet" : "See what takes up space"
            color: Theme.fg; font.family: Theme.display; font.pixelSize: 16
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: Disks.noCache ? "Press Scan to measure " + Disks.usageRoot + ". Nothing is changed or deleted."
                                : "Pick Home or a drive above, or type a folder, then press Scan."
            color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
        }
    }
}
