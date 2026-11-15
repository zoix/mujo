pragma Singleton

// The weather for the place chosen with `mujo weather set`, read from
// `mujo weather` (which keeps the answer for half an hour). Nothing is
// asked while no place is set.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool known: false
    property string place: ""
    property int temperature: 0
    property int high: 0
    property int low: 0
    property int code: 0
    property bool day: true
    property string description: ""

    // Nerd Font glyph for a WMO weather code.
    readonly property string glyph: {
        if (code === 0 || code === 1)
            return day ? "" : "";
        if (code === 45 || code === 48)
            return "";
        if (code >= 71 && code <= 77 || code === 85 || code === 86)
            return "";
        if (code >= 95)
            return "";
        if (code >= 51 && code <= 67 || code >= 80 && code <= 82)
            return "";
        return "";
    }
    readonly property string line: known ? temperature + "° " + description : ""

    function refresh(): void {
        if (Settings.weatherKey === "") {
            root.known = false;
            return;
        }
        reader.running = true;
    }

    function apply(output: string): void {
        try {
            const w = JSON.parse(output).data;
            root.known = w.set === true;
            if (!root.known)
                return;
            root.place = w.place;
            root.temperature = w.temperature;
            root.high = w.high;
            root.low = w.low;
            root.code = w.code;
            root.day = w.day;
            root.description = w.description;
        } catch (error) {
            // No network: keep what was known.
        }
    }

    Connections {
        target: Settings
        function onWeatherKeyChanged(): void {
            root.refresh();
        }
    }

    Timer {
        interval: 900000
        repeat: true
        running: Settings.weatherKey !== ""
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: reader
        command: [Mujo.bin, "weather", "--json"]
        stdout: StdioCollector {
            onStreamFinished: root.apply(this.text)
        }
    }
}
