pragma Singleton

// The quote of the hour, read from `karma quote`. It is fetched again when
// the hour changes; unless the hourly visit is switched off or do-not-disturb
// is on, the frame then shows it for a moment (modules/Quote.qml).
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string text: ""
    property string author: ""
    property string source: ""
    readonly property string credit: source !== "" ? author + ", " + source : author

    property bool announce: false
    property int hour: -1

    // Read the current quote; with SHOW, slide it out once it has arrived.
    function refresh(show: bool): void {
        root.announce = show;
        reader.running = true;
    }

    function apply(output: string): void {
        try {
            const quote = JSON.parse(output).data;
            root.text = quote.text ?? "";
            root.author = quote.author ?? "";
            root.source = quote.source ?? "";
            if (root.announce && root.text !== "")
                Ui.showQuote();
        } catch (error) {
            console.warn("karma: cannot read the quote:", error);
        }
        root.announce = false;
    }

    SystemClock {
        precision: SystemClock.Hours
        onHoursChanged: {
            const first = root.hour === -1;
            const changed = root.hour !== hours;
            root.hour = hours;
            if (first)
                root.refresh(false);
            else if (changed)
                root.refresh(Settings.quoteHourly && !Settings.dnd);
        }
    }

    Component.onCompleted: {
        if (root.hour === -1)
            root.refresh(false);
    }

    Process {
        id: reader
        command: [Karma.bin, "quote", "--json"]
        stdout: StdioCollector {
            onStreamFinished: root.apply(this.text)
        }
    }
}
