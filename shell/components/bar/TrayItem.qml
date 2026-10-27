// TrayItem.qml - top bar: the StatusNotifierItem tray icons (Tray.qml), with a divider before them.
import QtQuick
import "../.."
import ".."

Row {
    id: root
    property string screenName: ""
    height: Config.barHeight
    visible: appTray.visible
    Item {
        width: 9; height: root.height
        Rectangle { anchors.centerIn: parent; width: 1; height: 16; color: Theme.divider }
    }
    Tray { id: appTray; screenName: root.screenName; height: root.height }
}
