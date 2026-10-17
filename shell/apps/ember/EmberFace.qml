// EmberFace.qml - Ember herself: her portrait in ASCII line art (EmberArt.mjs), drawn in one colour and
// animated - she blinks, glances about, her long hair sways, her mouth moves while she speaks, dots
// rise while she thinks, and a scan line runs down the wireframe. The first time she appears the
// lines are drawn in from the top. `mood` picks her expression; bump `talk` for every bit of speech.
import QtQuick
import "../.."
import "EmberArt.mjs" as Art

Item {
    id: root
    // idle | thinking | speaking | working | asking | happy | error
    property string mood: "idle"
    property int talk: 0
    property color ink: Theme.fg

    // ---- expression state, advanced by the tick ----
    property string eyes: "open"
    property string mouth: "rest"
    property real sway: 0
    property int thought: 0
    property int revealed: 0            // rows drawn in so far (the intro)
    property int scan: -8               // the scan line's row
    property var rows: Art.frame({ eyes: "open", mouth: "rest", sway: 0 })

    property real lastTalk: 0
    onTalkChanged: lastTalk = Date.now()
    property real blinkAt: Date.now() + 2500
    property int blinkStep: -1
    property real glanceUntil: 0
    property string glance: ""
    property real glanceAt: Date.now() + 7000
    property int tickN: 0

    function rnd(a, b) { return a + Math.random() * (b - a); }
    function step() {
        const now = Date.now();
        tickN++;
        sway += mood === "working" ? 0.16 : 0.09;
        if (revealed < Art.rows) revealed++;
        scan = scan > Art.rows + 10 ? -12 : scan + 1;

        // blinking: half, closed, half
        if (blinkStep < 0 && now > blinkAt && mood !== "happy") blinkStep = 0;
        let lid = "";
        if (blinkStep >= 0) {
            lid = ["half", "closed", "closed", "half"][blinkStep];
            blinkStep++;
            if (blinkStep > 3) { blinkStep = -1; blinkAt = now + rnd(2200, 6000); if (Math.random() < 0.15) blinkAt = now + 260; }
        }
        // glances while idle
        if (mood === "idle" && now > glanceAt) {
            glance = Math.random() < 0.5 ? "left" : "right";
            glanceUntil = now + rnd(700, 1600);
            glanceAt = now + rnd(6000, 14000);
        }
        if (now > glanceUntil) glance = "";

        let e = "open", m = "rest";
        switch (mood) {
        case "thinking":
            e = Math.floor(tickN / 18) % 3 === 2 ? "left" : "up";
            m = "small";
            if (tickN % 5 === 0) thought = (thought + 1) % 4;
            break;
        case "speaking": {
            const live = now - lastTalk < 260;
            m = live ? ["o", "e", "a", "rest", "e", "o"][tickN % 6] : "rest";
            break;
        }
        case "working": e = Math.floor(tickN / 25) % 4 === 3 ? "right" : "down"; m = "flat"; break;
        case "asking": e = "wide"; m = "small"; break;
        case "happy": e = "happy"; m = "smile"; break;
        case "error": e = "half"; m = "flat"; break;
        default: e = glance !== "" ? glance : "open"; m = "rest";
        }
        if (mood !== "thinking") thought = 0;
        if (lid !== "" && e !== "happy") e = lid;
        eyes = e; mouth = m;
        rows = Art.frame({ eyes: eyes, mouth: mouth, sway: sway, swayAmp: mood === "working" ? 1.3 : 1, thought: thought });
    }
    Timer { interval: 85; repeat: true; running: root.visible; onTriggered: root.step() }

    // ---- drawing: the biggest mono size that fits ----
    FontMetrics { id: fm; font.family: Theme.mono; font.pixelSize: 100 }
    readonly property real px: Math.max(6, Math.floor(Math.min(width / (Art.cols * fm.averageCharacterWidth / 100),
                                                               height / (Art.rows * 1.08))))
    Column {
        anchors.centerIn: parent
        Repeater {
            model: Art.rows
            Text {
                required property int index
                height: Math.round(root.px * 1.08)
                text: index < root.revealed ? root.rows[index] : ""
                color: root.ink
                // the scan line: a bright band moving down, a faint trail behind it
                opacity: {
                    const d = root.scan - index;
                    return d === 0 ? 1 : d > 0 && d < 4 ? 0.95 - d * 0.04 : 0.72;
                }
                font.family: Theme.mono; font.pixelSize: root.px
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
            }
        }
    }
}
