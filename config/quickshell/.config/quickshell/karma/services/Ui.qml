pragma Singleton

// Which panels are open, and on which screen. Panels are presentation
// state only; nothing here changes the system.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.theme

Singleton {
    id: root

    // Name of the screen that shows the launcher, the power panel and the OSD.
    property string screen: ""

    property bool launcher: false
    property string launcherMode: "apps"   // apps | actions | wallpapers
    property bool session: false

    // A wallpaper being tried in the picker, shown before karma has applied it.
    property string wallPreview: ""

    property bool osd: false
    property string osdKind: "volume"
    property int osdValue: 0
    property bool osdMuted: false

    readonly property bool modal: launcher || session

    function focusedScreen(): string {
        return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "");
    }

    // Open the launcher in a mode; asking for the mode it already shows closes it.
    function toggleLauncher(mode: string): void {
        if (root.launcher && root.launcherMode === mode) {
            root.launcher = false;
            return;
        }
        root.screen = root.focusedScreen();
        root.session = false;
        root.launcherMode = mode;
        root.launcher = true;
    }

    function toggleSession(): void {
        if (!root.session)
            root.screen = root.focusedScreen();
        root.launcher = false;
        root.session = !root.session;
    }

    function closeAll(): void {
        root.launcher = false;
        root.session = false;
    }

    function showOsd(kind: string, value: int, muted: bool): void {
        if (!root.modal)
            root.screen = root.focusedScreen();
        root.osdKind = kind;
        root.osdValue = Math.max(0, Math.min(100, value));
        root.osdMuted = muted;
        root.osd = true;
        osdTimer.restart();
    }

    Timer {
        id: osdTimer
        interval: Tokens.osdTimeout
        onTriggered: root.osd = false
    }
}
