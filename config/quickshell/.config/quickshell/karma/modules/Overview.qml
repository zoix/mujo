// Every workspace as a miniature of its screen, with the windows on it.
// Click a miniature to go there. Shown as a page of the dashboard.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.theme
import qs.components
import qs.services

Flow {
    id: root

    property bool active: false
    readonly property var spaces: Hyprland.workspaces.values.filter(w => w.id > 0)

    spacing: Tokens.spaceSm

    onActiveChanged: {
        if (active)
            Hyprland.refreshToplevels();
    }

    Repeater {
        model: ScriptModel {
            values: root.spaces
        }

        delegate: Rectangle {
            id: mini

            required property HyprlandWorkspace modelData
            readonly property HyprlandMonitor monitor: modelData.monitor
            // Screen size in the layout's units, and how much the miniature shrinks it.
            readonly property real screenWidth: monitor ? monitor.width / monitor.scale : 1
            readonly property real screenHeight: monitor ? monitor.height / monitor.scale : 1
            readonly property real factor: width / screenWidth

            width: Tokens.card
            height: width * screenHeight / screenWidth
            radius: Tokens.radiusMd
            color: Tokens.bgBase
            border.width: modelData.focused ? Tokens.borderFocus : 0
            border.color: Tokens.accent
            clip: true

            Repeater {
                model: mini.modelData.toplevels

                delegate: Rectangle {
                    id: win

                    required property HyprlandToplevel modelData
                    readonly property var info: modelData.lastIpcObject ?? ({})
                    readonly property var at: info.at ?? [0, 0]
                    readonly property var size: info.size ?? [0, 0]

                    x: (at[0] - (mini.monitor ? mini.monitor.x : 0)) * mini.factor
                    y: (at[1] - (mini.monitor ? mini.monitor.y : 0)) * mini.factor
                    width: size[0] * mini.factor
                    height: size[1] * mini.factor
                    radius: Tokens.radiusSm
                    color: Tokens.bgControl
                    border.width: Tokens.borderThin
                    border.color: win.modelData.activated ? Tokens.accent : Tokens.borderSubtle
                    clip: true

                    // A still picture of the window, where the compositor provides one.
                    ScreencopyView {
                        anchors.fill: parent
                        captureSource: root.active ? win.modelData.wayland : null
                        live: false
                    }

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: Math.min(Tokens.icon, parent.height - Tokens.spaceXs)
                        source: {
                            const name = win.info.class ?? "";
                            const entry = name !== "" ? DesktopEntries.heuristicLookup(name) : null;
                            return name === "" ? "" : Quickshell.iconPath(entry && entry.icon ? entry.icon : name.toLowerCase(), true);
                        }
                    }
                }
            }

            Rectangle {
                x: Tokens.spaceXs
                y: Tokens.spaceXs
                width: label.implicitWidth + Tokens.spaceSm + Tokens.spaceSm
                height: label.implicitHeight + Tokens.spaceXs
                radius: Tokens.radiusFull
                color: mini.modelData.focused ? Tokens.accent : Tokens.bgFrame

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: mini.modelData.id
                    color: mini.modelData.focused ? Tokens.textOnAccent : Tokens.textPrimary
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                    font.weight: Tokens.weightEmphasis
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    mini.modelData.activate();
                    Ui.dashboard = false;
                }
            }
        }
    }
}
