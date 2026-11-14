// Content of the volume and brightness panel on the right edge: the level
// as a number, a vertical bar and an icon. karma triggers it over IPC.
import QtQuick
import qs.theme
import qs.components
import qs.services

Item {
    id: root

    implicitWidth: Tokens.osdWidth + Tokens.spaceSm
    implicitHeight: Tokens.osdHeight

    Text {
        id: label
        anchors.top: parent.top
        anchors.topMargin: Tokens.spaceLg
        anchors.horizontalCenter: parent.horizontalCenter
        text: Ui.osdValue
        color: Tokens.textPrimary
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSm
        font.weight: Tokens.weightEmphasis
    }

    Rectangle {
        anchors.top: label.bottom
        anchors.bottom: icon.top
        anchors.topMargin: Tokens.spaceSm
        anchors.bottomMargin: Tokens.spaceSm
        anchors.horizontalCenter: parent.horizontalCenter
        width: Tokens.spaceMd
        radius: Tokens.radiusFull
        color: Tokens.bgControl

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height * Ui.osdValue / 100
            radius: Tokens.radiusFull
            color: Ui.osdMuted ? Tokens.textMuted : Tokens.accent

            Behavior on height {
                Anim {
                    duration: Tokens.durationFast
                }
            }
            Behavior on color {
                Fade {}
            }
        }
    }

    Glyph {
        id: icon
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.spaceLg
        anchors.horizontalCenter: parent.horizontalCenter
        font.pixelSize: Tokens.fontLg
        color: Ui.osdMuted ? Tokens.stateError : Tokens.textPrimary
        text: Ui.osdKind === "brightness" ? "" : Ui.osdKind === "microphone" ? (Ui.osdMuted ? "" : "") : Ui.osdMuted || Ui.osdValue === 0 ? "" : Ui.osdValue < 50 ? "" : ""
    }
}
