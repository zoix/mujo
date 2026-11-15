pragma Singleton

// Read-only view of ~/.config/mujo/config.json, which the mujo CLI writes.
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
    property bool desktopClock: false
    property bool glass: false
    // Battery savings (`mujo power battery`): the two switches, and whether
    // the panels are drawn solid right now because the charger is unplugged.
    property bool batteryRefresh: false
    property bool batterySolid: false
    property bool solidNow: false
    property bool powerAuto: false
    // When the focus session ends, in seconds since 1970 (0 = none).
    property real focusUntil: 0
    // Changes whenever the weather place or its units do ("" = no place).
    property string weatherKey: ""

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
            root.desktopClock = config.desktop_clock === true;
            root.glass = config.glass === true;
            root.batteryRefresh = config.battery_refresh === true;
            root.batterySolid = config.battery_solid === true;
            root.solidNow = config.battery_now ? config.battery_now.solid === true : false;
            root.powerAuto = config.power_auto === true;
            root.focusUntil = config.focus && config.focus.until ? config.focus.until : 0;
            root.weatherKey = config.weather ? config.weather.name + " " + config.weather.lat + " " + config.weather.lon + " " + (config.weather_units ?? "c") : "";
        } catch (error) {
            console.warn("mujo: cannot read config.json:", error);
        }
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/mujo/config.json"
        watchChanges: true
        printErrors: false
        onLoaded: root.apply(file.text())
        onFileChanged: file.reload()
    }
}
