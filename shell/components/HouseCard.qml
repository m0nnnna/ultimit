// HouseCard.qml - a glass panel that opens with the house motion: an accent line draws out from the
// centre of the top edge (lineP), then the content wipes down (wipeP). Reverse the two to collapse
// it. glitch() is the failed-password feedback: a short horizontal tear (frame and content slide
// against each other) while the accent goes to the error colour and comes back.
// Children go inside; size the card from outside (width/height are the open size).
import QtQuick
import ".."

Item {
    id: card
    property real lineP: 1
    property real wipeP: 1
    property real errP: 0
    property real fx: 0     // glitch: frame offset
    property real cx: 0     // glitch: content offset
    readonly property color lineColor: Qt.tint(Theme.accent, Qt.rgba(Theme.bad.r, Theme.bad.g, Theme.bad.b, errP))
    default property alias content: inner.data

    function glitch() { gl.restart(); }

    ParallelAnimation {
        id: gl
        SequentialAnimation {
            NumberAnimation { target: card; property: "fx"; to: -16; duration: Config.dur(40) }
            NumberAnimation { target: card; property: "fx"; to: 14; duration: Config.dur(50) }
            NumberAnimation { target: card; property: "fx"; to: -9; duration: Config.dur(50) }
            NumberAnimation { target: card; property: "fx"; to: 6; duration: Config.dur(50) }
            NumberAnimation { target: card; property: "fx"; to: 0; duration: Config.dur(60) }
        }
        SequentialAnimation {
            NumberAnimation { target: card; property: "cx"; to: 10; duration: Config.dur(40) }
            NumberAnimation { target: card; property: "cx"; to: -12; duration: Config.dur(50) }
            NumberAnimation { target: card; property: "cx"; to: 7; duration: Config.dur(50) }
            NumberAnimation { target: card; property: "cx"; to: -3; duration: Config.dur(50) }
            NumberAnimation { target: card; property: "cx"; to: 0; duration: Config.dur(60) }
        }
        SequentialAnimation {
            NumberAnimation { target: card; property: "errP"; to: 1; duration: Config.dur(70); easing.type: Easing.OutCubic }
            PauseAnimation { duration: Config.dur(750) }
            NumberAnimation { target: card; property: "errP"; to: 0; duration: Config.dur(450) }
        }
    }

    Item {
        x: card.fx; width: card.width; height: card.height
        visible: card.wipeP > .001 || card.lineP > .001
        Rectangle {
            id: bg
            width: parent.width; height: card.height * card.wipeP
            visible: card.wipeP > .001
            color: Theme.panel
            border.width: 1
            border.color: Qt.tint(Theme.line, Qt.rgba(Theme.bad.r, Theme.bad.g, Theme.bad.b, card.errP * .6))
        }
        Item {
            width: parent.width; height: bg.height
            visible: card.wipeP > .001
            Brackets { color: card.lineColor }
        }
        Rectangle {   // the accent line, drawn out from the centre
            y: -1; height: 2
            width: card.width * card.lineP; x: (card.width - width) / 2
            visible: card.lineP > .001
            color: card.lineColor
        }
    }
    Item {
        x: card.cx; width: card.width; height: card.height * card.wipeP
        visible: card.wipeP > .001
        clip: true
        Item { id: inner; width: card.width; height: card.height }
    }
}
