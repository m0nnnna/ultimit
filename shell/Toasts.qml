pragma Singleton

// Toasts.qml - thin shim over Notifs so every toast renders through the same popup
// component (components/NotifCard.qml, hosted by ToastOverlay).
//   Toasts.show("Title", "message")                    // plain
//   Toasts.show("Mailer", "No mail app — try:", "sudo apt install thunderbird")  // + selectable command
//   Toasts.show("Battery", "5% left", "", 0, 2)           // sticky (timeout 0), critical (urgency 2); returns an id
//   Toasts.show("Update", "Ultimit 0.2 is out", "", 0, 1, () => open())   // clicking the card runs it
import QtQuick
import Quickshell

Singleton {
    function show(title, message, command, timeoutMs, urgency, onClick) { return Notifs.toast(title, message, command, timeoutMs, urgency, onClick); }
    function dismiss(id) { Notifs.closePopup(id); }
}
