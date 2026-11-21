// System tray. Resting the pointer on an item, or a right click, opens its
// menu in the pop-out beside the bar; a left click activates the item.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.theme
import qs.components
import qs.services

Column {
    id: root

    required property ShellScreen screen

    spacing: Tokens.spaceXs

    Repeater {
        model: SystemTray.items

        delegate: BarButton {
            id: button

            required property SystemTrayItem modelData

            // The menu opens in the pop-out beside the bar, in mujo's style.
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
            // Moving to the next icon reports "entered" before "left", so a
            // leave only counts while the pop-out still shows this menu.
            onHoveredChanged: {
                if (hovered && modelData.hasMenu)
                    Ui.hoverTray(modelData.menu, root.screen.name, button.mapToItem(null, 0, button.height / 2).y);
                else if (!hovered && Ui.trayMenu === modelData.menu)
                    Ui.leaveIcon("tray");
            }

            IconImage {
                anchors.centerIn: parent
                implicitSize: Tokens.fontXl
                source: button.modelData.icon
            }
        }
    }
}
