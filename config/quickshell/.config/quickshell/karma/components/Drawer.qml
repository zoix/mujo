// A panel that grows out of one edge of the frame, in the frame's colour,
// with rounded outer corners and a curved join where it meets the frame.
// Put the content inside; the drawer takes its size from it.
//
//   edge:  which edge of the parent the panel is attached to
//   open:  grows to the content's size when true, back to nothing when false
//   shift: offset along the edge from the centre (0 = centred)
//   atEnd: on a left or right edge, sit near the bottom instead of the middle
//   centre: on a left or right edge, the height to centre on (-1 = not set)
import QtQuick
import QtQuick.Shapes
import qs.theme

Item {
    id: root

    property string edge: "bottom"   // bottom | top | left | right
    property bool open: false
    property real shift: 0
    property bool atEnd: false
    property real centre: -1
    default property alias content: holder.data

    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property real fillet: Tokens.radiusLg
    readonly property real corner: Tokens.radiusXl
    // 0 = closed, 1 = fully open
    property real progress: open ? 1 : 0
    // How far the panel reaches out of the edge when open, and how long it
    // is along the edge. A panel on a side edge is drawn turned by a
    // quarter; it only lands on whole pixels if length and reach are both
    // even or both odd, so the length is made one longer when they differ.
    // (Otherwise the panel sits half a pixel off and a hairline of desktop
    // shows between it and the frame.)
    readonly property real reach: Math.round(vertical ? holder.implicitWidth : holder.implicitHeight)
    readonly property real length: Math.round((vertical ? holder.implicitHeight : holder.implicitWidth) + fillet + fillet)
    readonly property real along: vertical ? length + Math.abs(length - reach) % 2 : length
    readonly property real depth: reach * progress

    visible: progress > 0
    width: vertical ? depth : along
    height: vertical ? along : depth
    x: edge === "left" ? Tokens.bar : edge === "right" ? parent.width - Tokens.frame - width : (parent.width - Tokens.bar - Tokens.frame - width) / 2 + Tokens.bar + shift
    y: edge === "top" ? Tokens.frame : edge === "bottom" ? parent.height - Tokens.frame - height : centre >= 0 ? Math.max(Tokens.frame, Math.min(parent.height - Tokens.frame - height, centre - height / 2)) : atEnd ? parent.height - Tokens.frame - height - Tokens.button : (parent.height - height) / 2 + shift

    Behavior on progress {
        NumberAnimation {
            duration: Tokens.durationSlow
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.open ? Tokens.easeEnter : Tokens.easeExit
        }
    }

    // The shape is drawn as if attached to a bottom edge, then turned.
    Item {
        id: turned

        anchors.centerIn: parent
        width: root.along
        height: root.depth
        rotation: root.edge === "top" ? 180 : root.edge === "left" ? 90 : root.edge === "right" ? -90 : 0

        Shape {
            id: shape

            readonly property real w: turned.width
            readonly property real h: turned.height
            readonly property real f: Math.min(root.fillet, h / 2)
            readonly property real r: Math.min(root.corner, h / 2)
            readonly property real inset: root.fillet

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: "transparent"
                fillColor: Tokens.panel
                startX: shape.inset - shape.f
                startY: shape.h

                PathArc {
                    x: shape.inset
                    y: shape.h - shape.f
                    radiusX: shape.f
                    radiusY: shape.f
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: shape.inset
                    y: shape.r
                }
                PathArc {
                    x: shape.inset + shape.r
                    y: 0
                    radiusX: shape.r
                    radiusY: shape.r
                }
                PathLine {
                    x: shape.w - shape.inset - shape.r
                    y: 0
                }
                PathArc {
                    x: shape.w - shape.inset
                    y: shape.r
                    radiusX: shape.r
                    radiusY: shape.r
                }
                PathLine {
                    x: shape.w - shape.inset
                    y: shape.h - shape.f
                }
                PathArc {
                    x: shape.w - shape.inset + shape.f
                    y: shape.h
                    radiusX: shape.f
                    radiusY: shape.f
                    direction: PathArc.Counterclockwise
                }
                PathLine {
                    x: shape.inset - shape.f
                    y: shape.h
                }
            }
        }
    }

    // A strip over the seam with the frame, for solid panels: both shapes
    // have softened edges, and the strip makes sure nothing shows between
    // them. See-through panels get none (it would show as a darker band).
    Rectangle {
        readonly property real t: Tokens.borderFocus
        visible: Tokens.panelOpacity >= 1
        color: Tokens.bgFrame
        x: root.vertical ? (root.edge === "right" ? root.width - t : -t) : root.fillet
        y: root.vertical ? root.fillet : (root.edge === "bottom" ? root.height - t : -t)
        width: root.vertical ? t + t : root.width - root.fillet - root.fillet
        height: root.vertical ? root.height - root.fillet - root.fillet : t + t
    }

    // The content keeps its full size and is uncovered as the panel grows,
    // staying attached to the panel's leading side.
    Item {
        anchors.fill: parent
        clip: true

        Item {
            id: holder

            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
            width: implicitWidth
            height: implicitHeight
            opacity: root.progress
            x: root.edge === "right" ? 0 : root.edge === "left" ? parent.width - width : root.fillet
            y: root.edge === "bottom" ? 0 : root.edge === "top" ? parent.height - height : root.fillet
        }
    }
}
