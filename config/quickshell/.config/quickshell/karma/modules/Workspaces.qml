// Workspaces of one monitor, in a rounded container. Each shows its number
// and the icons of the apps on it. A pill in the accent colour slides to
// the active one. Click to switch.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import qs.theme
import qs.components

Rectangle {
    id: root

    required property ShellScreen screen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property var list: Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor === root.monitor)
    readonly property int activeIndex: list.findIndex(w => w.active)
    // Where the active workspace's slot is; the slot itself reports it.
    property real pillY: 0
    property real pillHeight: cell
    readonly property int cell: Tokens.spaceXl

    // The icon of an app, from its window class.
    function iconFor(toplevel: var): string {
        const name = toplevel.lastIpcObject ? (toplevel.lastIpcObject.class ?? "") : "";
        if (name === "")
            return "";
        const entry = DesktopEntries.heuristicLookup(name);
        return Quickshell.iconPath(entry && entry.icon ? entry.icon : name.toLowerCase(), true);
    }

    implicitWidth: cell + Tokens.spaceXs + Tokens.spaceXs
    implicitHeight: column.implicitHeight + Tokens.spaceXs + Tokens.spaceXs
    radius: Tokens.radiusFull
    color: Tokens.bgControl

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
        x: Tokens.spaceXs
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

        x: Tokens.spaceXs
        y: Tokens.spaceXs

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

                Binding {
                    target: root
                    property: "pillY"
                    value: slot.y
                    when: slot.modelData.active
                }
                Binding {
                    target: root
                    property: "pillHeight"
                    value: slot.height
                    when: slot.modelData.active
                }

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
