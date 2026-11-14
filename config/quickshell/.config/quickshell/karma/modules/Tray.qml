// System tray. Left click activates an item, right click opens its menu.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.theme
import qs.components

Column {
    id: root

    spacing: Tokens.spaceXs

    Repeater {
        model: SystemTray.items

        delegate: BarButton {
            id: button

            required property SystemTrayItem modelData

            anchors.horizontalCenter: parent.horizontalCenter
            onClicked: modelData.onlyMenu && modelData.hasMenu ? menu.open() : modelData.activate()
            onRightClicked: {
                if (modelData.hasMenu)
                    menu.open();
                else
                    modelData.secondaryActivate();
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: Tokens.fontXl
                source: button.modelData.icon
            }

            QsMenuAnchor {
                id: menu
                menu: button.modelData.menu
                anchor.item: button
                anchor.edges: Edges.Right
                anchor.gravity: Edges.Right
            }
        }
    }
}
