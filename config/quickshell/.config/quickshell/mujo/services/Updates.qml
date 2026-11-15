pragma Singleton

// How many packages are waiting to be upgraded, from `mujo update check`
// (which keeps its answer for an hour).
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int count: 0
    property var names: []

    function refresh(): void {
        reader.running = true;
    }

    // The first look waits until the session has settled.
    Timer {
        interval: 60000
        running: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 1800000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Process {
        id: reader
        command: [Mujo.bin, "update", "check", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const u = JSON.parse(this.text).data;
                    root.count = u.count ?? 0;
                    root.names = (u.repo ?? []).concat(u.aur ?? []);
                } catch (error) {}
            }
        }
    }
}
