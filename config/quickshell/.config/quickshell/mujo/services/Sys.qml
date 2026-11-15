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

    // The connection that carries the traffic: bytes per second between the
    // last two readings, the totals since it came up, and the last two
    // minutes of download speed for a graph.
    property string netInterface: ""
    property string netAddress: ""
    property real netDown: 0
    property real netUp: 0
    property real netReceived: 0
    property real netSent: 0
    property var netHistory: []
    property real lastNetTime: 0

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
        const net = data.net;
        const now = Date.now();
        if (net) {
            const seconds = (now - root.lastNetTime) / 1000;
            if (root.netInterface === net.interface && root.lastNetTime > 0 && seconds > 0) {
                root.netDown = Math.max(0, (net.rx_bytes - root.netReceived) / seconds);
                root.netUp = Math.max(0, (net.tx_bytes - root.netSent) / seconds);
                root.netHistory = root.netHistory.concat([root.netDown]).slice(-60);
            }
            root.netInterface = net.interface;
            root.netAddress = net.address ?? "";
            root.netReceived = net.rx_bytes;
            root.netSent = net.tx_bytes;
            root.lastNetTime = now;
        } else {
            root.netInterface = "";
            root.netDown = 0;
            root.netUp = 0;
        }
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
