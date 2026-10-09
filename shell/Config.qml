pragma Singleton

// Config.qml - user-tweakable settings and defaults for the Ultimit shell.
// Everything configurable lives here so the components stay generic.

import QtQuick
import Quickshell

Singleton {
    readonly property string version: "0.1"

    // Wallpaper animation. When false the wallpaper is drawn once (zero idle cost).
    // Set ULTIMIT_MOTION=0 in the environment to start with motion off.
    property bool motion: Quickshell.env("ULTIMIT_MOTION") !== "0"
    // Wallpaper redraw rate cap while motion is on.
    property int wallpaperFps: 20
    // Number of main shards in the wing (mockup slider: 16..60).
    property int shardDensity: 34

    // Play the boot sequence overlay once at shell startup.
    property bool bootOnStart: Quickshell.env("ULTIMIT_BOOT") !== "0"

    // UI animation duration scale: 0 when motion is off (reduced motion), else 1.
    readonly property real motionScale: motion ? 1 : 0
    function dur(ms) { return Math.round(ms * motionScale); }

    // ---- shared UI state / requests (see apps/accessory, Boot.qml, Rail.qml) ----
    // Accessory window visibility; the window writes back here when closed via its frame.
    property bool accessoryOpen: false
    readonly property string accessoryTitle: "Accessory"
    // Bumped to ask Boot.qml to (re)play the boot overlay.
    property int bootRequest: 0
    function playBoot() { bootRequest++; }

    // Layout metrics (px)
    readonly property int railWidth: 84
    readonly property int tickerHeight: 26

    // Rail buttons, in display order.
    //  id       - key used for icons
    //  label    - text under the icon
    //  command  - argv-style command launched on click (run through `sh -c`)
    //  appIds   - Wayland app_ids that count as "this app is open"
    //             (compared case-insensitively)
    readonly property var apps: [
        { id: "games",     label: "GAMES",     command: "steam",
          appIds: ["steam", "lutris", "heroic", "com.heroicgameslauncher.hgl", "net.lutris.lutris"] },
        { id: "mailer",    label: "MAILER",    command: "thunderbird",
          appIds: ["thunderbird", "org.mozilla.thunderbird", "org.gnome.evolution", "evolution"] },
        { id: "news",      label: "NEWS",      command: "xdg-open https://news.ycombinator.com",
          appIds: ["firefox", "org.mozilla.firefox", "google-chrome", "chromium", "brave-browser"] },
        { id: "audio",     label: "AUDIO",     command: "rhythmbox",
          appIds: ["rhythmbox", "org.gnome.rhythmbox3", "spotify"] },
        { id: "data",      label: "DATA",      command: "nautilus",
          appIds: ["nautilus", "org.gnome.nautilus", "org.gnome.files"] },
        { id: "accessory", label: "ACCESSORY", command: "gnome-control-center",
          appIds: ["gnome-control-center", "org.gnome.settings"] }
    ]

    // Static sample headlines for the ticker: { t: time label, h: headline }
    readonly property var headlines: [
        { t: "10:04", h: "Ultimit 0.1 “Mine” enters development" },
        { t: "09:20", h: "Fullscreen games skip the compositor" },
        { t: "YDAY",  h: "Desktop cat learns to sit on windows" },
        { t: "OCT 07", h: "Four skins ship in the first build" }
    ]
}
