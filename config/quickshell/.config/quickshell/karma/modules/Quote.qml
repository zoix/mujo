// Content of the quote panel on the top edge: the quote of the hour and
// who said it. It visits on the hour and after `karma quote next`.
import QtQuick
import qs.theme
import qs.services

Item {
    id: root

    readonly property int limit: Tokens.card + Tokens.card + Tokens.card

    implicitWidth: Math.max(line.width, credit.width) + Tokens.spaceXl + Tokens.spaceXl
    implicitHeight: line.height + credit.height + Tokens.spaceXs + Tokens.spaceMd + Tokens.spaceMd

    Text {
        id: line
        anchors.horizontalCenter: parent.horizontalCenter
        y: Tokens.spaceMd
        width: Math.min(implicitWidth, root.limit)
        text: Quotes.text
        wrapMode: Text.WordWrap
        horizontalAlignment: Text.AlignHCenter
        color: Tokens.textPrimary
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSm
    }

    Text {
        id: credit
        anchors.horizontalCenter: parent.horizontalCenter
        y: line.y + line.height + Tokens.spaceXs
        text: Quotes.credit
        color: Tokens.accent
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontXs
    }
}
