// The dashboard: a panel that drops from the top edge, with three pages.
//   Today       the date with a calendar, system gauges, the media player
//   Workspaces  a miniature of every workspace (modules/Overview.qml)
//   Activity    latest changes, network, battery, captures (modules/Activity.qml)
// It shows things; the actions are the media buttons, going to a workspace,
// undoing a change and copying or opening a capture.
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
    readonly property string page: Ui.dashboardPage
    // 0 to 1 while a newly chosen page comes in.
    property real reveal: 1

    onPageChanged: {
        pageIn.restart();
        if (active && page !== "workspaces")
            keys.forceActiveFocus();
        if (active && page === "activity")
            Activity.refresh();
    }

    NumberAnimation {
        id: pageIn
        target: root
        property: "reveal"
        from: 0
        to: 1
        duration: Tokens.durationNormal
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Tokens.easeEnter
    }

    readonly property MprisPlayer player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property int cardHeight: Tokens.ring + Tokens.ring + Tokens.spaceXl + Tokens.spaceXl

    implicitWidth: row.implicitWidth + Tokens.spaceMd + Tokens.spaceMd
    implicitHeight: tabs.height + Tokens.spaceSm + (page === "workspaces" ? overview.implicitHeight : row.implicitHeight) + Tokens.spaceMd + Tokens.spaceMd

    Behavior on implicitHeight {
        Anim {}
    }

    Tabs {
        id: tabs
        x: Tokens.spaceMd
        y: Tokens.spaceMd
        width: row.implicitWidth
        labels: ["Today", "Workspaces", "Activity"]
        index: root.pages.indexOf(root.page)
        onChosen: index => Ui.dashboardPage = root.pages[index]
    }

    ActivityPage {
        visible: root.page === "activity"
        opacity: root.reveal
        active: root.active && visible
        x: Tokens.spaceMd
        y: tabs.y + tabs.height + Tokens.spaceSm
        width: row.implicitWidth
        height: root.cardHeight
    }

    Overview {
        id: overview
        visible: root.page === "workspaces"
        opacity: root.reveal
        active: root.active && visible
        x: Tokens.spaceMd
        y: tabs.y + tabs.height + Tokens.spaceSm
        width: row.implicitWidth
    }

    onActiveChanged: {
        Sys.watching = active;
        if (active && page !== "workspaces")
            keys.forceActiveFocus();
        if (active && page === "activity")
            Activity.refresh();
    }

    readonly property var pages: ["today", "workspaces", "activity"]

    // As in quick settings: Tab, the arrow keys or H and L change page, 1 to
    // 3 go straight to one, Escape closes. (On the Workspaces page the
    // arrows move between the miniatures instead; see Overview.qml.)
    Item {
        id: keys
        Keys.onPressed: event => {
            const at = root.pages.indexOf(root.page);
            if (event.key === Qt.Key_Escape) {
                Ui.closeDashboard();
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                Ui.dashboardPage = root.pages[(at + 1) % root.pages.length];
            } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                Ui.dashboardPage = root.pages[(at + root.pages.length - 1) % root.pages.length];
            } else if (event.key === Qt.Key_1) {
                Ui.dashboardPage = "today";
            } else if (event.key === Qt.Key_2) {
                Ui.dashboardPage = "workspaces";
            } else if (event.key === Qt.Key_3) {
                Ui.dashboardPage = "activity";
            } else {
                return;
            }
            event.accepted = true;
        }
    }

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

        visible: root.page === "today"
        opacity: root.reveal
        x: Tokens.spaceMd
        y: tabs.y + tabs.height + Tokens.spaceSm
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

                        // The weather, once a place is set (mujo weather set).
                        Row {
                            visible: Weather.known
                            spacing: Tokens.spaceXs

                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Weather.glyph
                                color: Tokens.accent
                                font.pixelSize: Tokens.fontXs
                            }

                            Text {
                                text: Weather.line
                                color: Tokens.textPrimary
                                font.family: Tokens.fontFamily
                                font.pixelSize: Tokens.fontXs
                            }
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
                    text: root.player ? root.player.trackArtist : "Player controls show up here"
                    color: Tokens.textMuted
                    // Up to two lines; only a longer text is cut.
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
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
