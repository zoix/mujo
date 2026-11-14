// Status icons: network, Bluetooth, audio, do-not-disturb, battery.
// Each opens the terminal UI that controls it, through karma.
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.theme
import qs.components
import qs.services

Rectangle {
    id: root

    required property ShellScreen screen

    // Tell the interface which icon the pointer rests on, and where.
    function hover(button: Item, kind: string): void {
        if (button.hovered)
            Ui.hoverIcon(kind, root.screen.name, button.mapToItem(null, 0, button.height / 2).y);
        else
            Ui.leaveIcon();
    }

    implicitWidth: icons.implicitWidth + Tokens.spaceXs + Tokens.spaceXs
    implicitHeight: icons.implicitHeight + Tokens.spaceXs + Tokens.spaceXs
    radius: Tokens.radiusFull
    color: Tokens.bgBase

    Column {
        id: icons

        x: Tokens.spaceXs
        y: Tokens.spaceXs
        spacing: 0

        BarButton {
            id: netButton
            anchors.horizontalCenter: parent.horizontalCenter
            onHoveredChanged: root.hover(netButton, "net")
            onClicked: Ui.toggleLauncher("wifi")
            onRightClicked: Karma.run(["net", "wifi", "toggle"])

            Glyph {
                anchors.centerIn: parent
                text: Net.wired && Net.ssid === "" ? "" : ""
                color: Net.ssid !== "" || Net.wired ? Tokens.textPrimary : Tokens.borderSubtle
                opacity: Net.ssid === "" || Net.signal >= 50 ? 1 : 0.6
            }
        }

        BarButton {
            id: btButton
            anchors.horizontalCenter: parent.horizontalCenter
            visible: Bluetooth.defaultAdapter !== null
            onHoveredChanged: root.hover(btButton, "bt")
            onClicked: Karma.open(["bt", "tui"])
            onRightClicked: Karma.run(["bt", "power", "toggle"])

            Glyph {
                anchors.centerIn: parent
                text: ""
                color: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled ? Tokens.textPrimary : Tokens.borderSubtle
            }
        }

        BarButton {
            id: audioButton
            anchors.horizontalCenter: parent.horizontalCenter
            onHoveredChanged: root.hover(audioButton, "audio")
            onClicked: Karma.open(["audio", "tui"])
            onRightClicked: Karma.run(["audio", "mute", "toggle"])
            onScrolled: up => Karma.run(["audio", "volume", up ? "+5" : "-5"])

            Glyph {
                anchors.centerIn: parent
                text: Audio.muted || Audio.volume === 0 ? "" : Audio.volume < 50 ? "" : ""
                color: Audio.muted ? Tokens.stateError : Tokens.textPrimary
            }
        }

        BarButton {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: Settings.dnd
            onClicked: Karma.run(["dnd", "off"])

            Glyph {
                anchors.centerIn: parent
                text: ""
                color: Tokens.stateWarning
            }
        }

        BarButton {
            id: batteryButton
            anchors.horizontalCenter: parent.horizontalCenter
            visible: Battery.present
            implicitHeight: battery.implicitHeight + Tokens.spaceSm
            onHoveredChanged: root.hover(batteryButton, "battery")
            onClicked: Ui.toggleLauncher("actions")

            Column {
                id: battery
                anchors.centerIn: parent
                spacing: 0

                Glyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Battery.charging ? "" : Battery.percent > 80 ? "" : Battery.percent > 55 ? "" : Battery.percent > 30 ? "" : Battery.percent > 10 ? "" : ""
                    color: Battery.charging ? Tokens.stateSuccess : Battery.percent <= 10 ? Tokens.stateError : Battery.percent <= 20 ? Tokens.stateWarning : Tokens.textPrimary
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Battery.percent
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                }
            }
        }
    }
}
