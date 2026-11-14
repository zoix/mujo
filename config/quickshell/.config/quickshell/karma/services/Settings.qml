pragma Singleton

// Read-only view of ~/.config/karma/config.json, which the karma CLI writes.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string wallpaper: ""
    property bool dnd: false

    function reload(): void {
        file.reload();
    }

    function apply(text: string): void {
        try {
            const config = JSON.parse(text);
            root.wallpaper = typeof config.wallpaper === "string" ? config.wallpaper : "";
            root.dnd = config.dnd === true;
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
