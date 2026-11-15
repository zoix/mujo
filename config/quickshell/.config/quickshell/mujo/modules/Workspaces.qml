// Workspaces of one monitor, in a rounded container. Each shows its number
// and the icons of the apps on it. A pill in the accent colour slides to
// the active one. Click to switch.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import qs.services
import qs.theme
import qs.components

Rectangle {
    id: root

    required property ShellScreen screen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property var list: Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor === root.monitor).sort((a, b) => a.id - b.id)
    readonly property int activeIndex: list.findIndex(w => w.active)
    // The pill covers the active workspace's slot: its number and its icons.
    readonly property Item activeSlot: slots.count > 0 && activeIndex >= 0 ? slots.itemAt(activeIndex) : null
    readonly property real pillY: activeSlot ? activeSlot.y : 0
    readonly property real pillHeight: activeSlot ? activeSlot.height : cell
    readonly property int cell: Tokens.spaceXl

    // The icon of an app, from its window class.
    function iconFor(toplevel: var): string {
        return Mujo.appIcon(toplevel.lastIpcObject ? (toplevel.lastIpcObject.class ?? "") : "");
    }

    implicitWidth: cell + Tokens.borderFocus + Tokens.borderFocus
    implicitHeight: column.implicitHeight + Tokens.spaceXs + Tokens.spaceXs
    radius: Tokens.radiusFull
    color: Tokens.group

    // Windows that were open before the interface started have no class
    // yet; ask Hyprland for the list once.
    Component.onCompleted: Hyprland.refreshToplevels()

    // Window classes arrive a moment after a window opens.
    Connections {
        target: Hyprland
        function onRawEvent(event: var): void {
            if (event.name === "openwindow" || event.name === "closewindow" || event.name === "movewindow")
                Hyprland.refreshToplevels();
        }
    }

    Rectangle {
        visible: root.activeIndex >= 0
        x: Tokens.borderFocus
        y: Tokens.spaceXs + root.pillY
        width: root.cell
        height: root.pillHeight
        radius: Tokens.radiusFull
        color: Tokens.accent

        Behavior on y {
            Anim {}
        }
        Behavior on height {
            Anim {}
        }
    }

    Column {
        id: column

        x: Tokens.borderFocus
        y: Tokens.spaceXs
        // Room between workspaces, so one's icons are not read as the next one's.
        spacing: Tokens.spaceSm

        Repeater {
            id: slots

            model: ScriptModel {
                values: root.list
            }

            delegate: Item {
                id: slot

                required property HyprlandWorkspace modelData
                readonly property var icons: modelData.toplevels.values.map(t => root.iconFor(t)).filter(i => i !== "").slice(0, 3)

                width: root.cell
                height: inner.implicitHeight + Tokens.spaceXs + Tokens.spaceXs

                Column {
                    id: inner
                    anchors.centerIn: parent
                    spacing: Tokens.spaceXs

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: slot.modelData.id
                        color: slot.modelData.active ? Tokens.textOnAccent : slot.modelData.urgent ? Tokens.stateWarning : area.containsMouse ? Tokens.textPrimary : Tokens.textMuted
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontSm
                        font.weight: Tokens.weightEmphasis

                        Behavior on color {
                            Fade {}
                        }
                    }

                    Repeater {
                        model: slot.icons

                        delegate: IconImage {
                            required property string modelData
                            anchors.horizontalCenter: parent.horizontalCenter
                            implicitSize: Tokens.fontLg
                            source: modelData
                        }
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
