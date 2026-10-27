// Ticker.qml - the news ticker inside the top bar (TopBar.qml fills the bar's middle with it).
// Accent "NEWS" tab on the left (with the number of unread notifications), then the crawl: desktop
// notifications first (accent-marked: icon, app, summary, body; Notifs.tickerItems), then the
// headlines. Both ends fade out. The crawl restarts when a notification arrives so the new item
// enters from the right. Click: a headline opens its link, a notification runs its default action
// (else opens the notification centre); right-click on a notification clears it from the ticker.
import QtQuick
import QtQuick.Effects
import Quickshell
import ".."

Item {
    id: root

    property string screenName: ""
    // Paused while a fullscreen window covers this screen (the bar is hidden then anyway).
    readonly property bool covered: Config.isCovered(root.screenName)

    // Headlines: real feed items (Feeds.qml) once any feed has loaded, else the built-in ones from Config.
    // { kind: "news"|"notif", t: time label, h: headline, link: http(s) URL or "", ... }
    readonly property var entries: {
        const out = [];
        if (Config.tickerNotifs)
            for (const n of Notifs.tickerItems)
                out.push({ kind: "notif", nid: n.nid, app: n.app, icon: n.icon, h: n.title, b: n.body, urgency: n.urgency, link: "" });
        const news = Feeds.hasItems ? Feeds.shown : Config.headlines.map(n => ({ t: n.t, h: n.h, link: "" }));
        for (const n of news) out.push({ kind: "news", t: n.t, h: n.h, link: n.link || "" });
        return out;
    }
    readonly property int unread: Config.tickerNotifs ? Notifs.tickerItems.length : 0

    Connections {
        target: Notifs
        function onTickerAdded() { if (Config.motion) crawl.restart(); }
    }

    Rectangle {
        id: tab
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: tabText.implicitWidth + Theme.space(7)
        color: Theme.accent
        Text {
            id: tabText
            anchors.centerIn: parent
            text: root.unread > 0 ? "NEWS " + root.unread : "NEWS"
            color: Theme.onAccent
            font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 2.2
            font.features: Theme.tnum
        }
    }

    Item {
        id: fadeMask
        anchors.fill: viewport
        visible: false
        layer.enabled: true
        Rectangle {
            id: ramp
            anchors.fill: parent
            readonly property real f: Math.min(0.5, 24 / Math.max(1, width))
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: ramp.f; color: "black" }
                GradientStop { position: 1 - ramp.f; color: "black" }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }

    Item {
        id: viewport
        anchors { left: tab.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        clip: true

        // Soft 24px fade at both ends instead of a hard cut: the crawl is masked by a ramp.
        layer.enabled: true
        layer.effect: MultiEffect { maskEnabled: true; maskSource: fadeMask }
        // Feed and notification text is untrusted: PlainText only.
        Row {
            id: msg
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            x: Config.motion ? viewport.width : Theme.space(7)

            // Constant speed (~48 px/s); restarts when the text or viewport changes. Paused while hovered
            // or while a fullscreen window is up on any screen.
            NumberAnimation on x {
                id: crawl
                running: Config.motion && viewport.width > 0
                paused: running && (hover.containsMouse || root.covered || Config.desktopPaused)
                from: viewport.width
                to: -msg.implicitWidth
                duration: Math.max(1000, (viewport.width + msg.implicitWidth) / 48 * 1000)
                loops: Animation.Infinite
                // Reduce motion: the marquee stops and the text sits at the left, static.
                onRunningChanged: if (!running) msg.x = Theme.space(7)
            }

            Repeater {
                id: rep
                model: root.entries
                delegate: Row {
                    id: item
                    required property var modelData
                    required property int index
                    readonly property bool notif: modelData.kind === "notif"
                    readonly property bool hot: hover.hoverIdx === index && (notif || modelData.link !== "")
                    spacing: 0
                    Rectangle {   // notification marker: accent bar
                        visible: item.notif
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; height: Theme.icon.sm
                        color: item.modelData.urgency === 2 ? Theme.bad : Theme.accent
                    }
                    Item { visible: item.notif; width: Theme.space(2); height: 1 }
                    Image {
                        visible: item.notif && status === Image.Ready
                        anchors.verticalCenter: parent.verticalCenter
                        width: visible ? Theme.icon.sm : 0; height: Theme.icon.sm
                        source: item.notif ? item.modelData.icon : ""
                        sourceSize: Qt.size(Theme.icon.sm * 2, Theme.icon.sm * 2)
                        asynchronous: true
                    }
                    Item { visible: item.notif && item.modelData.icon !== ""; width: Theme.space(2); height: 1 }
                    Text {   // time label (news) / app name (notification)
                        text: item.notif ? item.modelData.app.toUpperCase() : item.modelData.t
                        textFormat: Text.PlainText
                        color: item.notif ? (item.modelData.urgency === 2 ? Theme.bad : Theme.accent) : Theme.fg
                        font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 0.6
                    }
                    Text {
                        text: "  " + item.modelData.h
                        textFormat: Text.PlainText
                        color: item.hot ? Theme.accent : (item.notif ? Theme.fg : Theme.dim)
                        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                        font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 0.6
                        font.underline: item.hot
                    }
                    Text {
                        visible: item.notif && item.modelData.b !== ""
                        text: "  " + item.modelData.b
                        textFormat: Text.PlainText
                        color: Theme.dim
                        font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 0.6
                    }
                    Text {
                        text: "   ◆   "
                        visible: item.index < root.entries.length - 1
                        color: item.notif ? Theme.accent : Theme.dim
                        font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 0.6
                    }
                }
            }
        }

        // Hover pauses the crawl; click acts on the item under the pointer.
        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            property int hoverIdx: -1
            function hit(mx) {
                const px = mx - msg.x;
                for (let i = 0; i < rep.count; i++) {
                    const it = rep.itemAt(i);
                    if (it && px >= it.x && px < it.x + it.width) return i;
                }
                return -1;
            }
            function entryAt(mx) { const i = hit(mx); return i >= 0 ? root.entries[i] : null; }
            onPositionChanged: mouse => hoverIdx = hit(mouse.x)
            onExited: hoverIdx = -1
            cursorShape: hoverIdx >= 0 && root.entries[hoverIdx] && (root.entries[hoverIdx].kind === "notif" || root.entries[hoverIdx].link !== "")
                ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: mouse => {
                const e = entryAt(mouse.x);
                if (!e) return;
                if (e.kind === "notif") {
                    if (mouse.button === Qt.RightButton) { Notifs.tickerRemove(e.nid); return; }
                    if (!Notifs.invokeDefault(e.nid)) FlyoutState.openFlyout("clock", root.screenName);
                } else if (mouse.button === Qt.LeftButton && e.link !== "") Feeds.open(e.link);
            }
        }
    }
}
