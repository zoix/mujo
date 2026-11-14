// One choice in a row of choices inside a page. The chosen one is outlined
// in the accent colour; the filled accent pill is kept for the page tabs.
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
    color: root.chosen ? Tokens.group : area.containsMouse ? Tokens.bgControl : Tokens.bgBase
    border.width: root.chosen ? Tokens.borderThin : 0
    border.color: Tokens.accent

    Behavior on color {
        Fade {}
    }

    Text {
        id: text
        anchors.centerIn: parent
        text: root.label
        color: root.chosen ? Tokens.accent : Tokens.textPrimary
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
