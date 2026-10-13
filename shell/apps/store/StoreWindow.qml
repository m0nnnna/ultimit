// StoreWindow.qml - the STORE window: a normal xdg toplevel (the compositor draws the titlebar/frame).
// Header with search and INSTALLED, category chips, then one of: picks + categories (home), search or
// category results, one app in full, or the installed apps. A status line at the bottom follows the
// running install/remove.
import QtQuick
import QtQuick.Controls
import Quickshell
import "../.."
import "../games"

FloatingWindow {
    id: win
    title: "STORE"
    visible: Store.open
    implicitWidth: 1000
    implicitHeight: 700
    minimumSize: Qt.size(720, 480)
    color: Theme.bg1

    onVisibleChanged: if (visible !== Store.open) Store.open = visible

    Rectangle {
        anchors.fill: parent
        color: Theme.panel

        // ---------------- header ----------------
        Item {
            id: header
            // The window title itself is in the compositor's titlebar.
            x: 20; y: 10
            width: parent.width - 40
            height: 36
            GLabel {
                id: sub
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: Store.total > 0 ? Store.total.toLocaleString(Qt.locale("en_US"), "f", 0) + " apps from Flathub" : "Apps from Flathub"
            }
            GInput {
                id: search
                anchors { left: sub.right; leftMargin: 20; right: instBtn.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                placeholder: "Search apps  ( / )"
                onEdited: v => debounce.restart()
                onAccepted: { debounce.stop(); Store.search(text, ""); }
                onEscaped: { text = ""; Store.search("", ""); }
                Timer { id: debounce; interval: 220; onTriggered: Store.search(search.text, "") }
            }
            GButton {
                id: instBtn
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "Installed" + (Store.installedIds.length ? " (" + Store.installedIds.length + ")" : "")
                primary: Store.view === "installed"
                onClicked: Store.showInstalled()
            }
        }
        // a search started from outside (ultimit-store --search) shows its words in the box
        Connections { target: Store; function onQueryChanged() { if (search.text !== Store.query) search.text = Store.query; } }
        Shortcut { sequence: "/"; onActivated: search.input.forceActiveFocus() }
        Shortcut { sequence: "Ctrl+F"; onActivated: search.input.forceActiveFocus() }
        Shortcut { sequence: "Escape"; enabled: Store.view === "app"; onActivated: Store.back() }

        // ---------------- categories ----------------
        Flow {
            id: cats
            x: 20; anchors.top: header.bottom; anchors.topMargin: 8
            width: parent.width - 40
            spacing: 6
            Repeater {
                model: [{ id: "", label: "Picks" }].concat(Store.categories)
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool on: modelData.id === "" ? Store.view === "home"
                        : (Store.view === "results" && Store.category === modelData.id && Store.query === "")
                    width: ct.implicitWidth + 20; height: 26
                    color: on ? Theme.accent : (ch.hovered ? Theme.panel2 : "transparent")
                    border.color: on ? Theme.accent : Theme.line
                    Text {
                        id: ct; anchors.centerIn: parent
                        text: modelData.label.toUpperCase()
                        color: parent.on ? Theme.onAccent : Theme.fg
                        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.4
                    }
                    HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { search.text = ""; Store.search("", parent.modelData.id); } }
                }
            }
        }
        Rectangle { id: rule; x: 20; anchors.top: cats.bottom; anchors.topMargin: 10; width: parent.width - 40; height: 1; color: Theme.line }

        // ---------------- content ----------------
        Item {
            id: content
            anchors { top: rule.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: status.top; leftMargin: 20; rightMargin: 20 }

            Text {
                visible: Store.error !== "" && !Store.homeLoaded
                anchors.centerIn: parent; width: parent.width * 0.7
                horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                text: Store.error; color: Theme.bad; font.family: Theme.ui; font.pixelSize: 13
            }
            Text {
                visible: Store.error === "" && !Store.homeLoaded
                anchors.centerIn: parent
                text: "Reading Flathub's catalogue…"; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
            }

            // home + results: a grid of cards
            GridView {
                id: grid
                visible: Store.homeLoaded && (Store.view === "home" || Store.view === "results")
                anchors.fill: parent
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                readonly property int cols: Math.max(1, Math.floor(width / 300))
                cellWidth: Math.floor(width / cols)
                cellHeight: 148
                model: Store.view === "home" ? Store.picks : Store.results
                header: Item {
                    width: grid.width; height: 30
                    GLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        strong: true
                        text: Store.view === "home" ? "Picks for a new PC"
                            : Store.searching ? "Searching…"
                            : Store.query !== "" ? Store.resultCount + (Store.resultCount === 1 ? " result" : " results") + " for “" + Store.query + "”"
                            : Store.categoryLabel + "  ·  " + Store.resultCount + " apps"
                    }
                }
                delegate: Item {
                    required property var modelData
                    width: grid.cellWidth; height: grid.cellHeight
                    AppCard { anchors.fill: parent; anchors.rightMargin: 10; anchors.bottomMargin: 10; app: parent.modelData }
                }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }
            Text {
                visible: Store.view === "results" && !Store.searching && Store.results.length === 0
                anchors.centerIn: parent
                text: "Nothing found. Try fewer or different words."; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 13
            }

            AppPage { visible: Store.view === "app"; anchors.fill: parent }
            InstalledPage { visible: Store.view === "installed"; anchors.fill: parent }
        }

        // ---------------- status line ----------------
        Rectangle {
            id: status
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: Store.busy || Store.note !== "" ? 34 : 0
            visible: height > 0
            color: Theme.panel2
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            Rectangle {   // progress
                visible: Store.busy
                y: 0; height: 2; color: Theme.accent
                width: Store.pct >= 0 ? parent.width * Store.pct / 100 : parent.width * 0.25
                x: Store.pct >= 0 ? 0 : (parent.width - width) * (0.5 + 0.5 * Math.sin(spin.t))
                Timer { id: spin; property real t: 0; interval: 30; repeat: true; running: Store.busy && Store.pct < 0; onTriggered: t += 0.06 }
            }
            Text {
                anchors { left: parent.left; leftMargin: 20; right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                text: Store.busy
                    ? (Store.job.kind === "install" ? "Installing " : "Removing ") + Store.job.name + "  ·  " + Store.jobMsg
                      + (Store.pct >= 0 ? "  " + Store.pct + "%" : "") + (Store.queue.length ? "  ·  " + Store.queue.length + " waiting" : "")
                    : Store.note
                color: Store.busy ? Theme.fg : Store.noteKind === "error" ? Theme.bad : Store.noteKind === "ok" ? Theme.ok : Theme.dim
                font.family: Theme.ui; font.pixelSize: 12
            }
        }
    }
}
