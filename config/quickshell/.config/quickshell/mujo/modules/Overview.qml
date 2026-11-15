// Every workspace as a miniature of its screen, with the windows on it.
// Click a miniature to go there, or move with the arrow keys (or H and L,
// or Tab) and press Enter. Shown as a page of the dashboard.
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
    // The miniature the keyboard is on.
    property int index: 0

    function step(by: int): void {
        if (root.spaces.length > 0)
            root.index = (root.index + by + root.spaces.length) % root.spaces.length;
    }

    function go(): void {
        const space = root.spaces[root.index];
        if (space)
            space.activate();
        Ui.closeDashboard();
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                Ui.closeDashboard();
            } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_1) {
                // Tab changes page, as in quick settings.
                Ui.dashboardPage = "today";
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_3) {
                Ui.dashboardPage = "activity";
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_L || event.key === Qt.Key_J) {
                root.step(1);
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_H || event.key === Qt.Key_K) {
                root.step(-1);
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.go();
            } else {
                return;
            }
            event.accepted = true;
        }
    }

    spacing: Tokens.spaceSm

    onActiveChanged: {
        if (!active)
            return;
        Hyprland.refreshToplevels();
        // Start on the workspace in view.
        root.index = Math.max(0, root.spaces.findIndex(w => w.focused));
        keys.forceActiveFocus();
    }

    Repeater {
        model: ScriptModel {
            values: root.spaces
        }

        delegate: Rectangle {
            id: mini

            required property HyprlandWorkspace modelData
            required property int index
            readonly property bool chosen: root.index === index
            readonly property HyprlandMonitor monitor: modelData.monitor
            // Screen size in the layout's units, and how much the miniature shrinks it.
            readonly property real screenWidth: monitor ? monitor.width / monitor.scale : 1
            readonly property real screenHeight: monitor ? monitor.height / monitor.scale : 1
            readonly property real factor: width / screenWidth

            width: Tokens.card
            height: width * screenHeight / screenWidth
            radius: Tokens.radiusMd
            color: Tokens.bgBase
            border.width: mini.chosen ? Tokens.borderFocus + Tokens.borderThin : 0
            border.color: Tokens.accent
            clip: true
            scale: mini.chosen ? 1 : 0.94

            Behavior on scale {
                Anim {}
            }

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
                        source: Mujo.appIcon(win.info.class ?? "")
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
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.index = mini.index
                onClicked: root.go()
            }
        }
    }
}
