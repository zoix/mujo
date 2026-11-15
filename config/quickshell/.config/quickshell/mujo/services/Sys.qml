pragma Singleton

// Processor, memory, temperature and disk figures for the dashboard, read
// from `mujo sys` every two seconds while something is watching.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Set by whoever shows the figures; nothing is polled otherwise.
    property bool watching: false

    property int cpu: 0          // percent, between the last two readings
    property int cores: 0
    property int memory: 0       // percent
    property real memoryUsed: 0  // GiB
    property real memoryTotal: 0
    property int temperature: -1 // °C, -1 without a sensor
    property int disk: 0         // percent
    property int uptime: 0       // seconds

    property real lastTotal: 0
    property real lastIdle: 0

    function apply(text: string): void {
        let data;
        try {
            data = JSON.parse(text).data;
        } catch (error) {
            return;
        }
        const total = data.cpu.total - root.lastTotal;
        const idle = data.cpu.idle - root.lastIdle;
        if (root.lastTotal > 0 && total > 0)
            root.cpu = Math.round((total - idle) * 100 / total);
        root.lastTotal = data.cpu.total;
        root.lastIdle = data.cpu.idle;
        root.cores = data.cpu.cores;
        root.memory = data.memory.percent;
        root.memoryTotal = data.memory.total_kb / 1048576;
        root.memoryUsed = (data.memory.total_kb - data.memory.available_kb) / 1048576;
        root.temperature = data.temperature_c ?? -1;
        root.disk = data.disk.percent;
        root.uptime = data.uptime_s;
    }

    onWatchingChanged: {
        if (watching)
            reader.running = true;
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.watching
        onTriggered: reader.running = true
    }

    Process {
        id: reader
        command: [Mujo.bin, "sys", "--json"]
        stdout: StdioCollector {
            onStreamFinished: root.apply(this.text)
        }
    }
}
