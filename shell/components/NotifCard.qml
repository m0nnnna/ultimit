// NotifCard.qml - one popup in the toast stack (mockup .toast): panel fill, 1px strong line,
// 3px accent left bar, mono caps app label, title, body, chamfered action buttons, close x.
// Used for both D-Bus notifications and Toasts.show(). Hover pauses the expiry timer.
import QtQuick
import Quickshell
import ".."
import "../apps/accessory"

Rectangle {
    id: card

    required property int nid
    required property string kind
    required property string app
    required property string title
    required property string body
    required property string icon
    required property string image
    required property int urgency
    required property int timeout          // ms, 0 = sticky
    required property string actions       // JSON [{id,text}]
    required property bool hasDefault
    required property string command
    required property int rev

    // In the notification-centre list: no expiry timer, no popup actions; the x removes it from history.
    property bool inHistory: false
    function dismissMe() { if (inHistory) Notifs.dismiss(nid); else Notifs.closePopup(nid); }

    readonly property var actionList: { try { return JSON.parse(actions); } catch (e) { return []; } }
    readonly property color accentColor: urgency === 2 ? Theme.bad : (urgency === 0 ? Theme.dim : Theme.accent)
    readonly property string pic: image !== "" ? image : icon

    implicitHeight: content.implicitHeight + 22
    height: implicitHeight
    color: Theme.panel
    border.width: 1
    border.color: urgency === 2 ? Theme.bad : Theme.lineStrong
    GlowFrame { anchors.fill: parent; color: card.accentColor; travel: !card.inHistory && card.urgency !== 0; strength: card.urgency === 2 ? 1.2 : 0.8 }
    Rectangle { x: -1; y: -1; width: 3; height: parent.height + 2; color: card.accentColor }

    opacity: 0
    Component.onCompleted: opacity = 1
    Behavior on opacity { NumberAnimation { duration: Config.dur(350); easing.type: Easing.OutCubic } }
    transform: Translate { y: card.opacity < 1 ? (1 - card.opacity) * -8 : 0 }

    // ---- expiry (pauses while hovered) ----
    property real remaining: timeout
    property real startedAt: 0
    onTimeoutChanged: remaining = timeout
    onRevChanged: { remaining = timeout; if (life.running) { life.restart(); startedAt = Date.now(); } }
    HoverHandler { id: hover }
    Timer {
        id: life
        interval: Math.max(50, card.remaining)
        running: card.timeout > 0 && !hover.hovered && !card.inHistory
        onRunningChanged: {
            if (running) card.startedAt = Date.now();
            else if (card.startedAt > 0)
                card.remaining = Math.max(1500, card.remaining - (Date.now() - card.startedAt));
        }
        onTriggered: Notifs.expirePopup(card.nid)
    }

    // click the card body: run the "default" action if there is one, else dismiss the popup
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: card.hasDefault && !card.inHistory ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: mouse => {
            if (card.inHistory) { if (mouse.button === Qt.MiddleButton) card.dismissMe(); }
            else if (mouse.button === Qt.LeftButton && card.hasDefault) Notifs.invoke(card.nid, "default");
            else card.dismissMe();
        }
    }

    Row {
        id: content
        x: 14; y: 11
        width: parent.width - 28 - 16
        spacing: 10

        Item {   // image / app icon
            id: pic
            visible: card.pic !== "" && img.status === Image.Ready
            width: visible ? 40 : 0; height: 40
            Image {
                id: img
                anchors.fill: parent
                source: card.pic
                sourceSize: Qt.size(80, 80)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
            Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Theme.line }
        }

        Column {
            width: content.width - (pic.visible ? pic.width + content.spacing : 0)
            spacing: 3

            DecodeText {
                width: parent.width
                text: card.app.toUpperCase()
                visible: text !== ""
                decode: !card.inHistory
                elide: Text.ElideRight
                color: Theme.dim
                font.family: Theme.mono; font.pixelSize: Theme.size.sm; font.letterSpacing: 2
            }
            Text {
                width: parent.width
                visible: card.title !== ""
                text: card.title
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Theme.fg
                font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 13
            }
            Text {
                width: parent.width
                visible: card.body !== ""
                text: card.body
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: 6
                elide: Text.ElideRight
                color: card.title !== "" ? Theme.dim : Theme.fg
                linkColor: Theme.accent
                font.family: Theme.ui; font.pixelSize: 12
                lineHeight: 1.3
                onLinkActivated: link => { if (/^https?:\/\//.test(link)) Qt.openUrlExternally(link); }
                HoverHandler { cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor }
            }
            Rectangle {   // selectable command (install hints)
                visible: card.command !== ""
                width: parent.width
                height: visible ? cmdEdit.implicitHeight + 12 : 0
                color: Theme.panel2
                border.width: 1; border.color: Theme.line
                TextEdit {
                    id: cmdEdit
                    x: 8; y: 6
                    width: parent.width - 16
                    readOnly: true
                    selectByMouse: true
                    text: card.command
                    wrapMode: TextEdit.Wrap
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.onAccent
                    font.family: Theme.mono; font.pixelSize: 11
                }
            }
            Flow {
                visible: card.actionList.length > 0 && !card.inHistory
                width: parent.width
                spacing: 6
                topPadding: 4
                Repeater {
                    model: card.actionList
                    delegate: ChamferButton {
                        required property var modelData
                        required property int index
                        height: 28
                        implicitHeight: 28
                        primary: index === 0 && card.urgency === 2
                        text: modelData.text
                        onClicked: Notifs.invoke(card.nid, modelData.id)
                    }
                }
            }
        }
    }

    // dismiss
    Text {
        anchors.top: parent.top; anchors.right: parent.right
        anchors.topMargin: 6; anchors.rightMargin: 8
        text: "×"
        color: xMouse.containsMouse ? Theme.fg : Theme.dim
        font.family: Theme.mono; font.pixelSize: 14
        MouseArea {
            id: xMouse
            anchors.fill: parent; anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.dismissMe()
        }
    }
}
