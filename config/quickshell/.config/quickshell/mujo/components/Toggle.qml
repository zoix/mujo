// A large on/off tile for the quick-settings panel.
import QtQuick
import qs.theme

Rectangle {
    id: root

    property bool on: false
    property string glyph: ""
    property string label: ""
    signal clicked

    implicitWidth: (Tokens.notificationWidth - Tokens.spaceSm) / 2
    implicitHeight: Tokens.button
    radius: Tokens.radiusLg
    color: root.on ? Tokens.accent : area.containsMouse ? Tokens.bgControl : Tokens.bgBase

    Behavior on color {
        Fade {}
    }

    Glyph {
        id: icon
        anchors.left: parent.left
        anchors.leftMargin: Tokens.spaceMd
        anchors.verticalCenter: parent.verticalCenter
        text: root.glyph
        font.pixelSize: Tokens.fontLg
        color: root.on ? Tokens.textOnAccent : Tokens.textPrimary
    }

    Text {
        anchors.left: icon.right
        anchors.leftMargin: Tokens.spaceSm
        anchors.right: parent.right
        anchors.rightMargin: Tokens.spaceSm
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.on ? Tokens.textOnAccent : Tokens.textPrimary
        elide: Text.ElideRight
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
