// QuestionPanel.qml - Claude's AskUserQuestion: pick from its options (or type your own) and send the answers back.
pragma ComponentBehavior: Bound
import QtQuick
import "../.."
import "../accessory"

Column {
    id: root
    property var ask: null              // the ask event: { rid, questions[{ question, header, multi, options[{ label, description }] }] }
    property bool compact: false
    signal answered(var answers)        // { question text: "label" or "label, label" }
    signal skipped()

    property var picks: ({})            // question index -> [labels]
    property var others: ({})           // question index -> typed answer
    readonly property var questions: ask && ask.questions ? ask.questions : []
    onAskChanged: { picks = {}; others = {}; }

    function answerOf(i) {
        const p = (picks[i] || []).slice();
        const o = (others[i] || "").trim();
        if (o !== "") { if (questions[i].multi) p.push(o); else return o; }
        return p.join(", ");
    }
    readonly property bool complete: {
        picks; others;
        for (let i = 0; i < questions.length; i++) if (answerOf(i) === "") return false;
        return questions.length > 0;
    }
    function toggle(i, label) {
        const q = questions[i], p = Object.assign({}, picks), cur = p[i] || [];
        if (q.multi) p[i] = cur.indexOf(label) >= 0 ? cur.filter(l => l !== label) : cur.concat([label]);
        else p[i] = cur.indexOf(label) >= 0 ? [] : [label];
        picks = p;
        if (!q.multi && p[i].length) { const o = Object.assign({}, others); o[i] = ""; others = o; }
    }
    function setOther(i, text) {
        const o = Object.assign({}, others); o[i] = text; others = o;
        if (text.trim() !== "" && !questions[i].multi) { const p = Object.assign({}, picks); p[i] = []; picks = p; }
    }
    function send() {
        if (!complete) return;
        const a = {};
        for (let i = 0; i < questions.length; i++) a[questions[i].question] = answerOf(i);
        answered(a);
    }

    spacing: compact ? 8 : 12

    Repeater {
        model: root.questions
        delegate: Column {
            id: qcol
            required property var modelData
            required property int index
            width: root.width
            spacing: 6
            Text {
                visible: qcol.modelData.header !== ""
                text: qcol.modelData.header.toUpperCase() + (qcol.modelData.multi ? "   · PICK ANY" : "")
                color: Theme.warn; font.family: Theme.mono; font.pixelSize: Theme.type.label; font.letterSpacing: 1.6
            }
            Text {
                width: parent.width; wrapMode: Text.Wrap
                text: qcol.modelData.question
                color: Theme.fg; font.family: Theme.ui; font.pixelSize: root.compact ? 13 : 14
            }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: qcol.modelData.options
                    delegate: Rectangle {
                        id: opt
                        required property var modelData
                        readonly property bool picked: (root.picks[qcol.index] || []).indexOf(modelData.label) >= 0
                        width: Math.min(optCol.implicitWidth + 20, qcol.width)
                        height: optCol.implicitHeight + 12
                        color: picked ? Theme.accent : (optMouse.containsMouse ? Theme.press : Theme.field)
                        Behavior on color { ColorAnimation { duration: Config.dur(Theme.motion.fast); easing.type: Theme.easeFast } }
                        Column {
                            id: optCol
                            x: 10; y: 6; width: opt.width - 20
                            Text {
                                width: parent.width; wrapMode: Text.Wrap
                                text: opt.modelData.label
                                color: opt.picked ? Theme.onAccent : Theme.fg; font.family: Theme.ui; font.pixelSize: Theme.type.body
                            }
                            Text {
                                visible: !root.compact && opt.modelData.description !== ""
                                width: Math.min(implicitWidth, qcol.width - 20); wrapMode: Text.Wrap
                                text: opt.modelData.description
                                color: opt.picked ? Theme.onAccent : Theme.dim; font.family: Theme.ui; font.pixelSize: Theme.type.label
                            }
                        }
                        MouseArea {
                            id: optMouse
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggle(qcol.index, opt.modelData.label)
                        }
                    }
                }
            }
            Entry {
                width: Math.min(parent.width, 420)
                placeholder: "Other…"
                text: root.others[qcol.index] || ""
                onTextChanged: if (text !== (root.others[qcol.index] || "")) root.setOther(qcol.index, text)
                onAccepted: root.send()
            }
        }
    }

    Row {
        spacing: 8
        ChamferButton { implicitHeight: root.compact ? 28 : 34; text: "Send answer" + (root.questions.length > 1 ? "s" : ""); primary: true; enabled: root.complete; opacity: enabled ? 1 : 0.5; onClicked: root.send() }
        ChamferButton { implicitHeight: root.compact ? 28 : 34; text: "Skip"; onClicked: root.skipped() }
    }
}
