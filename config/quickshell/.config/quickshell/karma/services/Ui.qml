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

    // The dashboard: pinned open by a key, or open while the pointer is on it.
    property bool dashboard: false
    property string dashboardPage: "today"   // today | workspaces

    // The pop-out beside a bar icon: which one ("" = none), on which screen
    // and at what height. It opens a moment after the pointer rests on an
    // icon and closes a moment after it has left both icon and pop-out.
    property string popout: ""
    property string popoutScreen: ""
    property real popoutY: 0
    property string popoutWanted: ""
    property bool popoutHeld: false

    function hoverIcon(kind: string, screen: string, y: real): void {
        root.popoutWanted = kind;
        root.popoutScreen = screen;
        root.popoutY = y;
        popoutClose.stop();
        if (root.popout !== "")
            root.popout = kind;
        else
            popoutOpen.restart();
    }

    // The pointer left the icon of KIND. Moving from one icon to its
    // neighbour reports "entered the new one" before "left the old one", so
    // a leave only counts if it is for the icon the pop-out is showing.
    function leaveIcon(kind: string): void {
        if (kind !== root.popoutWanted)
            return;
        popoutOpen.stop();
        if (!root.popoutHeld)
            popoutClose.restart();
    }

    function holdPopout(held: bool): void {
        root.popoutHeld = held;
        if (held)
            popoutClose.stop();
        else
            popoutClose.restart();
    }

    Timer {
        id: popoutOpen
        interval: 350
        onTriggered: root.popout = root.popoutWanted
    }

    Timer {
        id: popoutClose
        interval: 300
        onTriggered: root.popout = ""
    }

    // A wallpaper being tried in the picker, shown before karma has applied it.
    property string wallPreview: ""

    property bool osd: false
    property string osdKind: "volume"
    property int osdValue: 0
    property bool osdMuted: false

    // The screenshot area picker (modules/Picker.qml), on the focused screen.
    property bool picker: false

    function openPicker(): void {
        root.closeAll();
        root.screen = root.focusedScreen();
        root.picker = true;
    }

    // The quick-settings panel on the right edge.
    property bool sidebar: false

    // The menu of a tray icon, shown in the pop-out beside the bar.
    property var trayMenu: null

    // The workspace overview takes the keyboard (arrows, Enter, Escape).
    readonly property bool overview: dashboard && dashboardPage === "workspaces"

    readonly property bool modal: launcher || session || sidebar || overview

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
        root.sidebar = false;
        root.launcherMode = mode;
        root.launcher = true;
    }

    // Asking for the page that is already open closes the dashboard.
    function toggleDashboard(page: string): void {
        if (root.dashboard && root.dashboardPage === page) {
            root.closeDashboard();
            return;
        }
        root.screen = root.focusedScreen();
        root.dashboardPage = page;
        root.dashboard = true;
    }

    // Closing the dashboard puts it back on its first page, once it has
    // slid away, so that the top edge always opens "Today".
    function closeDashboard(): void {
        root.dashboard = false;
        dashboardReset.restart();
    }

    Timer {
        id: dashboardReset
        interval: Tokens.durationSlow + 50
        onTriggered: {
            if (!root.dashboard)
                root.dashboardPage = "today";
        }
    }

    function toggleSidebar(): void {
        if (!root.sidebar)
            root.screen = root.focusedScreen();
        root.launcher = false;
        root.session = false;
        root.sidebar = !root.sidebar;
    }

    function showTrayMenu(menu: var, screen: string, y: real): void {
        root.trayMenu = menu;
        root.popoutScreen = screen;
        root.popoutY = y;
        root.popoutWanted = "tray";
        popoutOpen.stop();
        popoutClose.stop();
        root.popout = "tray";
    }

    function toggleSession(): void {
        if (!root.session)
            root.screen = root.focusedScreen();
        root.launcher = false;
        root.sidebar = false;
        root.session = !root.session;
    }

    function closeAll(): void {
        root.launcher = false;
        root.session = false;
        root.sidebar = false;
        if (root.dashboard)
            root.closeDashboard();
    }

    function showOsd(kind: string, value: int, muted: bool): void {
        // Not while a panel with its own volume or brightness slider is
        // open: the slider already shows the level.
        if (root.sidebar || root.popout === "audio")
            return;
        if (!root.modal)
            root.screen = root.focusedScreen();
        root.osdKind = kind;
        root.osdValue = Math.max(0, Math.min(100, value));
        root.osdMuted = muted;
        root.osd = true;
        root.popout = "";
        osdTimer.restart();
    }

    // The quote of the hour, visiting on the top edge.
    property bool quote: false

    function showQuote(): void {
        if (root.dashboard)
            return;
        root.quote = true;
        quoteTimer.restart();
    }

    Timer {
        id: quoteTimer
        interval: Tokens.quoteTimeout
        onTriggered: root.quote = false
    }

    Timer {
        id: osdTimer
        interval: Tokens.osdTimeout
        onTriggered: root.osd = false
    }
}
