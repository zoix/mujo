// The dashboard's Activity page: what changed lately (with undo), the
// network, the battery over the last day, and the newest screenshots and
// recordings. Figures are read-only; undo and copy or open run the mujo CLI.
import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.theme
import qs.components
import qs.services

Item {
    id: root

    property bool active: false
    readonly property int half: Math.floor((height - Tokens.spaceSm) / 2)

    // 1536 -> "1.5 KiB"
    function bytes(n: real): string {
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        let i = 0;
        while (n >= 1024 && i < units.length - 1) {
            n /= 1024;
            i++;
        }
        return (i === 0 || n >= 100 ? Math.round(n) : n.toFixed(1)) + " " + units[i];
    }

    function duration(seconds: real): string {
        const minutes = Math.round(seconds / 60);
        return minutes >= 60 ? Math.floor(minutes / 60) + " h " + (minutes % 60) + " min" : minutes + " min";
    }

    component Card: Rectangle {
        radius: Tokens.radiusLg
        color: Tokens.bgBase
    }

    component Title: Text {
        color: Tokens.accent
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontXs
    }

    component Line: Text {
        color: Tokens.textMuted
        elide: Text.ElideRight
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontXs
    }

    Row {
        anchors.fill: parent
        spacing: Tokens.spaceSm

        // Latest changes, newest first. One that can be undone has a button.
        Card {
            width: Tokens.card
            height: root.height

            Column {
                id: changes
                anchors.fill: parent
                anchors.margins: Tokens.spaceMd
                spacing: Tokens.spaceXs

                Title {
                    text: "Latest changes"
                }

                Line {
                    visible: Activity.changes.length === 0
                    width: changes.width
                    text: "Nothing has been changed yet"
                }

                Repeater {
                    model: Activity.changes

                    delegate: Item {
                        id: change

                        required property var modelData

                        width: changes.width
                        height: Tokens.barButton

                        Line {
                            id: when
                            anchors.verticalCenter: parent.verticalCenter
                            text: Qt.formatTime(new Date(change.modelData.time), "HH:mm")
                        }

                        Text {
                            anchors.left: when.right
                            anchors.leftMargin: Tokens.spaceSm
                            anchors.right: undo.visible ? undo.left : parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            // Folders are left out of file names to keep the line short.
                            text: change.modelData.summary.replace(/\/[^ ]*\//g, "")
                            color: change.modelData.undone ? Tokens.textMuted : Tokens.textPrimary
                            elide: Text.ElideRight
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                        }

                        BarButton {
                            id: undo
                            visible: change.modelData.reversible && !change.modelData.undone
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                Mujo.run(["undo", change.modelData.id]);
                                again.restart();
                            }

                            Glyph {
                                anchors.centerIn: parent
                                text: ""
                                font.pixelSize: Tokens.fontSm
                                color: undo.hovered ? Tokens.accent : Tokens.textMuted
                            }
                        }
                    }
                }
            }
        }

        Column {
            spacing: Tokens.spaceSm

            // Network: speed now, a graph of the last two minutes, and the totals
            // since the connection came up.
            Card {
                width: Tokens.card
                height: root.half

                Item {
                    id: net
                    anchors.fill: parent
                    anchors.margins: Tokens.spaceMd

                    Title {
                        id: netTitle
                        text: Net.ssid !== "" ? Net.ssid : Sys.netInterface !== "" ? Sys.netInterface : "Network"
                        width: parent.width - netAddress.implicitWidth - Tokens.spaceSm
                        elide: Text.ElideRight
                    }

                    Line {
                        id: netAddress
                        anchors.right: parent.right
                        text: Sys.netInterface === "" ? "offline" : Sys.netAddress
                    }

                    Text {
                        id: netSpeed
                        anchors.top: netTitle.bottom
                        anchors.topMargin: Tokens.spaceXs
                        text: "↓ " + root.bytes(Sys.netDown) + "/s   ↑ " + root.bytes(Sys.netUp) + "/s"
                        color: Tokens.textPrimary
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontSm
                    }

                    Spark {
                        anchors.top: netSpeed.bottom
                        anchors.topMargin: Tokens.spaceXs
                        anchors.bottom: netTotal.top
                        anchors.bottomMargin: Tokens.spaceXs
                        width: parent.width
                        values: Sys.netHistory
                    }

                    Line {
                        id: netTotal
                        anchors.bottom: parent.bottom
                        width: parent.width
                        text: Sys.netInterface === "" ? "No connection" : root.bytes(Sys.netReceived) + " down, " + root.bytes(Sys.netSent) + " up"
                    }
                }
            }

            // Battery: charge over the last 24 hours, the draw now, wear.
            Card {
                width: Tokens.card
                height: root.height - root.half - Tokens.spaceSm

                Item {
                    id: battery
                    anchors.fill: parent
                    anchors.margins: Tokens.spaceMd

                    readonly property var device: Battery.device
                    readonly property real watts: Battery.present ? Math.abs(device.changeRate) : 0
                    readonly property real remaining: Battery.present ? (Battery.charging ? device.timeToFull : device.timeToEmpty) : 0

                    Title {
                        id: batteryTitle
                        text: Battery.present ? "Battery " + Battery.percent + "%" : "Battery"
                    }

                    Line {
                        anchors.right: parent.right
                        visible: Battery.present
                        text: (Battery.charging ? "+" : "−") + battery.watts.toFixed(1) + " W"
                        color: Battery.charging ? Tokens.stateSuccess : Tokens.textMuted
                    }

                    Text {
                        id: batteryLeft
                        anchors.top: batteryTitle.bottom
                        anchors.topMargin: Tokens.spaceXs
                        width: parent.width
                        text: !Battery.present ? "No battery" : battery.remaining > 0 ? root.duration(battery.remaining) + (Battery.charging ? " until full" : " left") : Battery.charging ? "Plugged in" : "On battery"
                        color: Tokens.textPrimary
                        elide: Text.ElideRight
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontSm
                    }

                    Spark {
                        anchors.top: batteryLeft.bottom
                        anchors.topMargin: Tokens.spaceXs
                        anchors.bottom: batteryNote.top
                        anchors.bottomMargin: Tokens.spaceXs
                        width: parent.width
                        values: Activity.battery.map(point => point[1])
                        ceiling: 100
                        tint: Battery.charging ? Tokens.stateSuccess : Tokens.accent
                    }

                    Line {
                        id: batteryNote
                        anchors.bottom: parent.bottom
                        width: parent.width
                        text: Activity.battery.length < 2 ? "No history yet" : "Last " + Math.max(1, Math.round(Activity.battery[0][0] / 3600)) + " h" + (Battery.present && battery.device.healthSupported ? ", health " + Math.round(battery.device.healthPercentage) + "%" : "")
                    }
                }
            }
        }

        // Screenshots and recordings. A click copies a picture (or opens a
        // recording); a right click opens it.
        Card {
            width: Tokens.card
            height: root.height

            Column {
                id: captures
                anchors.fill: parent
                anchors.margins: Tokens.spaceMd
                spacing: Tokens.spaceSm

                readonly property int cell: Math.floor((width - Tokens.spaceSm) / 2)
                readonly property int cellHeight: Math.floor((height - capturesTitle.height - Tokens.spaceSm * 3) / 3)

                // The title, and a button for each folder on the right.
                Item {
                    id: capturesTitle
                    width: captures.width
                    height: Tokens.barButton

                    Title {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Captures"
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: Tokens.spaceXs

                        Repeater {
                            model: [
                                {
                                    folder: "screenshots",
                                    icon: "\uf03e"
                                },
                                {
                                    folder: "recordings",
                                    icon: "\uf03d"
                                }
                            ]

                            delegate: BarButton {
                                id: folderButton

                                required property var modelData

                                hoverColor: Tokens.group
                                radius: Tokens.radiusFull
                                onClicked: {
                                    Mujo.run(["shot", "folder", modelData.folder]);
                                    Ui.closeDashboard();
                                }

                                Glyph {
                                    anchors.centerIn: parent
                                    text: folderButton.modelData.icon
                                    font.pixelSize: Tokens.fontSm
                                    color: folderButton.hovered ? Tokens.accent : Tokens.textMuted
                                }
                            }
                        }
                    }
                }

                Line {
                    visible: Activity.captures.length === 0
                    width: captures.width
                    wrapMode: Text.WordWrap
                    text: "Nothing captured yet. Print takes a screenshot."
                }

                Grid {
                    columns: 2
                    spacing: Tokens.spaceSm

                    Repeater {
                        model: Activity.captures

                        delegate: ClippingRectangle {
                            id: capture

                            required property var modelData
                            readonly property bool picture: modelData.kind === "screenshot"

                            width: captures.cell
                            height: captures.cellHeight
                            radius: Tokens.radiusSm
                            color: Tokens.bgControl
                            border.width: captureArea.containsMouse ? Tokens.borderFocus : 0
                            border.color: Tokens.accent

                            Image {
                                anchors.fill: parent
                                visible: capture.picture
                                source: capture.picture ? "file://" + capture.modelData.path : ""
                                sourceSize.width: captures.cell * 2
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }

                            Glyph {
                                anchors.centerIn: parent
                                visible: !capture.picture
                                text: ""
                                color: Tokens.textMuted
                            }

                            MouseArea {
                                id: captureArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: event => {
                                    const open = event.button === Qt.RightButton || !capture.picture;
                                    Mujo.run(["shot", open ? "open" : "copy", capture.modelData.path]);
                                    if (open)
                                        Ui.closeDashboard();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Read the page again once an undo has had time to finish.
    Timer {
        id: again
        interval: 1200
        onTriggered: Activity.refresh()
    }
}
