// A horizontal slider, 0 to 100. Reports the wanted value once the pointer
// has rested, so that a drag is one change and not hundreds.
import QtQuick
import qs.theme

Item {
    id: root

    property int value: 0
    property bool dim: false
    signal moved(value: int)

    implicitWidth: Tokens.notificationWidth
    implicitHeight: Tokens.spaceXl

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: Tokens.spaceSm
        radius: Tokens.radiusFull
        color: Tokens.bgControl

        Rectangle {
            width: parent.width * Math.max(0, Math.min(100, root.value)) / 100
            height: parent.height
            radius: Tokens.radiusFull
            color: root.dim ? Tokens.textMuted : Tokens.accent

            Behavior on width {
                Anim {
                    duration: Tokens.durationFast
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        property int wanted: -1

        function ask(x: real): void {
            wanted = Math.max(0, Math.min(100, Math.round(x * 100 / width)));
            send.restart();
        }

        onPressed: event => ask(event.x)
        onPositionChanged: event => {
            if (pressed)
                ask(event.x);
        }

        Timer {
            id: send
            interval: Tokens.durationFast
            onTriggered: root.moved(parent.wanted)
        }
    }
}
