pragma Singleton

// Live network state, for display. With `mujo time auto on`, a change of
// network also has the time zone checked.
import QtQuick
import Quickshell
import Quickshell.Networking

Singleton {
    id: root

    readonly property var devices: Networking.devices.values
    readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wifiNetwork: wifiDevice ? (wifiDevice.networks.values.find(n => n.connected) ?? null) : null
    readonly property bool wired: devices.some(d => d.type === DeviceType.Wired && d.connected)
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property string ssid: wifiNetwork ? wifiNetwork.name : ""
    readonly property int signal: wifiNetwork ? Math.round(wifiNetwork.signalStrength * 100) : 0

    // A new network may be in another time zone. The check waits until the
    // connection has settled; the first one comes shortly after start.
    onSsidChanged: zoneCheck.restart()
    onWiredChanged: zoneCheck.restart()

    Timer {
        id: zoneCheck
        interval: 15000
        running: true
        onTriggered: {
            if (Settings.timeAuto && (root.ssid !== "" || root.wired))
                Mujo.run(["time", "sync"]);
        }
    }
}
