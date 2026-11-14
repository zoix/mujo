pragma Singleton

// Live network state, for display only.
import QtQuick
import Quickshell
import Quickshell.Networking

Singleton {
    readonly property var devices: Networking.devices.values
    readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wifiNetwork: wifiDevice ? (wifiDevice.networks.values.find(n => n.connected) ?? null) : null
    readonly property bool wired: devices.some(d => d.type === DeviceType.Wired && d.connected)
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property string ssid: wifiNetwork ? wifiNetwork.name : ""
    readonly property int signal: wifiNetwork ? Math.round(wifiNetwork.signalStrength * 100) : 0
}
