// Notifications: a panel in the top-right corner that is part of the frame.
// It grows as cards arrive and shrinks back into the corner when the last
// one leaves. Click a card to dismiss it; hovering keeps it on screen.
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.Notifications
import qs.theme
import qs.components
import qs.services

Item {
    id: root

    readonly property real fillet: Tokens.radiusLg
    readonly property real corner: Tokens.radiusXl
    readonly property real panelWidth: Tokens.notificationWidth + Tokens.spaceMd + Tokens.spaceMd
    // Only the focused screen shows notifications.
    property bool shown: true
    // Height of the panel body; 0 when there is nothing to show.
    property real panelHeight: shown && Notifs.list.length > 0 ? cards.implicitHeight + Tokens.spaceMd + Tokens.spaceMd : 0

    Behavior on panelHeight {
        Anim {
            duration: Tokens.durationSlow
        }
    }

    visible: panelHeight > 0
    width: panelWidth + fillet
    height: panelHeight + fillet
    x: parent.width - Tokens.frame - width
    y: Tokens.frame

    Shape {
        id: shape

        readonly property real w: root.width
        readonly property real h: root.panelHeight
        readonly property real f: Math.min(root.fillet, h / 2)
        readonly property real r: Math.min(root.corner, h / 2)
        readonly property real inset: root.fillet

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: "transparent"
            fillColor: Tokens.bgFrame
            startX: shape.inset - shape.f
            startY: 0

            // join with the top edge
            PathArc {
                x: shape.inset
                y: shape.f
                radiusX: shape.f
                radiusY: shape.f
            }
            PathLine {
                x: shape.inset
                y: shape.h - shape.r
            }
            // the panel's one free corner
            PathArc {
                x: shape.inset + shape.r
                y: shape.h
                radiusX: shape.r
                radiusY: shape.r
                direction: PathArc.Counterclockwise
            }
            PathLine {
                x: shape.w - shape.f
                y: shape.h
            }
            // join with the right edge
            PathArc {
                x: shape.w
                y: shape.h + shape.f
                radiusX: shape.f
                radiusY: shape.f
            }
            PathLine {
                x: shape.w
                y: 0
            }
            PathLine {
                x: shape.inset - shape.f
                y: 0
            }
        }
    }

    Item {
        x: root.fillet
        width: root.panelWidth
        height: root.panelHeight
        clip: true

        Column {
            id: cards

            x: Tokens.spaceMd
            y: Tokens.spaceMd
            width: Tokens.notificationWidth
            spacing: Tokens.spaceSm

            Repeater {
                model: ScriptModel {
                    values: Notifs.list
                }

                delegate: Rectangle {
                    id: card

                    required property Notification modelData
                    readonly property bool critical: modelData.urgency === NotificationUrgency.Critical

                    width: cards.width
                    implicitHeight: content.implicitHeight + Tokens.spaceMd + Tokens.spaceMd
                    radius: Tokens.radiusLg
                    color: Tokens.bgBase
                    border.width: card.critical ? Tokens.borderFocus : 0
                    border.color: Tokens.stateError

                    // Cards arrive from the right edge, where they belong.
                    x: width
                    opacity: 0
                    Component.onCompleted: {
                        x = 0;
                        opacity = 1;
                    }
                    Behavior on x {
                        Anim {
                            easing.bezierCurve: Tokens.easeEnter
                        }
                    }
                    Behavior on opacity {
                        Anim {}
                    }

                    Timer {
                        // expireTimeout is in milliseconds; 0 or less means "no preference".
                        interval: card.modelData.expireTimeout > 0 ? card.modelData.expireTimeout : Tokens.notificationTimeout
                        running: !card.critical && !hover.hovered
                        onTriggered: card.modelData.expire()
                    }

                    HoverHandler {
                        id: hover
                    }

                    TapHandler {
                        onTapped: card.modelData.dismiss()
                    }

                    ColumnLayout {
                        id: content
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.spaceMd
                        spacing: Tokens.spaceXs

                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: card.modelData.appName
                            color: card.critical ? Tokens.stateError : Tokens.accent
                            elide: Text.ElideRight
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontXs
                        }

                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.summary
                            color: Tokens.textPrimary
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontMd
                            font.weight: Tokens.weightEmphasis
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: card.modelData.body
                            color: Tokens.textMuted
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                        }

                        Flow {
                            Layout.fillWidth: true
                            Layout.topMargin: Tokens.spaceXs
                            visible: card.modelData.actions.length > 0
                            spacing: Tokens.spaceSm

                            Repeater {
                                model: card.modelData.actions

                                delegate: Rectangle {
                                    id: action

                                    required property NotificationAction modelData

                                    implicitWidth: actionLabel.implicitWidth + Tokens.spaceLg + Tokens.spaceLg
                                    implicitHeight: actionLabel.implicitHeight + Tokens.spaceSm + Tokens.spaceSm
                                    radius: Tokens.radiusFull
                                    color: actionHover.hovered ? Tokens.accent : Tokens.bgControl

                                    Behavior on color {
                                        Fade {}
                                    }

                                    Text {
                                        id: actionLabel
                                        anchors.centerIn: parent
                                        text: action.modelData.text
                                        color: actionHover.hovered ? Tokens.textOnAccent : Tokens.textPrimary
                                        font.family: Tokens.fontFamily
                                        font.pixelSize: Tokens.fontSm
                                    }

                                    HoverHandler {
                                        id: actionHover
                                        cursorShape: Qt.PointingHandCursor
                                    }

                                    TapHandler {
                                        onTapped: action.modelData.invoke()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
