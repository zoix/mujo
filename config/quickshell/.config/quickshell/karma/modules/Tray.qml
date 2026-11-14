// System tray. Left click activates an item, right click opens its menu
// in the pop-out beside the bar.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.theme
import qs.components

Column {
    id: root

    required property ShellScreen screen

    spacing: Tokens.spaceXs

    Repeater {
        model: SystemTray.items

        delegate: BarButton {
            id: button

            required property SystemTrayItem modelData

            // The menu opens in the pop-out beside the bar, in karma's style.
            function menu(): void {
                Ui.showTrayMenu(modelData.menu, root.screen.name, button.mapToItem(null, 0, button.height / 2).y);
            }

            anchors.horizontalCenter: parent.horizontalCenter
            onClicked: modelData.onlyMenu && modelData.hasMenu ? button.menu() : modelData.activate()
            onRightClicked: {
                if (modelData.hasMenu)
                    button.menu();
                else
                    modelData.secondaryActivate();
            }
            onHoveredChanged: {
                if (!hovered)
                    Ui.leaveIcon();
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: Tokens.fontXl
                source: button.modelData.icon
            }
        }
    }
}
