// CameraPage.qml - CAMERA tab: webcam picker, live preview, effect (off / blur / replace / remove), blur strength,
// replacement image and the virtual camera other apps pick.
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import "../.."
import "../games"

Flickable {
    id: root
    contentHeight: Math.max(cols.implicitHeight, height)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    readonly property var cam: Broadcast.cam
    readonly property bool idle: Broadcast.busy === ""
    readonly property bool on: cam.enabled === true
    readonly property string effect: cam.effect || "blur"
    property real blurShown: -1

    function fileName(p) { return p ? p.split("/").pop() : ""; }

    Row {
        id: cols
        width: root.width - 8
        spacing: 20

        // ---- left: webcam + virtual camera ----
        Column {
            width: 270
            spacing: 10
            Row {
                spacing: 8
                Rectangle { width: 6; height: 6; anchors.verticalCenter: parent.verticalCenter; color: Theme.accent }
                GLabel { text: "Camera"; strong: true }
            }
            DeviceList {
                width: parent.width
                devices: Broadcast.webcams.map(w => ({ id: w.path, label: w.name, tag: w.path.replace("/dev/", "") }))
                current: root.cam.device || ""
                emptyText: "No webcam found"
                onPicked: id => { if (root.idle && id !== root.cam.device) Broadcast.camSet("device", id); }
            }
            EffectCard {
                width: parent.width
                title: "Virtual camera"
                desc: "Other apps: pick “Ultimit Camera”."
                checked: root.cam.vcam === true
                onToggled: v => { if (root.idle) Broadcast.camSet("vcam", v); }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    visible: root.cam.vcamDevicePresent === false
                    text: "The “Ultimit Camera” device is missing (v4l2loopback is not loaded)."
                    color: Theme.warn; font.family: Theme.ui; font.pixelSize: 12
                }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    visible: root.cam.vcam === true && root.cam.vcamOn === true
                    text: "✓ On air: apps can use the camera now."
                    color: Theme.ok; font.family: Theme.ui; font.pixelSize: 12
                }
            }
        }

        // ---- right: preview + effects ----
        Column {
            width: cols.width - 290
            spacing: 12

            Rectangle {
                id: stage
                width: parent.width
                height: Math.round(width * 9 / 16)
                color: Theme.bg2; border.color: Theme.line; border.width: 1
                clip: true
                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    visible: root.on && Broadcast.camRunning && Broadcast.previewUrl !== ""
                    source: Broadcast.previewUrl
                    cache: false
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                }
                Brackets { color: Theme.accent; size: 14; thickness: 2 }
                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    visible: !(root.on && Broadcast.camRunning && Broadcast.previewUrl !== "")
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Broadcast.camStarting ? "Starting the camera engine…" : (root.on ? "Waiting for the picture…" : "Camera is off")
                        color: Theme.fg; font.family: Theme.display; font.pixelSize: 14; font.letterSpacing: 1
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !root.on && Broadcast.busy === ""
                        text: "Turn on camera effects to see yourself here."
                        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: Broadcast.camStarting
                        width: 220; height: 4; color: Theme.panel2; border.color: Theme.line; border.width: 1
                        Rectangle {
                            id: sweep
                            width: 70; height: parent.height; color: Theme.accent
                            SequentialAnimation on x {
                                running: Broadcast.camStarting; loops: Animation.Infinite
                                NumberAnimation { from: 0; to: 150; duration: 900; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: 150; to: 0; duration: 900; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: Broadcast.camStarting
                        text: "This takes a few seconds."
                        color: Theme.dim; font.family: Theme.ui; font.pixelSize: 12
                    }
                }
                GChip {
                    anchors { left: parent.left; top: parent.top; margins: 12 }
                    visible: root.on && Broadcast.camRunning
                    text: root.cam.vcamOn ? "On air" : "Preview"
                    tone: root.cam.vcamOn ? Theme.ok : Theme.dim
                }
            }

            EffectCard {
                width: parent.width
                title: "Camera effects"
                desc: "Blur, replace or remove the background behind you. The picture goes to the virtual camera."
                checked: root.on
                onToggled: v => { if (root.idle) { if (v) Broadcast.camSet("enabled", true); else Broadcast.camOff(); } }
                GSeg {
                    options: [{ id: "off", label: "Off" }, { id: "blur", label: "Blur" }, { id: "replace", label: "Replace" }, { id: "remove", label: "Remove" }]
                    current: root.effect
                    opacity: root.on ? 1 : 0.5
                    onPicked: id => { if (root.idle) Broadcast.camSet("effect", id); }
                }
                BSlider {
                    width: parent.width
                    visible: root.effect === "blur"
                    label: "Blur strength"
                    from: 0; to: 100
                    value: root.blurShown >= 0 ? root.blurShown : (root.cam.blur !== undefined ? root.cam.blur : 60)
                    onMoved: v => { root.blurShown = v; blurCommit.restart(); }
                    Timer { id: blurCommit; interval: 350; onTriggered: { if (root.idle) { Broadcast.camSet("blur", root.blurShown); root.blurShown = -1; } else blurCommit.restart(); } }
                }
                Row {
                    visible: root.effect === "replace"
                    width: parent.width
                    spacing: 8
                    Rectangle {
                        width: parent.width - pick.implicitWidth - 8; height: 34
                        color: Theme.panel; border.color: Theme.line; border.width: 1
                        Text {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            verticalAlignment: Text.AlignVCenter; elide: Text.ElideMiddle
                            text: root.cam.image ? root.fileName(root.cam.image) : "No image chosen"
                            color: root.cam.image ? Theme.fg : Theme.dim
                            font.family: Theme.ui; font.pixelSize: 13
                        }
                    }
                    GButton { id: pick; text: "Choose image…"; onClicked: picker.running = true }
                }
            }
        }
    }

    Process {
        id: picker
        command: Broadcast.fake ? ["echo", Quickshell.shellPath("apps/broadcast/fixtures/preview.jpg")]
            : ["zenity", "--file-selection", "--title=Choose a background image",
               "--file-filter=Images | *.png *.jpg *.jpeg *.webp *.bmp *.PNG *.JPG *.JPEG"]
        stdout: StdioCollector {
            onStreamFinished: { const p = text.trim(); if (p !== "") Broadcast.camSet("image", p); }
        }
    }
}
