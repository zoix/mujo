// The pages of a panel: one bar across the top, with a pill in the accent
// colour that slides to the chosen page. Larger and heavier than the
// choices inside a page (Chip), so the two are not mistaken for each other.
import QtQuick
import qs.theme

Rectangle {
    id: root

    property var labels: []
    property int index: 0
    signal chosen(index: int)

    readonly property real cell: (width - Tokens.spaceXs - Tokens.spaceXs) / Math.max(1, labels.length)

    implicitWidth: Tokens.notificationWidth
    implicitHeight: Tokens.spaceXxl + Tokens.spaceXs + Tokens.spaceXs
    radius: Tokens.radiusFull
    color: Tokens.group

    Rectangle {
        x: Tokens.spaceXs + root.index * root.cell
        y: Tokens.spaceXs
        width: root.cell
        height: parent.height - Tokens.spaceXs - Tokens.spaceXs
        radius: Tokens.radiusFull
        color: Tokens.accent

        Behavior on x {
            Anim {}
        }
    }

    Row {
        x: Tokens.spaceXs
        y: Tokens.spaceXs
        height: parent.height - Tokens.spaceXs - Tokens.spaceXs

        Repeater {
            model: root.labels

            delegate: Item {
                id: tab

                required property string modelData
                required property int index

                width: root.cell
                height: parent.height

                Text {
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - Tokens.spaceSm)
                    elide: Text.ElideRight
                    text: tab.modelData
                    color: root.index === tab.index ? Tokens.textOnAccent : area.containsMouse ? Tokens.textPrimary : Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontMd
                    font.weight: Tokens.weightEmphasis

                    Behavior on color {
                        Fade {}
                    }
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.chosen(tab.index)
                }
            }
        }
    }
}
