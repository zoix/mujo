// Quick settings: a panel on the right edge with three pages.
//   Quick   on/off tiles and the notification history
//   Look    light or dark, palette, accent, motion
//   System  volume, output device, brightness, power profile, services
// Tab or the arrow keys change page.
// It shows the current state and runs the mujo CLI for every change.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs.theme
import qs.components
import qs.services

Item {
    id: root

    property bool active: false
    property string page: "quick"
    // 0 to 1 while a newly chosen page comes in.
    property real reveal: 1

    onPageChanged: pageIn.restart()

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

    Behavior on implicitHeight {
        Anim {}
    }
    property int brightness: -1
    // The scale of the screen with the focus (0: unknown), and whether it
    // was chosen with `mujo display scale` or comes from host.lua.
    property real screenScale: 0
    property bool scaleChosen: false
    property string profile: ""
    property var profiles: []
    property var outputs: []
    // Enabled background services, from `mujo services`.
    property var services: []
    readonly property var accents: Object.keys(Tokens.accentColors)

    implicitWidth: Tokens.notificationWidth + Tokens.spaceMd + Tokens.spaceMd
    implicitHeight: body.implicitHeight + Tokens.spaceMd + Tokens.spaceMd

    function payload(text: string): var {
        try {
            return JSON.parse(text).data;
        } catch (error) {
            return null;
        }
    }

    // Values that only mujo knows.
    function refresh(): void {
        displayReader.running = true;
        profileReader.running = true;
        audioReader.running = true;
        servicesReader.running = true;
    }

    function run(args: list<string>): void {
        Mujo.run(args);
        later.restart();
    }

    onActiveChanged: {
        if (active) {
            root.refresh();
            keys.forceActiveFocus();
        }
    }

    Timer {
        id: later
        interval: 500
        onTriggered: root.refresh()
    }

    Process {
        id: displayReader
        command: [Mujo.bin, "display", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const d = root.payload(this.text);
                root.brightness = d && d.brightness ? d.brightness.percent : -1;
                root.screenScale = d && d.scale ? d.scale.scale : 0;
                root.scaleChosen = d && d.scale ? d.scale.chosen : false;
            }
        }
    }

    Process {
        id: profileReader
        command: [Mujo.bin, "power", "profile", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const d = root.payload(this.text);
                root.profile = d ? d.profile : "";
                root.profiles = d ? d.available : [];
            }
        }
    }

    Process {
        id: audioReader
        command: [Mujo.bin, "audio", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const d = root.payload(this.text);
                root.outputs = d ? d.outputs : [];
            }
        }
    }

    Process {
        id: servicesReader
        command: [Mujo.bin, "services", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const d = root.payload(this.text);
                root.services = d ? d.services : [];
            }
        }
    }

    // While the panel is open the list follows a service that starts or stops.
    Timer {
        interval: 5000
        repeat: true
        running: root.active && root.page === "sound"
        onTriggered: servicesReader.running = true
    }

    readonly property var pages: ["quick", "look", "sound"]

    function turn(by: int): void {
        const at = root.pages.indexOf(root.page);
        root.page = root.pages[(at + by + root.pages.length) % root.pages.length];
    }

    // Tab, the arrow keys or H and L move between the pages; 1, 2 and 3 go
    // straight to one; Escape closes.
    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                Ui.closeAll();
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                root.turn(1);
            } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                root.turn(-1);
            } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_3) {
                root.page = root.pages[event.key - Qt.Key_1];
            } else {
                return;
            }
            event.accepted = true;
        }
    }

    // The name of a group of settings.
    component Heading: Text {
        color: Tokens.textMuted
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontSm
        font.weight: Tokens.weightEmphasis
        topPadding: Tokens.spaceMd
    }

    Column {
        id: body

        x: Tokens.spaceMd
        y: Tokens.spaceMd
        width: Tokens.notificationWidth
        spacing: Tokens.spaceSm

        Tabs {
            width: parent.width
            labels: ["Quick", "Look", "System"]
            index: root.pages.indexOf(root.page)
            onChosen: index => root.page = root.pages[index]
        }

        Item {
            width: parent.width
            height: Tokens.spaceXs
        }

        // ---- Quick
        Grid {
            visible: root.page === "quick"
            opacity: root.reveal
            transform: Translate {
                x: (1 - root.reveal) * Tokens.spaceXl
            }
            columns: 2
            spacing: Tokens.spaceSm

            Toggle {
                glyph: ""
                label: Net.ssid !== "" ? Net.ssid : "Wi-Fi"
                on: Net.wifiEnabled
                onClicked: root.run(["net", "wifi", "toggle"])
            }
            Toggle {
                glyph: ""
                label: "Bluetooth"
                on: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled
                onClicked: root.run(["bt", "power", "toggle"])
            }
            Toggle {
                glyph: ""
                label: "Do not disturb"
                on: Settings.dnd
                onClicked: root.run(["dnd", "toggle"])
            }
            Toggle {
                glyph: ""
                label: "Night light"
                on: Settings.nightOn
                onClicked: root.run(["display", "night", "toggle"])
            }
            Toggle {
                glyph: ""
                label: "Keep awake"
                on: Settings.awake
                onClicked: root.run(["power", "awake", "toggle"])
            }
            Toggle {
                glyph: "\uf0e7"
                label: "Follow charger"
                on: Settings.powerAuto
                onClicked: root.run(["power", "auto", "toggle"])
            }
            Toggle {
                glyph: "\uf0ac"
                label: "Auto time zone"
                on: Settings.timeAuto
                onClicked: root.run(["time", "auto", "toggle"])
            }
            Toggle {
                glyph: "\uf108"
                label: "60 Hz on battery"
                on: Settings.batteryRefresh
                onClicked: root.run(["power", "battery", "refresh", "toggle"])
            }
            Toggle {
                glyph: "\uf0c8"
                label: "Solid on battery"
                on: Settings.batterySolid
                onClicked: root.run(["power", "battery", "solid", "toggle"])
            }
            Toggle {
                glyph: "\uf252"
                label: Settings.focusUntil > 0 ? "Focusing" : "Focus 25 min"
                on: Settings.focusUntil > 0
                onClicked: root.run(Settings.focusUntil > 0 ? ["focus", "stop"] : ["focus", "start"])
            }
            Toggle {
                glyph: ""
                label: Audio.muted ? "Muted" : "Sound on"
                on: Audio.muted
                onClicked: root.run(["audio", "mute", "toggle"])
            }
        }

        Row {
            visible: root.page === "quick"
            opacity: root.reveal
            width: parent.width
            spacing: Tokens.spaceSm

            Heading {
                width: parent.width - clear.width - Tokens.spaceSm
                text: Notifs.history.length > 0 ? "Recent notifications" : "No notifications yet"
            }

            Chip {
                id: clear
                visible: Notifs.history.length > 0
                label: "Clear"
                onClicked: Notifs.forget()
            }
        }

        ListView {
            visible: root.page === "quick" && count > 0
            opacity: root.reveal
            width: parent.width
            height: Math.min(contentHeight, Tokens.osdHeight + Tokens.osdHeight)
            clip: true
            spacing: Tokens.spaceXs
            model: Notifs.history
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: past

                required property var modelData

                width: ListView.view.width
                implicitHeight: pastText.implicitHeight + Tokens.spaceSm + Tokens.spaceSm
                radius: Tokens.radiusMd
                color: Tokens.bgBase

                Column {
                    id: pastText
                    x: Tokens.spaceMd
                    y: Tokens.spaceSm
                    width: parent.width - Tokens.spaceMd - Tokens.spaceMd

                    Text {
                        width: parent.width
                        text: past.modelData.summary
                        color: Tokens.textPrimary
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontSm
                    }

                    Text {
                        width: parent.width
                        text: (past.modelData.app ? past.modelData.app + "  " : "") + Qt.formatTime(past.modelData.time, "HH:mm") + (past.modelData.body ? "  " + past.modelData.body : "")
                        color: Tokens.textMuted
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontXs
                    }
                }
            }
        }

        // ---- Look
        Column {
            visible: root.page === "look"
            opacity: root.reveal
            transform: Translate {
                x: (1 - root.reveal) * Tokens.spaceXl
            }
            width: parent.width
            spacing: Tokens.spaceSm

            Heading {
                text: "Light or dark"
            }
            Row {
                spacing: Tokens.spaceSm

                Repeater {
                    model: ["auto", "dark", "light"]

                    delegate: Chip {
                        required property string modelData
                        label: modelData === "auto" ? "Follow the wallpaper" : modelData === "dark" ? "Dark" : "Light"
                        chosen: Settings.modePref === modelData
                        onClicked: root.run(["theme", "mode", modelData])
                    }
                }
            }

            Heading {
                text: "Colours"
            }
            Row {
                spacing: Tokens.spaceSm

                Chip {
                    label: "Catppuccin"
                    chosen: Settings.palette === "catppuccin"
                    onClicked: root.run(["theme", "palette", "catppuccin"])
                }
                Chip {
                    label: "From the wallpaper"
                    chosen: Settings.palette === "wallpaper"
                    onClicked: root.run(["theme", "palette", "wallpaper"])
                }
            }

            Heading {
                text: "Accent"
            }
            Flow {
                width: parent.width
                spacing: Tokens.spaceSm

                Chip {
                    label: "Auto"
                    chosen: Settings.accentPref === "auto"
                    onClicked: root.run(["theme", "accent", "auto"])
                }

                Repeater {
                    model: root.accents

                    delegate: Rectangle {
                        id: swatch

                        required property string modelData

                        width: Tokens.icon
                        height: Tokens.icon
                        radius: Tokens.radiusFull
                        color: Tokens.accentColors[modelData]
                        border.width: Settings.accentPref === modelData ? Tokens.borderFocus + Tokens.borderThin : 0
                        border.color: Tokens.textPrimary

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.run(["theme", "accent", swatch.modelData])
                        }
                    }
                }
            }

            Heading {
                text: "Motion"
            }
            Row {
                spacing: Tokens.spaceSm

                Chip {
                    label: "Normal"
                    chosen: !Settings.reduceMotion && Settings.motion === "normal"
                    onClicked: {
                        Mujo.run(["theme", "reduce-motion", "off"]);
                        root.run(["theme", "motion", "normal"]);
                    }
                }
                Chip {
                    label: "Gentle"
                    chosen: !Settings.reduceMotion && Settings.motion === "gentle"
                    onClicked: {
                        Mujo.run(["theme", "reduce-motion", "off"]);
                        root.run(["theme", "motion", "gentle"]);
                    }
                }
                Chip {
                    label: "Off"
                    chosen: Settings.reduceMotion
                    onClicked: root.run(["theme", "reduce-motion", "on"])
                }
            }

            Heading {
                text: "Panels"
            }
            Row {
                spacing: Tokens.spaceSm

                Chip {
                    label: "Solid"
                    chosen: !Settings.glass
                    onClicked: root.run(["theme", "glass", "off"])
                }
                Chip {
                    label: "See-through"
                    chosen: Settings.glass
                    onClicked: root.run(["theme", "glass", "on"])
                }
            }

            Chip {
                label: "Choose a wallpaper"
                onClicked: Ui.toggleLauncher("wallpapers")
            }
        }

        // ---- Sound and screen
        Column {
            visible: root.page === "sound"
            opacity: root.reveal
            transform: Translate {
                x: (1 - root.reveal) * Tokens.spaceXl
            }
            width: parent.width
            spacing: Tokens.spaceSm

            Item {
                width: parent.width
                implicitHeight: volumeHeading.implicitHeight

                Heading {
                    id: volumeHeading
                    text: "Volume  " + Audio.volume + "%" + (Audio.muted ? "  (muted)" : "")
                }

                // The mixer (every stream and device), behind a small icon
                // at the end of the title's line.
                Glyph {
                    anchors.right: parent.right
                    anchors.bottom: volumeHeading.bottom
                    text: "\uf1de"
                    font.pixelSize: Tokens.fontMd
                    color: mixerArea.containsMouse ? Tokens.accent : Tokens.textMuted

                    MouseArea {
                        id: mixerArea
                        anchors.fill: parent
                        anchors.margins: -Tokens.spaceSm
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Mujo.open(["audio", "tui"]);
                            Ui.closeAll();
                        }
                    }
                }
            }
            Slide {
                value: Audio.volume
                dim: Audio.muted
                onMoved: value => root.run(["audio", "volume", String(value)])
            }

            Heading {
                visible: root.outputs.length > 1
                text: "Output"
            }
            Flow {
                visible: root.outputs.length > 1
                width: parent.width
                spacing: Tokens.spaceSm

                Repeater {
                    model: root.outputs

                    delegate: Chip {
                        required property var modelData
                        label: modelData.description
                        chosen: modelData.default
                        onClicked: root.run(["audio", "output", modelData.name])
                    }
                }
            }

            Heading {
                visible: root.brightness >= 0
                text: "Brightness  " + root.brightness + "%"
            }
            Slide {
                visible: root.brightness >= 0
                value: root.brightness
                onMoved: value => {
                    root.brightness = Math.max(1, value);
                    root.run(["display", "brightness", String(Math.max(1, value))]);
                }
            }

            Heading {
                visible: root.screenScale > 0
                text: "Text size  " + Math.round(root.screenScale * 100) + "%"
            }
            Row {
                visible: root.screenScale > 0
                spacing: Tokens.spaceSm

                Chip {
                    label: "Smaller"
                    onClicked: root.run(["display", "scale", "smaller"])
                }
                Chip {
                    label: "Bigger"
                    onClicked: root.run(["display", "scale", "bigger"])
                }
                Chip {
                    visible: root.scaleChosen
                    label: "Reset"
                    onClicked: root.run(["display", "scale", "reset"])
                }
            }

            Heading {
                visible: root.profiles.length > 0
                text: "Power profile"
            }
            Row {
                visible: root.profiles.length > 0
                spacing: Tokens.spaceSm

                Repeater {
                    model: root.profiles

                    delegate: Chip {
                        required property string modelData
                        label: modelData === "power-saver" ? "Saver" : modelData === "balanced" ? "Balanced" : "Performance"
                        chosen: root.profile === modelData
                        onClicked: root.run(["power", "profile", modelData])
                    }
                }
            }

            Heading {
                text: "Services"
            }
            Text {
                visible: root.services.length === 0
                width: parent.width
                text: "None enabled yet. One appears here after 'systemctl enable'."
                color: Tokens.textMuted
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontXs
            }
            Column {
                visible: root.services.length > 0
                width: parent.width
                spacing: Tokens.spaceXs

                Repeater {
                    model: root.services

                    delegate: Rectangle {
                        id: service

                        required property var modelData
                        readonly property string state_: modelData.state

                        width: parent.width
                        implicitHeight: serviceName.implicitHeight + Tokens.spaceSm + Tokens.spaceSm
                        radius: Tokens.radiusMd
                        color: Tokens.bgBase

                        Rectangle {
                            id: serviceDot
                            x: Tokens.spaceMd
                            anchors.verticalCenter: parent.verticalCenter
                            width: Tokens.spaceSm
                            height: Tokens.spaceSm
                            radius: Tokens.radiusFull
                            color: service.state_ === "running" ? Tokens.stateSuccess : service.state_ === "failed" ? Tokens.stateError : service.state_ === "ready" ? Tokens.stateInfo : Tokens.textMuted
                        }

                        Text {
                            id: serviceName
                            anchors.left: serviceDot.right
                            anchors.leftMargin: Tokens.spaceSm
                            anchors.right: serviceState.left
                            anchors.rightMargin: Tokens.spaceSm
                            anchors.verticalCenter: parent.verticalCenter
                            text: service.modelData.name
                            color: Tokens.textPrimary
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontSm
                        }

                        Text {
                            id: serviceState
                            anchors.right: parent.right
                            anchors.rightMargin: Tokens.spaceMd
                            anchors.verticalCenter: parent.verticalCenter
                            text: service.state_ === "ready" ? "Starts on first use" : service.state_ === "running" ? "Running" : service.state_ === "failed" ? "Failed" : "Stopped"
                            color: service.state_ === "failed" ? Tokens.stateError : Tokens.textMuted
                            textFormat: Text.PlainText
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontXs
                        }
                    }
                }
            }
        }
    }
}
