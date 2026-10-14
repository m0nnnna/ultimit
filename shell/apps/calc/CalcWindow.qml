// CalcWindow.qml - CALC, the Ultimit calculator: one small xdg toplevel. Instantiate once: CalcWindow {}
//   qs -p <shell> ipc call calc toggle | open | close   (shell/bin/ultimit-calc wraps these)
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."
import "../accessory"

FloatingWindow {
    id: win
    title: "CALC"
    visible: Calc.open
    implicitWidth: 340
    implicitHeight: 620
    minimumSize: Qt.size(300, 520)
    color: "transparent"   // the Theme.panel glass below fills it

    onVisibleChanged: { if (visible !== Calc.open) Calc.open = visible; if (visible) Qt.callLater(() => ui.forceActiveFocus()); }
    Component.onCompleted: Qt.callLater(() => ui.forceActiveFocus())

    IpcHandler {
        target: "calc"
        function toggle(): void { Calc.toggle(); }
        function open(): void { Calc.show(); }
        function close(): void { Calc.hide(); }
        function state(): string { return JSON.stringify({ open: Calc.open, expr: Calc.expr, preview: Calc.preview, deg: Calc.deg, sci: Calc.sci, history: Calc.history.length, msg: Calc.msg }); }
    }
    Connections { target: Calc; function onRaiseChanged() { ui.forceActiveFocus(); } }

    Rectangle {
        id: ui
        anchors.fill: parent
        color: Theme.panel
        focus: true

        Keys.onPressed: event => {
            const k = event.key, t = event.text;
            if (event.modifiers & Qt.ControlModifier) {
                if (k === Qt.Key_C) Calc.copyResult();
                else if (k === Qt.Key_V) Calc.paste(Quickshell.clipboardText);
                else if (k === Qt.Key_W || k === Qt.Key_Q) Calc.hide();
                else return;
                event.accepted = true; return;
            }
            if (k === Qt.Key_Return || k === Qt.Key_Enter || t === "=") Calc.equals();
            else if (k === Qt.Key_Backspace) Calc.backspace();
            else if (k === Qt.Key_Escape || k === Qt.Key_Delete) Calc.clear();
            else if (t === "," ) Calc.insert(".");
            else if (t.length === 1 && /[0-9.+\-*\/^%()a-zA-Z]/.test(t)) Calc.insert(t);
            else return;
            event.accepted = true;
        }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 14
            spacing: 10

            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Item { Layout.fillWidth: true } // the name is in the titlebar
                CalcKey { Layout.preferredWidth: 58; implicitHeight: 30; kind: "fn"; text: Calc.deg ? "DEG" : "RAD"; on: false; onClicked: Calc.deg = !Calc.deg }
                CalcKey { Layout.preferredWidth: 58; implicitHeight: 30; kind: "fn"; text: "SCI"; on: Calc.sci; onClicked: Calc.sci = !Calc.sci }
            }

            // display
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 100
                color: Theme.panel2
                border.width: 1; border.color: Theme.line
                Text {
                    id: exprText
                    anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 12
                    y: 12; height: 40
                    horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideLeft
                    text: Calc.expr === "" ? "0" : Calc.pretty(Calc.expr)
                    color: Calc.expr === "" ? Theme.dim : Theme.fg
                    font.family: Theme.mono; font.pixelSize: 28
                }
                Text {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.margins: 12
                    y: 54; height: 24
                    horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideLeft
                    text: Calc.msg !== "" ? Calc.msg : (Calc.preview !== "" ? "= " + Calc.preview : "")
                    color: Calc.msg !== "" ? Theme.bad : Theme.accent
                    font.family: Theme.mono; font.pixelSize: 18
                }
                Text {
                    anchors.left: parent.left; anchors.leftMargin: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                    text: Calc.copied !== "" ? "COPIED" : (Calc.deg ? "DEGREES" : "RADIANS")
                    color: Calc.copied !== "" ? Theme.ok : Theme.dim
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
                }
                Text {
                    id: copyLab
                    anchors.right: parent.right; anchors.rightMargin: 12; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                    text: "COPY RESULT"
                    color: copyMa.containsMouse ? Theme.accent : Theme.dim
                    font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
                    MouseArea { id: copyMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Calc.copyResult() }
                }
            }

            // history
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 96
                color: "transparent"; border.width: 1; border.color: Theme.line
                clip: true
                Item {
                    id: histHead
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    height: 20
                    Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: "HISTORY"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1.6 }
                    Text {
                        visible: Calc.history.length > 0
                        anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                        text: "CLEAR"; color: clrMa.containsMouse ? Theme.accent : Theme.dim
                        font.family: Theme.mono; font.pixelSize: 9; font.letterSpacing: 1.4
                        MouseArea { id: clrMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Calc.clearHistory() }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                }
                ListView {
                    id: hist
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.top: histHead.bottom
                    clip: true
                    model: Calc.history
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { }
                    delegate: Rectangle {
                        required property var modelData
                        width: hist.width; height: 40
                        color: hm.containsMouse ? Theme.panel2 : "transparent"
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 10
                            y: 3; height: 16; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
                            text: Calc.pretty(modelData.expr)
                            color: Theme.dim; font.family: Theme.mono; font.pixelSize: 12
                        }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: 10; anchors.right: parent.right; anchors.rightMargin: 10
                            y: 19; height: 18; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
                            text: "= " + modelData.result
                            color: Theme.fg; font.family: Theme.mono; font.pixelSize: 15
                        }
                        MouseArea { id: hm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Calc.useEntry(modelData); ui.forceActiveFocus(); } }
                    }
                    Text {
                        anchors.centerIn: parent; visible: Calc.history.length === 0
                        text: "NO ENTRIES YET"; color: Theme.dim; opacity: 0.6
                        font.family: Theme.mono; font.pixelSize: 10; font.letterSpacing: 1.6
                    }
                }
            }

            // scientific keys
            GridLayout {
                visible: Calc.sci
                Layout.fillWidth: true
                columns: 5; rowSpacing: 0; columnSpacing: 0
                Repeater {
                    model: [["sin", "sin("], ["cos", "cos("], ["tan", "tan("], ["^", "^"], ["√", "sqrt("],
                            ["ln", "ln("], ["log", "log("], ["π", "pi"], ["e", "e"], ["abs", "abs("]]
                    delegate: CalcKey {
                        required property var modelData
                        Layout.fillWidth: true; Layout.preferredWidth: 1; implicitHeight: 32
                        kind: "fn"; text: modelData[0]
                        onClicked: { Calc.insert(modelData[1]); ui.forceActiveFocus(); }
                    }
                }
            }

            // keypad
            GridLayout {
                Layout.fillWidth: true
                columns: 4; rowSpacing: 0; columnSpacing: 0
                Repeater {
                    model: [
                        ["C", "op", "clear"], ["(", "op", "("], [")", "op", ")"], ["⌫", "op", "back"],
                        ["7", "num", "7"], ["8", "num", "8"], ["9", "num", "9"], ["÷", "op", "/"],
                        ["4", "num", "4"], ["5", "num", "5"], ["6", "num", "6"], ["×", "op", "*"],
                        ["1", "num", "1"], ["2", "num", "2"], ["3", "num", "3"], ["−", "op", "-"],
                        ["0", "num", "0"], [".", "num", "."], ["%", "op", "%"], ["+", "op", "+"]
                    ]
                    delegate: CalcKey {
                        required property var modelData
                        Layout.fillWidth: true; Layout.preferredWidth: 1
                        kind: modelData[1]; text: modelData[0]
                        onClicked: {
                            const a = modelData[2];
                            if (a === "clear") Calc.clear(); else if (a === "back") Calc.backspace(); else Calc.insert(a);
                            ui.forceActiveFocus();
                        }
                    }
                }
                CalcKey { Layout.columnSpan: 4; Layout.fillWidth: true; kind: "eq"; text: "="; onClicked: { Calc.equals(); ui.forceActiveFocus(); } }
            }
        }
    }
}
