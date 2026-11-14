// The frame around one screen, the bar on its left edge, and the panels
// that grow out of the frame: launcher (bottom), dashboard (top), power menu
// (right), volume and brightness display and icon pop-outs (left, beside
// the bar's status icons), notifications (top-right corner).
//
// One full-screen window on the top layer draws all of it. Only the bar and
// open panels take input; the rest of the window lets clicks through to the
// apps below. Four invisible windows reserve the space so that apps stay
// inside the frame.
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.theme
import qs.components
import qs.services

Scope {
    id: root

    required property ShellScreen screen
    // The launcher, power menu and volume display open on one screen at a time.
    readonly property bool here: Ui.screen === screen.name
    readonly property bool focused: Hyprland.focusedMonitor !== null && Hyprland.focusedMonitor.name === screen.name

    PanelWindow {
        id: overlay

        screen: root.screen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "karma-frame"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // While the launcher or the power menu is open the window takes the
        // keyboard, and a click anywhere outside the panel closes it.
        WlrLayershell.keyboardFocus: root.here && Ui.modal ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        mask: Region {
            item: root.here && Ui.modal ? scrim : bar

            Region {
                item: notifications
            }
            Region {
                item: topEdge
            }
            Region {
                item: dashboard
            }
            Region {
                item: popout
            }
        }

        MouseArea {
            id: scrim
            anchors.fill: parent
            enabled: root.here && Ui.modal
            onClicked: Ui.closeAll()
        }

        // The screen dims a little behind the power menu.
        Rectangle {
            anchors.fill: parent
            color: Tokens.bgFrame
            opacity: root.here && Ui.session ? 0.45 : 0

            Behavior on opacity {
                Anim {}
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                fillColor: Tokens.bgFrame
                fillRule: ShapePath.OddEvenFill

                PathRectangle {
                    width: overlay.width
                    height: overlay.height
                }

                PathRectangle {
                    x: Tokens.bar
                    y: Tokens.frame
                    width: overlay.width - Tokens.bar - Tokens.frame
                    height: overlay.height - Tokens.frame - Tokens.frame
                    radius: Tokens.radiusXl
                }
            }
        }

        Bar {
            id: bar
            screen: root.screen
            width: Tokens.bar
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
        }

        Drawer {
            edge: "bottom"
            open: root.here && Ui.launcher

            Launcher {
                active: root.here && Ui.launcher
            }
        }

        Drawer {
            edge: "right"
            open: root.here && Ui.session

            Session {
                active: root.here && Ui.session
            }
        }

        Drawer {
            edge: "right"
            open: root.here && Ui.sidebar

            Sidebar {
                active: root.here && Ui.sidebar
            }
        }

        // The dashboard opens when the pointer touches the middle of the top
        // edge, and stays while the pointer is on it. A key can pin it open.
        Item {
            id: topEdge
            x: dashboard.x
            width: dashboard.along
            height: Tokens.frame

            HoverHandler {
                id: edgeHover
            }
        }

        Timer {
            id: dashboardLinger
            interval: 400
            running: !edgeHover.hovered && !dashboardHover.hovered
            onTriggered: overlay.dashboardHovered = false
        }

        property bool dashboardHovered: false

        Connections {
            target: edgeHover
            function onHoveredChanged(): void {
                if (edgeHover.hovered)
                    overlay.dashboardHovered = true;
            }
        }

        Drawer {
            id: dashboard
            edge: "top"
            open: overlay.dashboardHovered || root.here && Ui.dashboard

            Dashboard {
                active: dashboard.open
            }

            HoverHandler {
                id: dashboardHover
            }
        }

        // Details beside a bar icon while the pointer rests on it.
        Drawer {
            id: popout
            edge: "left"
            centre: Ui.popoutY
            open: Ui.popout !== "" && Ui.popoutScreen === root.screen.name && !Ui.osd

            Popout {}

            HoverHandler {
                onHoveredChanged: Ui.holdPopout(hovered)
            }
        }

        // Next to the volume and brightness icons it reports on.
        Drawer {
            edge: "left"
            atEnd: true
            open: root.here && Ui.osd

            Osd {}
        }

        Notifications {
            id: notifications
            shown: root.focused
        }
    }

    component Reserve: PanelWindow {
        screen: root.screen
        color: "transparent"
        implicitWidth: 1
        implicitHeight: 1
        WlrLayershell.namespace: "karma-reserve"
        mask: Region {}
    }

    Reserve {
        exclusiveZone: Tokens.bar
        anchors {
            left: true
            top: true
            bottom: true
        }
    }

    Reserve {
        exclusiveZone: Tokens.frame
        anchors {
            right: true
            top: true
            bottom: true
        }
    }

    Reserve {
        exclusiveZone: Tokens.frame
        anchors {
            top: true
            left: true
            right: true
        }
    }

    Reserve {
        exclusiveZone: Tokens.frame
        anchors {
            bottom: true
            left: true
            right: true
        }
    }
}
