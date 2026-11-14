pragma Singleton

// Read-only view of ~/.config/karma/config.json, which the karma CLI writes.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string wallpaper: ""
    property bool dnd: false
    property string modePref: "auto"
    property string palette: "catppuccin"
    property string accentPref: "auto"
    property string motion: "normal"
    property bool reduceMotion: false
    property bool nightOn: false
    property bool awake: false
    property bool desktopClock: true

    function reload(): void {
        file.reload();
    }

    function apply(text: string): void {
        try {
            const config = JSON.parse(text);
            root.wallpaper = typeof config.wallpaper === "string" ? config.wallpaper : "";
            root.dnd = config.dnd === true;
            root.modePref = config.mode_pref ?? "auto";
            root.palette = config.palette ?? "catppuccin";
            root.accentPref = config.accent_pref ?? "auto";
            root.motion = config.motion ?? "normal";
            root.reduceMotion = config.reduce_motion === true;
            root.nightOn = config.night_on === true;
            root.awake = config.awake === true;
            root.desktopClock = config.desktop_clock !== false;
        } catch (error) {
            console.warn("karma: cannot read config.json:", error);
        }
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/karma/config.json"
        watchChanges: true
        printErrors: false
        onLoaded: root.apply(file.text())
        onFileChanged: file.reload()
    }
}
