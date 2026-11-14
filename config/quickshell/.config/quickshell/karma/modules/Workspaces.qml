// Workspaces of one monitor, in a rounded container. A pill in the accent
// colour slides to the active one. Click a number to switch.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.theme
import qs.components

Rectangle {
    id: root

    required property ShellScreen screen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property var list: Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor === root.monitor)
    readonly property int activeIndex: list.findIndex(w => w.active)
    readonly property int cell: Tokens.spaceXl

    implicitWidth: cell + Tokens.spaceXs + Tokens.spaceXs
    implicitHeight: column.implicitHeight + Tokens.spaceXs + Tokens.spaceXs
    radius: Tokens.radiusFull
    color: Tokens.bgBase

    Behavior on implicitHeight {
        Anim {}
    }

    Rectangle {
        visible: root.activeIndex >= 0
        x: Tokens.spaceXs
        y: Tokens.spaceXs + Math.max(0, root.activeIndex) * root.cell
        width: root.cell
        height: root.cell
        radius: Tokens.radiusFull
        color: Tokens.accent

        Behavior on y {
            Anim {}
        }
    }

    Column {
        id: column

        x: Tokens.spaceXs
        y: Tokens.spaceXs

        Repeater {
            model: ScriptModel {
                values: root.list
            }

            delegate: Item {
                id: slot

                required property HyprlandWorkspace modelData

                width: root.cell
                height: root.cell

                Text {
                    anchors.centerIn: parent
                    text: slot.modelData.id
                    color: slot.modelData.active ? Tokens.textOnAccent : slot.modelData.urgent ? Tokens.stateWarning : area.containsMouse ? Tokens.textPrimary : Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                    font.weight: Tokens.weightEmphasis

                    Behavior on color {
                        Fade {}
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: slot.modelData.activate()
                }
            }
        }
    }
}
