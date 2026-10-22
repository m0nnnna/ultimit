// MobileBack.qml - phone-only back bar for an app's stacked panes (Config.mobile):
// a 44 px strip with "‹ LABEL"; tapping it emits back().
import QtQuick

Rectangle {
    id: root
    property string label: "BACK"
    signal back()
    width: parent ? parent.width : 0
    height: 44
    color: Theme.panel2
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
    Text {
        x: 14; anchors.verticalCenter: parent.verticalCenter
        text: "‹  " + root.label.toUpperCase()
        color: Theme.accent
        font.family: Theme.ui; font.weight: Font.DemiBold; font.pixelSize: 13; font.letterSpacing: 1.6
    }
    MouseArea { anchors.fill: parent; onClicked: root.back() }
}
