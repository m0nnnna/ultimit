// AppMenuButton.qml - top bar, far left: the focused window's name (desktop entry Name, else its
// title). Click opens the app menu (AppMenu.qml). With no window focused it reads "Ultimit" and
// opens the launcher instead.
import QtQuick
import Quickshell.Wayland
import "../.."
import ".."

BarButton {
    id: btn
    readonly property var tl: ToplevelManager.activeToplevel
    // title / appId changes re-evaluate through the explicit reads
    readonly property string appName: { if (tl) { tl.title; tl.appId; } return BarUi.nameFor(tl); }
    name: "App menu: " + (appName !== "" ? appName : "Ultimit")
    tip: ""
    lit: BarUi.appMenuOpen
    width: Math.min(260, label.implicitWidth + Theme.space(8))
    onClicked: {
        if (tl) BarUi.toggleAppMenu(centerX() - width / 2 + Theme.space(8), screenName);
        else Config.toggleLauncher(screenName);
    }
    Text {
        id: label
        anchors { left: parent.left; leftMargin: Theme.space(4); right: parent.right; rightMargin: Theme.space(4); verticalCenter: parent.verticalCenter }
        elide: Text.ElideRight
        text: btn.appName !== "" ? btn.appName : "Ultimit"
        color: btn.lit ? Theme.accent : Theme.fg
        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
        font.family: Theme.ui; font.pixelSize: Theme.type.body; font.weight: Font.DemiBold
    }
}
