// The mujo logo: a gate whose posts form the letter m, with a dot in the
// doorway. Drawn as shapes so that it takes its colours from the theme.
import QtQuick
import QtQuick.Shapes
import qs.theme

Item {
    id: root

    property real size: Tokens.icon
    property color color: Tokens.textPrimary
    property color dotColor: Tokens.accent

    implicitWidth: size
    implicitHeight: size

    // Drawn on a 96 x 96 grid (docs/logo/mark-dark.svg) and scaled.
    Shape {
        anchors.centerIn: parent
        width: 96
        height: 96
        scale: root.size / 96
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.color
            strokeWidth: 9
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathSvg {
                path: "M 8 18 Q 48 8 88 18"
            }
        }

        ShapePath {
            strokeColor: root.color
            strokeWidth: 8
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap

            PathSvg {
                path: "M 18 37 H 78 M 25 37 L 22 83 M 71 37 L 74 83 M 48 37 V 55"
            }
        }

        ShapePath {
            strokeColor: "transparent"
            fillColor: root.dotColor

            PathAngleArc {
                centerX: 48
                centerY: 72
                radiusX: 5.5
                radiusY: 5.5
                startAngle: 0
                sweepAngle: 360
            }
        }
    }
}
