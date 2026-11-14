// The vertical bar on the left edge: launcher, workspaces, window title,
// tray, status icons, clock, power.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.theme
import qs.components
import qs.services

Item {
    id: root

    required property ShellScreen screen
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)
    readonly property HyprlandToplevel toplevel: Hyprland.activeToplevel
    // Hyprland keeps the last focused window as "active" on an empty
    // workspace, so the title is shown only while its workspace is in view.
    readonly property string title: toplevel && monitor && toplevel.workspace === monitor.activeWorkspace ? toplevel.title : ""

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Tokens.spaceMd
        anchors.bottomMargin: Tokens.spaceMd
        spacing: Tokens.spaceMd

        BarButton {
            Layout.alignment: Qt.AlignHCenter
            onClicked: Ui.toggleLauncher("apps")
            onRightClicked: Ui.toggleLauncher("actions")

            Glyph {
                anchors.centerIn: parent
                text: ""
                color: Tokens.accent
            }
        }

        Workspaces {
            Layout.alignment: Qt.AlignHCenter
            screen: root.screen
        }

        // The focused window's title, written bottom to top.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Text {
                anchors.centerIn: parent
                width: parent.height
                rotation: -90
                text: root.title
                color: Tokens.textMuted
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontSm
            }
        }

        Tray {
            Layout.alignment: Qt.AlignHCenter
        }

        Status {
            Layout.alignment: Qt.AlignHCenter
        }

        Clock {
            Layout.alignment: Qt.AlignHCenter
        }

        BarButton {
            Layout.alignment: Qt.AlignHCenter
            onClicked: Ui.toggleSession()

            Glyph {
                anchors.centerIn: parent
                text: ""
                color: Tokens.stateError
            }
        }
    }
}
