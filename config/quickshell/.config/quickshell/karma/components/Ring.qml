// A round gauge: an arc that fills clockwise from the bottom left, with a
// value and a label in the middle.
import QtQuick
import QtQuick.Shapes
import qs.theme

Item {
    id: root

    property real value: 0      // 0 to 1
    property string text: ""
    property string label: ""
    property color tint: Tokens.accent

    readonly property real thickness: Tokens.spaceSm
    readonly property real sweep: 270

    implicitWidth: Tokens.ring
    implicitHeight: Tokens.ring

    Behavior on value {
        Anim {
            duration: Tokens.durationSlow
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Tokens.bgControl
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: (root.width - root.thickness) / 2
                radiusY: (root.height - root.thickness) / 2
                startAngle: 135
                sweepAngle: root.sweep
            }
        }

        ShapePath {
            strokeColor: root.tint
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: (root.width - root.thickness) / 2
                radiusY: (root.height - root.thickness) / 2
                startAngle: 135
                sweepAngle: Math.max(1, root.sweep * Math.max(0, Math.min(1, root.value)))
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.text
            color: Tokens.textPrimary
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontLg
            font.weight: Tokens.weightHeavy
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Tokens.textMuted
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontXs
        }
    }
}
