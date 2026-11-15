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

        // The logo: a click shows the card about this machine and mujo's
        // health; a right click opens the menu of every mujo command.
        BarButton {
            id: logo
            Layout.alignment: Qt.AlignHCenter
            // Down a little, so the top of the gate is level with the top
            // of the windows beside it.
            Layout.topMargin: Tokens.spaceXs + Tokens.borderThin
            // No box behind the logo under the pointer; the logo lights up instead.
            hoverColor: "transparent"
            onClicked: Ui.toggleAbout(root.screen.name, logo.mapToItem(null, 0, logo.height / 2).y)
            onRightClicked: Ui.toggleLauncher("actions")
            onHoveredChanged: {
                if (!hovered)
                    Ui.leaveIcon("about");
            }

            Logo {
                anchors.centerIn: parent
                size: Tokens.icon
                color: logo.hovered ? Tokens.textPrimary : Tokens.accent
                dotColor: logo.hovered ? Tokens.accent : Tokens.textPrimary
            }
        }

        Workspaces {
            Layout.alignment: Qt.AlignHCenter
            screen: root.screen
        }

        // The focused window's title, written bottom to top. Resting the
        // pointer on it shows details and actions for that window.
        Item {
            id: titleArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            HoverHandler {
                onHoveredChanged: {
                    if (hovered && root.title !== "") {
                        Hyprland.refreshToplevels();
                        Ui.hoverIcon("window", root.screen.name, titleArea.mapToItem(null, 0, titleArea.height / 2).y);
                    } else {
                        Ui.leaveIcon("window");
                    }
                }
            }

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
            screen: root.screen
        }

        Status {
            Layout.alignment: Qt.AlignHCenter
            screen: root.screen
        }

        Clock {
            Layout.alignment: Qt.AlignHCenter

            TapHandler {
                onTapped: Ui.toggleDashboard("today")
            }
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
