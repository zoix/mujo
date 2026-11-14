// A square button in the bar. Put the icon inside it.
import QtQuick
import qs.theme

Rectangle {
    id: root

    signal clicked
    signal rightClicked
    signal scrolled(up: bool)

    readonly property bool hovered: area.containsMouse
    // The colour under the pointer; set it one step lighter when the
    // button sits on a container that already has the default colour.
    property color hoverColor: Tokens.bgControl

    implicitWidth: Tokens.barButton
    implicitHeight: Tokens.barButton
    radius: Tokens.radiusSm
    color: area.containsMouse ? root.hoverColor : "transparent"

    Behavior on color {
        Fade {}
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => {
            if (event.button === Qt.RightButton)
                root.rightClicked();
            else
                root.clicked();
        }
        onWheel: event => root.scrolled(event.angleDelta.y > 0)
    }
}
