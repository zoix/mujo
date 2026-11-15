pragma Singleton

// The only way the UI changes anything: it runs the mujo CLI.
import QtQuick
import Quickshell

Singleton {
    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/mujo"

    // run(["audio", "mute", "toggle"])
    function run(args: list<string>): void {
        Quickshell.execDetached([bin].concat(args));
    }

    // The icon for a window class. mujo's own windows (mujo.tui.net, mujo.drop,
    // ...) have no desktop entry and share the mujo icon.
    function appIcon(windowClass: string): string {
        if (windowClass === "")
            return "";
        if (windowClass.startsWith("mujo."))
            return Quickshell.iconPath("mujo", true);
        const entry = DesktopEntries.heuristicLookup(windowClass);
        return Quickshell.iconPath(entry && entry.icon ? entry.icon : windowClass.toLowerCase(), true);
    }

    // open(["net", "tui"]): the same command in a floating terminal.
    function open(args: list<string>): void {
        run(args.concat(["--window"]));
    }
}
