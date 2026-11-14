// Hours over minutes.
import QtQuick
import Quickshell
import qs.theme

Column {
    spacing: 0

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDateTime(clock.date, "HH")
        color: Tokens.accent
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontXl
        font.weight: Tokens.weightHeavy
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDateTime(clock.date, "mm")
        color: Tokens.textPrimary
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontXl
        font.weight: Tokens.weightHeavy
    }
}
