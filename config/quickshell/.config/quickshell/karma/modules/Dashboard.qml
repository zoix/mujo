// The dashboard: a panel that drops from the top edge. Three cards: the
// date with a calendar, system gauges, and the media player. It shows
// things; the only actions are the media buttons.
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import qs.theme
import qs.components
import qs.services

Item {
    id: root

    property bool active: false

    readonly property MprisPlayer player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property int cardHeight: Tokens.ring + Tokens.ring + Tokens.spaceXl + Tokens.spaceXl

    implicitWidth: row.implicitWidth + Tokens.spaceMd + Tokens.spaceMd
    implicitHeight: row.implicitHeight + Tokens.spaceMd + Tokens.spaceMd

    onActiveChanged: Sys.watching = active

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    component Card: Rectangle {
        implicitWidth: Tokens.card
        implicitHeight: root.cardHeight
        radius: Tokens.radiusLg
        color: Tokens.bgBase
    }

    Row {
        id: row

        x: Tokens.spaceMd
        y: Tokens.spaceMd
        spacing: Tokens.spaceSm

        // Date and calendar
        Card {
            id: dateCard

            readonly property date today: clock.date
            readonly property int year: today.getFullYear()
            readonly property int month: today.getMonth()
            // Monday first: 0 = Monday ... 6 = Sunday
            readonly property int offset: (new Date(year, month, 1).getDay() + 6) % 7
            readonly property int days: new Date(year, month + 1, 0).getDate()

            Column {
                anchors.fill: parent
                anchors.margins: Tokens.spaceMd
                spacing: Tokens.spaceSm

                Row {
                    spacing: Tokens.spaceSm

                    Text {
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        color: Tokens.accent
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontDisplay
                        font.weight: Tokens.weightHeavy
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            text: Qt.formatDateTime(clock.date, "dddd")
                            color: Tokens.textPrimary
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                        }

                        Text {
                            text: Qt.formatDateTime(clock.date, "d MMMM yyyy")
                            color: Tokens.textMuted
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontXs
                        }
                    }
                }

                Grid {
                    id: calendar

                    readonly property real cell: (parent.width) / 7

                    columns: 7

                    Repeater {
                        model: ["M", "T", "W", "T", "F", "S", "S"]

                        delegate: Text {
                            required property string modelData
                            width: calendar.cell
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: Tokens.textMuted
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontXs
                        }
                    }

                    Repeater {
                        model: dateCard.offset + dateCard.days

                        delegate: Item {
                            id: day

                            required property int index
                            readonly property int number: index - dateCard.offset + 1
                            readonly property bool isToday: number === dateCard.today.getDate()

                            width: calendar.cell
                            height: Tokens.fontXl + Tokens.spaceXs

                            Rectangle {
                                anchors.centerIn: parent
                                visible: day.isToday
                                width: Math.min(parent.width, parent.height)
                                height: width
                                radius: Tokens.radiusFull
                                color: Tokens.accent
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: day.number > 0
                                text: day.number
                                color: day.isToday ? Tokens.textOnAccent : Tokens.textPrimary
                                font.family: Tokens.fontFamily
                                font.pixelSize: Tokens.fontXs
                            }
                        }
                    }
                }
            }
        }

        // System
        Card {
            Grid {
                anchors.centerIn: parent
                columns: 2
                spacing: Tokens.spaceMd

                Ring {
                    value: Sys.cpu / 100
                    text: Sys.cpu + "%"
                    label: "CPU"
                }

                Ring {
                    value: Sys.memory / 100
                    text: Sys.memory + "%"
                    label: "Memory"
                    tint: Tokens.stateInfo
                }

                Ring {
                    value: Sys.temperature / 100
                    text: Sys.temperature < 0 ? "-" : Sys.temperature + "°"
                    label: "Temp"
                    tint: Sys.temperature >= 85 ? Tokens.stateError : Sys.temperature >= 70 ? Tokens.stateWarning : Tokens.stateSuccess
                }

                Ring {
                    value: Sys.disk / 100
                    text: Sys.disk + "%"
                    label: "Disk"
                    tint: Sys.disk >= 90 ? Tokens.stateError : Tokens.accent
                }
            }
        }

        // Media
        Card {
            Column {
                anchors.fill: parent
                anchors.margins: Tokens.spaceMd
                spacing: Tokens.spaceSm

                ClippingRectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Tokens.ring
                    height: Tokens.ring
                    radius: Tokens.radiusMd
                    color: Tokens.bgControl

                    Glyph {
                        anchors.centerIn: parent
                        visible: art.status !== Image.Ready
                        text: ""
                        color: Tokens.textMuted
                    }

                    Image {
                        id: art
                        anchors.fill: parent
                        source: root.player ? root.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: Tokens.ring + Tokens.ring
                    }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.player ? (root.player.trackTitle || root.player.identity) : "Nothing is playing"
                    color: Tokens.textPrimary
                    elide: Text.ElideRight
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontMd
                    font.weight: Tokens.weightEmphasis
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.player ? root.player.trackArtist : "Start a player to control it here"
                    color: Tokens.textMuted
                    elide: Text.ElideRight
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.player !== null
                    spacing: Tokens.spaceSm

                    BarButton {
                        onClicked: root.player.previous()

                        Glyph {
                            anchors.centerIn: parent
                            text: ""
                            font.pixelSize: Tokens.fontMd
                        }
                    }

                    BarButton {
                        color: Tokens.accent
                        radius: Tokens.radiusFull
                        onClicked: root.player.togglePlaying()

                        Glyph {
                            anchors.centerIn: parent
                            text: root.player && root.player.isPlaying ? "" : ""
                            font.pixelSize: Tokens.fontMd
                            color: Tokens.textOnAccent
                        }
                    }

                    BarButton {
                        onClicked: root.player.next()

                        Glyph {
                            anchors.centerIn: parent
                            text: ""
                            font.pixelSize: Tokens.fontMd
                        }
                    }
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "up " + Math.floor(Sys.uptime / 3600) + " h " + Math.floor(Sys.uptime % 3600 / 60) + " min"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                }
            }
        }
    }
}
