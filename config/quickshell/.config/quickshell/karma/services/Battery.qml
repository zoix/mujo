pragma Singleton

// The battery, as UPower reports it. Two things follow from it: a warning
// when it runs low, and, with `karma power auto on`, the power profile that
// suits the power source.
import QtQuick
import Quickshell
import Quickshell.Services.UPower

Singleton {
    id: root

    readonly property UPowerDevice device: UPower.displayDevice
    readonly property bool present: device !== null && device.ready && device.isLaptopBattery
    readonly property int percent: present ? Math.round(device.percentage * 100) : 0
    readonly property bool charging: present && !UPower.onBattery

    // The level last warned about, so each warning is given once per discharge.
    property int warned: 100

    function warn(urgency: string, title: string, body: string): void {
        Quickshell.execDetached(["notify-send", "-a", "karma", "-u", urgency, "-t", "10000", title, body]);
    }

    onPercentChanged: {
        if (!present || charging)
            return;
        if (percent <= 10 && warned > 10) {
            warned = 10;
            warn("critical", "Battery at " + percent + "%", "Plug in the charger soon.");
        } else if (percent <= 20 && warned > 20) {
            warned = 20;
            warn("normal", "Battery at " + percent + "%", "Time to find the charger.");
        }
    }

    onChargingChanged: {
        if (charging)
            warned = 100;
        sync();
    }

    function sync(): void {
        if (present && Settings.powerAuto)
            Karma.run(["power", "sync"]);
    }

    // The charger may have been plugged or pulled while nobody was looking
    // (before login, during suspend), so the profile is also checked once
    // the battery is known and shortly after start.
    onPresentChanged: sync()

    Timer {
        interval: 5000
        running: true
        onTriggered: root.sync()
    }
}
