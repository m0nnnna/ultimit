// ToastOverlay.qml - renders Toasts.model top-right, under the status block
// (mockup .toast: panel, strong 1px line, 3px accent left bar, mono caps title).
// Overlay layer; the window is only mapped while toasts exist and is sized to them.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

PanelWindow {
    id: win

    // Set by shell.qml (avoids a visible <-> screen binding loop).
    property string screenName: ""

    anchors { top: true; right: true }
    margins { top: 104; right: 20 }
    implicitWidth: 340
    implicitHeight: Math.max(1, col.implicitHeight)
    visible: Toasts.model.count > 0 && Config.isUiScreen(screenName)
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ultimit-toasts"

    Column {
        id: col
        width: parent.width
        spacing: 8

        Repeater {
            model: Toasts.model
            delegate: Rectangle {
                id: toast
                required property int tid
                required property string title
                required property string message
                required property string command

                width: col.width
                implicitHeight: inner.implicitHeight + 20
                height: implicitHeight
                color: Theme.panel
                border.width: 1
                border.color: Theme.lineStrong
                Rectangle { x: -1; y: -1; width: 3; height: parent.height + 2; color: Theme.accent }

                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: Config.dur(350); easing.type: Easing.OutCubic } }
                transform: Translate { y: toast.opacity < 1 ? (1 - toast.opacity) * -8 : 0 }

                Column {
                    id: inner
                    x: 14; y: 10
                    width: parent.width - 28 - 18
                    spacing: 2
                    Text {
                        text: toast.title.toUpperCase()
                        color: Theme.dim
                        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 2
                    }
                    Text {
                        width: parent.width
                        text: toast.message
                        color: Theme.fg
                        wrapMode: Text.WordWrap
                        font.family: Theme.ui; font.pixelSize: 12
                        lineHeight: 1.3
                    }
                    Rectangle {
                        visible: toast.command !== ""
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
                            text: toast.command
                            wrapMode: TextEdit.Wrap
                            color: Theme.fg
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.onAccent
                            font.family: Theme.mono; font.pixelSize: 11
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
                        onClicked: Toasts.dismiss(toast.tid)
                    }
                }
            }
        }
    }
}
