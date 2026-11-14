// One choice in a row of choices.
import QtQuick
import qs.theme

Rectangle {
    id: root

    property bool chosen: false
    property string label: ""
    signal clicked

    implicitWidth: text.implicitWidth + Tokens.spaceLg + Tokens.spaceLg
    implicitHeight: text.implicitHeight + Tokens.spaceSm + Tokens.spaceSm
    radius: Tokens.radiusFull
    color: root.chosen ? Tokens.accent : area.containsMouse ? Tokens.bgControl : Tokens.bgBase

    Behavior on color {
        Fade {}
    }

    Text {
        id: text
        anchors.centerIn: parent
        text: root.label
        color: root.chosen ? Tokens.textOnAccent : Tokens.textPrimary
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSm
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
