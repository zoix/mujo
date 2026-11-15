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

    // open(["net", "tui"]): the same command in a floating terminal.
    function open(args: list<string>): void {
        run(args.concat(["--window"]));
    }
}
