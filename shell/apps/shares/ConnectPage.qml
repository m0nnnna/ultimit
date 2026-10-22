// ConnectPage.qml - the CONNECT tab: type an address, pick a computer found on the network, see what is connected
// and what is saved. Everything goes through Shares (connect.py / gvfs); no admin rights.
import QtQuick
import QtQuick.Controls
import "../.."
import "../games"

Item {
    id: root

    // small section header: square + label (+ right-aligned extra)
    component Head: Item {
        property string text: ""
        property string extra: ""
        width: parent ? parent.width : 0
        height: 18
        Rectangle { id: sq; width: 6; height: 6; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
        GLabel { anchors { left: sq.right; leftMargin: 8; verticalCenter: parent.verticalCenter } text: parent.text; strong: true }
        GLabel { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: parent.extra }
    }
    component Link: GLabel {
        signal clicked()
        color: m.containsMouse ? Theme.accent : Theme.dim
        MouseArea { id: m; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }
    component Row2: Rectangle {      // a bordered list row with an accent stripe
        property color stripe: Theme.accent
        implicitHeight: 62
        color: Theme.panel2
        border.color: Theme.line
        border.width: 1
        Rectangle { width: 2; height: parent.height; color: parent.stripe }
    }

    Flickable {
        id: scroller
        anchors.fill: parent
        contentHeight: body.implicitHeight + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: body
            width: scroller.width - 8
            spacing: 12

            // ---------------- address ----------------
            Column {
                width: parent.width
                spacing: 6
                Head { text: "Connect to an address" }
                Flow {
                    width: parent.width
                    spacing: 8
                    GInput {
                        id: addr
                        width: Config.mobile ? parent.width : parent.width - go.width - 8
                        height: 34
                        placeholder: "\\\\computer\\share  or  smb://computer/share"
                        onAccepted: go.clicked()
                    }
                    GButton {
                        id: go
                        text: Shares.connecting !== "" ? "Connecting…" : "Connect"
                        primary: true
                        enabled: addr.text.trim() !== "" && Shares.connecting === ""
                        onClicked: { Shares.connectAddress(addr.text.trim(), false); }
                    }
                }
                Text {
                    visible: Shares.loaded && Shares.caps.smb === false
                    width: parent.width; wrapMode: Text.WordWrap
                    color: Theme.warn; font.family: Theme.ui; font.pixelSize: 12
                    text: "The network file support (gvfs-backends) is not available yet, so connecting will not work until it is installed."
                }
                Text {
                    visible: Shares.note !== ""
                    width: parent.width; elide: Text.ElideRight
                    color: Shares.noteKind === "error" ? Theme.bad : Theme.dim
                    font.family: Theme.ui; font.pixelSize: 12
                    text: Shares.note
                }
            }

            // ---------------- on your network ----------------
            Column {
                width: parent.width
                spacing: 8
                Item {
                    width: parent.width; height: 18
                    Head { text: "On your network" }
                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Rectangle {
                            id: spin
                            visible: Shares.discovering
                            width: 8; height: 8; rotation: 45
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.accent
                            RotationAnimator on rotation { running: Shares.discovering; from: 45; to: 405; duration: 900; loops: Animation.Infinite }
                        }
                        Link { anchors.verticalCenter: parent.verticalCenter; text: Shares.discovering ? "Looking…" : "Refresh"
                               onClicked: if (!Shares.discovering) Shares.discover() }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: Shares.servers
                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            readonly property bool on: Shares.browseServer !== null && Shares.browseServer.host === modelData.host
                            width: Config.mobile ? parent.width : 206; height: Config.mobile ? 56 : 52
                            color: on ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : (cm.containsMouse ? Theme.panel2 : "transparent")
                            border.color: on ? Theme.accent : Theme.line
                            border.width: 1
                            Column {
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                                spacing: 3
                                Text { width: parent.width; elide: Text.ElideRight; text: card.modelData.name; color: Theme.fg
                                       font.family: Theme.ui; font.pixelSize: 14; font.weight: Font.DemiBold }
                                Text { width: parent.width; elide: Text.ElideRight; text: card.modelData.address || card.modelData.host; color: Theme.dim
                                       font.family: Theme.mono; font.pixelSize: 11 }
                            }
                            MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: Shares.browseHost({ name: card.modelData.name, host: card.modelData.host }) }
                        }
                    }
                }
                Text {
                    visible: !Shares.discovering && Shares.servers.length === 0
                    width: parent.width; wrapMode: Text.WordWrap
                    color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                    text: Shares.discoverNote !== "" ? "Could not look for computers: " + Shares.discoverNote
                        : "No computers found. Windows PCs often do not announce themselves; type their address above."
                }
            }

            // ---------------- browse a server ----------------
            Rectangle {
                id: browsePanel
                visible: Shares.browseServer !== null
                width: parent.width
                height: bcol.implicitHeight + 28
                color: Theme.panel2
                border.color: Theme.lineStrong
                border.width: 1
                Column {
                    id: bcol
                    x: 14; y: 14
                    width: parent.width - 28
                    spacing: 8
                    Item {
                        width: parent.width; height: 18
                        Head { text: Shares.browseServer ? "Shares on " + Shares.browseServer.name : "" }
                        Link { anchors { right: parent.right; verticalCenter: parent.verticalCenter } text: "Close"; onClicked: Shares.browseServer = null }
                    }
                    GLabel { visible: Shares.browsing; text: "Looking…" }
                    Text {
                        visible: Shares.browseError !== ""
                        width: parent.width; wrapMode: Text.WordWrap
                        color: Theme.bad; font.family: Theme.ui; font.pixelSize: 12
                        text: Shares.browseError
                    }
                    Text {
                        visible: !Shares.browsing && Shares.browseError === "" && Shares.browseShares.length === 0 && !Shares.credReq
                        width: parent.width; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                        text: "No shared folders are visible on this computer."
                    }
                    Repeater {
                        model: Shares.browseShares
                        delegate: Item {
                            id: srow
                            required property string modelData
                            readonly property string uri: Shares.browseServer ? "smb://" + Shares.browseServer.host + "/" + srow.modelData : ""
                            readonly property bool mounted: Shares.isMounted(uri)
                            width: bcol.width; height: 38
                            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }
                            Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter } text: srow.modelData; color: Theme.fg
                                   font.family: Theme.ui; font.pixelSize: 14 }
                            GButton {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                height: 28
                                text: srow.mounted ? "Connected" : "Connect"
                                enabled: !srow.mounted && Shares.connecting === ""
                                primary: !srow.mounted
                                onClicked: Shares.connectShare(Shares.browseServer.host, srow.modelData)
                            }
                        }
                    }
                }
            }

            // ---------------- connected ----------------
            Column {
                width: parent.width
                spacing: 8
                Head { text: "Connected"; extra: Shares.mounts.length + (Shares.mounts.length === 1 ? " location" : " locations") }
                Text {
                    visible: Shares.mounts.length === 0
                    width: parent.width; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                    text: "Nothing connected."
                }
                Repeater {
                    model: Shares.mounts
                    delegate: Row2 {
                        id: mrow
                        required property var modelData
                        width: body.width
                        implicitHeight: Config.mobile ? minfo.implicitHeight + mbtns.height + 34 : 62
                        Column {
                            id: minfo
                            anchors { left: parent.left; right: Config.mobile ? parent.right : mbtns.left; leftMargin: 16; rightMargin: 12
                                      top: Config.mobile ? parent.top : undefined; topMargin: Config.mobile ? 12 : 0
                                      verticalCenter: Config.mobile ? undefined : parent.verticalCenter }
                            spacing: 4
                            Text { width: parent.width; elide: Text.ElideRight; text: mrow.modelData.name; color: Theme.fg
                                   font.family: Theme.ui; font.pixelSize: 15; font.weight: Font.DemiBold }
                            Text { width: parent.width; elide: Text.ElideMiddle; text: mrow.modelData.uri; color: Theme.dim
                                   font.family: Theme.mono; font.pixelSize: 11 }
                        }
                        Grid {
                            id: mbtns
                            columns: Config.mobile ? 2 : 3
                            anchors { right: Config.mobile ? undefined : parent.right; left: Config.mobile ? parent.left : undefined; rightMargin: 12; leftMargin: 16
                                      bottom: Config.mobile ? parent.bottom : undefined; bottomMargin: Config.mobile ? 12 : 0
                                      verticalCenter: Config.mobile ? undefined : parent.verticalCenter }
                            spacing: 8
                            GButton { text: Shares.isSaved(mrow.modelData.uri) ? "★ Saved" : "☆ Save"; enabled: !Shares.isSaved(mrow.modelData.uri)
                                      onClicked: Shares.saveMount(mrow.modelData) }
                            GButton { text: "Open"; primary: true; enabled: mrow.modelData.path !== ""; onClicked: Shares.openFolder(mrow.modelData.path) }
                            GButton { text: "Disconnect"; onClicked: Shares.disconnect(mrow.modelData.uri) }
                        }
                    }
                }
            }

            // ---------------- saved ----------------
            Column {
                width: parent.width
                spacing: 8
                Head { text: "Saved"; extra: Shares.saved.length + (Shares.saved.length === 1 ? " connection" : " connections") }
                Text {
                    visible: Shares.saved.length === 0
                    width: parent.width; color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                    text: "Connect to a share, then press Save to keep it here."
                }
                Repeater {
                    model: Shares.saved
                    delegate: Row2 {
                        id: srow2
                        required property var modelData
                        stripe: Theme.dim
                        width: body.width
                        implicitHeight: Config.mobile ? sinfo.implicitHeight + rec.height + sbtns.height + 48 : 62
                        Column {
                            id: sinfo
                            anchors { left: parent.left; right: Config.mobile ? parent.right : rec.left; leftMargin: 16; rightMargin: 12
                                      top: Config.mobile ? parent.top : undefined; topMargin: Config.mobile ? 12 : 0
                                      verticalCenter: Config.mobile ? undefined : parent.verticalCenter }
                            spacing: 4
                            Flow {
                                width: parent.width
                                spacing: 10
                                Text { anchors.verticalCenter: Config.mobile ? undefined : parent.verticalCenter; text: srow2.modelData.name; color: Theme.fg
                                       font.family: Theme.ui; font.pixelSize: 15; font.weight: Font.DemiBold }
                                GChip { visible: srow2.modelData.user !== ""; anchors.verticalCenter: Config.mobile ? undefined : parent.verticalCenter; text: srow2.modelData.user; tone: Theme.dim }
                                GChip { visible: Shares.isMounted(srow2.modelData.uri); anchors.verticalCenter: Config.mobile ? undefined : parent.verticalCenter; text: "Connected"; tone: Theme.ok }
                            }
                            Text { width: parent.width; elide: Text.ElideMiddle; text: srow2.modelData.uri; color: Theme.dim
                                   font.family: Theme.mono; font.pixelSize: 11 }
                        }
                        GToggle {
                            id: rec
                            width: 200
                            anchors { right: Config.mobile ? undefined : sbtns.left; rightMargin: 14; verticalCenter: Config.mobile ? undefined : parent.verticalCenter
                                      left: Config.mobile ? sinfo.left : undefined; top: Config.mobile ? sinfo.bottom : undefined; topMargin: Config.mobile ? 8 : 0 }
                            label: "Reconnect at login"
                            checked: srow2.modelData.reconnectAtLogin
                            onToggled: v => Shares.setReconnect(srow2.modelData.uri, v)
                        }
                        Grid {
                            id: sbtns
                            columns: 2
                            anchors { right: Config.mobile ? undefined : parent.right; left: Config.mobile ? parent.left : undefined; rightMargin: 12; leftMargin: 16
                                      bottom: Config.mobile ? parent.bottom : undefined; bottomMargin: Config.mobile ? 12 : 0
                                      verticalCenter: Config.mobile ? undefined : parent.verticalCenter }
                            spacing: 8
                            GButton { text: "Connect"; primary: true; enabled: !Shares.isMounted(srow2.modelData.uri) && Shares.connecting === ""
                                      onClicked: Shares.connectSaved(srow2.modelData) }
                            GButton { text: "Remove"; onClicked: Shares.unsave(srow2.modelData.uri) }
                        }
                    }
                }
            }
        }
    }
}
