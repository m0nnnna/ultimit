pragma Singleton

// Toasts.qml - thin shim over Notifs so every toast renders through the same popup
// component (components/NotifCard.qml, hosted by ToastOverlay).
//   Toasts.show("Title", "message")                    // plain
//   Toasts.show("Mailer", "No mail app — try:", "sudo apt install thunderbird")  // + selectable command
import QtQuick
import Quickshell

Singleton {
    function show(title, message, command, timeoutMs) { Notifs.toast(title, message, command, timeoutMs); }
    function dismiss(id) { Notifs.closePopup(id); }
}
