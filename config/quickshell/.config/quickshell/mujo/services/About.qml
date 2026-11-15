pragma Singleton

// What the card behind the bar's logo shows, from `mujo about`: the machine
// and how mujo is doing. Read when the card opens.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var info: null

    function refresh(): void {
        reader.running = true;
    }

    Process {
        id: reader
        command: [Mujo.bin, "about", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.info = JSON.parse(this.text).data;
                } catch (error) {}
            }
        }
    }
}
