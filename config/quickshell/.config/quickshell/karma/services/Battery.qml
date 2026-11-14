pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower

Singleton {
    readonly property UPowerDevice device: UPower.displayDevice
    readonly property bool present: device !== null && device.ready && device.isLaptopBattery
    readonly property int percent: present ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: present && !UPower.onBattery
}
