// SoundItem.qml - top bar: volume icon. Click opens the sound flyout, wheel changes the volume
// (5 % per notch), middle click mutes.
import QtQuick
import "../.."
import ".."

BarButton {
    visible: SysState.sinkReady
    name: "Volume: " + (SysState.sinkMuted ? "muted" : SysState.sinkVol + " percent")
    tip: (SysState.sinkMuted ? "VOLUME MUTED  " : "VOLUME  ") + SysState.sinkVol + "%"
        + (SysState.sinkName !== "" ? "\n" + SysState.sinkName : "") + "\nSCROLL: +/- 5%  MIDDLE: MUTE"
    fly: "sound"
    width: visible ? 32 : 0
    property real acc: 0
    onClicked: button => {
        if (button === Qt.MiddleButton) {
            SysState.toggleSinkMute();
            Osd.flash("volume", SysState.sinkVol, !SysState.sinkMuted);
        } else openFly("sound");
    }
    onWheeled: delta => {
        // 5 % per wheel notch (120 units); touchpads accumulate
        acc += delta;
        const notches = Math.trunc(acc / 120);
        if (notches === 0) return;
        acc -= notches * 120;
        const v = Math.max(0, Math.min(100, SysState.sinkVol + notches * 5));
        SysState.setSinkVol(v);
        Osd.flash("volume", v, SysState.sinkMuted);
    }
    StatusIcon {
        anchors.centerIn: parent
        kind: "volume"
        size: Theme.icon.md
        level: SysState.sinkVol <= 0 ? 0 : (SysState.sinkVol < 34 ? 1 : (SysState.sinkVol < 67 ? 2 : 3))
        muted: SysState.sinkMuted
    }
}
