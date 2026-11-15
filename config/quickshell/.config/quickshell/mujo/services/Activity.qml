pragma Singleton

// What the dashboard's Activity page shows besides live figures, from
// `mujo sys activity`: the latest changes, the battery's last day and the
// newest screenshots and recordings. Read when the page comes into view.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var changes: []
    property var battery: []     // [[seconds ago, percent], ...], oldest first
    property var captures: []

    function refresh(): void {
        reader.running = true;
    }

    Process {
        id: reader
        command: [Mujo.bin, "sys", "activity", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text).data;
                    root.changes = data.changes;
                    root.battery = data.battery;
                    root.captures = data.captures;
                } catch (error) {}
            }
        }
    }
}
