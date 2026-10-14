// image-shell.qml - IMAGE (the image viewer) as its own Quickshell process (qs -p <shell>/image-shell.qml),
// separate from the desktop shell like MEMO, so a huge picture never weighs on the desktop. Started on
// demand by bin/ultimit-image; exits shortly after its last window closes.
import QtQuick
import Quickshell
import Quickshell.Io
import "apps/image"

ShellRoot {
    settings.watchFiles: false

    // Follow the desktop skin (read-only; the desktop shell's Persist owns shell.json).
    FileView {
        id: skinFile
        path: Quickshell.env("HOME") + "/.config/ultimit/shell.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (Quickshell.env("ULTIMIT_SKIN")) return;
            try { const s = JSON.parse(text()).skin; if (s in Theme.skins) Theme.skin = s; } catch (e) {}
        }
    }
    ImageApp {}
}
