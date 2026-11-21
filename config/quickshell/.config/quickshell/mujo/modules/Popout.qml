// What a pop-out next to a bar icon shows: the details behind the icon, or
// the menu of a tray icon. Reading only, except the volume slider and the
// power profile, which run the mujo CLI, and tray menu entries, which
// belong to the app that owns the icon.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import qs.theme
import qs.components
import qs.services

Item {
    id: root

    readonly property string kind: Ui.popout
    readonly property var connected: Bluetooth.devices.values.filter(d => d.connected)

    // The about card has more to say than the others and is half as wide again.
    readonly property int bodyWidth: kind === "about" ? Math.round(Tokens.card * 1.5) : Tokens.card
    readonly property var about: About.info

    implicitWidth: bodyWidth + Tokens.spaceMd + Tokens.spaceMd
    implicitHeight: body.implicitHeight + Tokens.spaceMd + Tokens.spaceMd

    function duration(seconds: real): string {
        const minutes = Math.round(seconds / 60);
        return minutes >= 60 ? Math.floor(minutes / 60) + " h " + (minutes % 60) + " min" : minutes + " min";
    }

    readonly property string title: kind === "net" ? "Network" : kind === "bt" ? "Bluetooth" : kind === "audio" ? "Sound" : kind === "battery" ? "Battery" : kind === "window" ? "Window" : ""

    readonly property var win: Hyprland.activeToplevel && Hyprland.activeToplevel.lastIpcObject ? Hyprland.activeToplevel.lastIpcObject : null

    // Tray menus: the menu on show, and the menus above it when inside a submenu.
    property var menuStack: []
    readonly property var menuHandle: menuStack.length > 0 ? menuStack[menuStack.length - 1] : Ui.trayMenu

    // Another icon's menu starts at its top level.
    readonly property var trayRoot: Ui.trayMenu
    onTrayRootChanged: menuStack = []

    onKindChanged: {
        menuStack = [];
        if (kind === "about")
            About.refresh();
    }

    function gib(kb: real): string {
        return Math.round(kb / 1048576) + " GiB";
    }

    // The machine, as label and value; a fact mujo could not find is left out.
    readonly property var facts: {
        const a = root.about;
        if (!a)
            return [];
        return [["Machine", a.host], ["System", a.os], ["Kernel", a.kernel], ["Hyprland", a.hyprland], ["Processor", a.cpu], ["Graphics", a.gpu], ["Memory", root.gib(a.memory_kb)], ["Disk", a.disk.percent + "% of " + root.gib(a.disk.total_kb)], ["Packages", a.packages === null ? null : String(a.packages)], ["Uptime", root.duration(a.uptime_s)]].filter(f => f[1]);
    }

    QsMenuOpener {
        id: opener
        menu: root.kind === "tray" ? root.menuHandle : null
    }

    readonly property var lines: {
        if (kind === "net") {
            if (Net.ssid !== "")
                return [Net.ssid, "Signal " + Net.signal + "%", "Click: choose a network"];
            if (Net.wired)
                return ["Wired connection", "Click: choose a network"];
            return [Net.wifiEnabled ? "Not connected" : "Wi-Fi is off", "Click: choose a network", "Right click: Wi-Fi on or off"];
        }
        if (kind === "bt") {
            const adapter = Bluetooth.defaultAdapter;
            if (!adapter || !adapter.enabled)
                return ["Off", "Right click: switch on"];
            const names = root.connected.map(d => d.name);
            return (names.length > 0 ? names : ["No device connected"]).concat(["Click: devices"]);
        }
        if (kind === "audio")
            return [Audio.sink ? (Audio.sink.description || Audio.sink.name) : "No output", Audio.muted ? "Muted" : Audio.volume + "%"];
        if (kind === "battery") {
            const device = Battery.device;
            if (!Battery.present)
                return ["No battery"];
            const left = Battery.charging ? device.timeToFull : device.timeToEmpty;
            return [Battery.percent + "%, " + (Battery.charging ? "charging" : "on battery"), left > 0 ? root.duration(left) + (Battery.charging ? " until full" : " left") : (Battery.charging ? "Plugged in" : ""), Settings.chargeLimit < 100 ? "Charging stops at " + Settings.chargeLimit + "%" : "No charge limit"].filter(line => line !== "");
        }
        if (kind === "window") {
            if (!root.win)
                return ["No window is focused"];
            return [root.win.title || root.win.class, root.win.class, root.win.size[0] + " x " + root.win.size[1] + (root.win.floating ? ", floating" : ", tiled"), "Workspace " + root.win.workspace.name + (root.win.xwayland ? ", XWayland" : "")];
        }
        return [];
    }

    Column {
        id: body

        x: Tokens.spaceMd
        y: Tokens.spaceMd
        width: root.bodyWidth
        spacing: Tokens.spaceXs

        Text {
            visible: root.title !== ""
            text: root.title
            color: Tokens.accent
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontXs
        }

        Repeater {
            model: root.lines

            delegate: Text {
                required property string modelData
                required property int index

                width: body.width
                text: modelData
                color: index === 0 ? Tokens.textPrimary : Tokens.textMuted
                elide: Text.ElideRight
                font.family: Tokens.fontFamily
                font.pixelSize: index === 0 ? Tokens.fontMd : Tokens.fontSm
                font.weight: index === 0 ? Tokens.weightEmphasis : Tokens.weightRegular
            }
        }

        // The about card: who this machine is, then how mujo is doing.
        Row {
            visible: root.kind === "about"
            spacing: Tokens.spaceMd

            Logo {
                anchors.verticalCenter: parent.verticalCenter
                size: Tokens.spaceXxl + Tokens.spaceMd
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: "mujo"
                    color: Tokens.textPrimary
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLg
                    font.weight: Tokens.weightEmphasis
                }

                Text {
                    text: root.about ? root.about.mujo.version + (root.about.mujo.commit ? "  " + root.about.mujo.commit : "") : "Reading…"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                }
            }
        }

        Item {
            visible: root.kind === "about"
            width: body.width
            height: Tokens.spaceXs
        }

        Repeater {
            model: root.kind === "about" ? root.facts : []

            delegate: Item {
                id: fact

                required property var modelData

                width: body.width
                height: factValue.implicitHeight

                Text {
                    id: factLabel
                    width: Math.round(body.width * 0.28)
                    text: fact.modelData[0]
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }

                Text {
                    id: factValue
                    anchors.left: factLabel.right
                    anchors.right: parent.right
                    text: fact.modelData[1]
                    color: Tokens.textPrimary
                    elide: Text.ElideRight
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
            }
        }

        Rectangle {
            visible: root.kind === "about" && root.about !== null
            width: body.width
            height: Tokens.borderThin
            color: Tokens.borderSubtle
        }

        // Health, updates and the snapshots of the last update: a coloured
        // dot, a line of text and, where there is something to do, a button.
        Repeater {
            model: {
                const a = root.kind === "about" ? root.about : null;
                if (!a)
                    return [];
                const rows = [];
                const d = a.doctor;
                rows.push({
                    state: !d ? "idle" : d.failed > 0 ? "bad" : d.warnings > 0 ? "warn" : "good",
                    text: !d ? "Health not checked" : d.failed > 0 ? d.failed + " problem" + (d.failed === 1 ? "" : "s") + " found" : d.warnings > 0 ? d.warnings + " warning" + (d.warnings === 1 ? "" : "s") : "Everything is in order",
                    action: "Details",
                    entry: "System: health check (doctor)"
                });
                rows.push({
                    state: Updates.count > 0 ? "warn" : "good",
                    text: Updates.count > 0 ? Updates.count + " update" + (Updates.count === 1 ? "" : "s") + " waiting" : "Up to date",
                    action: Updates.count > 0 ? "Update" : "",
                    entry: "System: update mujo and packages"
                });
                if (a.snapshot && a.snapshot.post !== null && a.snapshot.packages.length > 0)
                    rows.push({
                        state: "idle",
                        text: "Last update: " + a.snapshot.packages.length + " package" + (a.snapshot.packages.length === 1 ? "" : "s"),
                        action: "Rollback plan",
                        entry: "System: show what rolling back the last update would do"
                    });
                return rows;
            }

            delegate: Item {
                id: health

                required property var modelData

                width: body.width
                height: Math.max(healthText.implicitHeight, healthChip.visible ? healthChip.implicitHeight : 0) + Tokens.spaceXs

                Rectangle {
                    id: healthDot
                    anchors.verticalCenter: parent.verticalCenter
                    width: Tokens.spaceSm
                    height: Tokens.spaceSm
                    radius: Tokens.radiusFull
                    color: health.modelData.state === "good" ? Tokens.stateSuccess : health.modelData.state === "warn" ? Tokens.stateWarning : health.modelData.state === "bad" ? Tokens.stateError : Tokens.textMuted
                }

                Text {
                    id: healthText
                    anchors.left: healthDot.right
                    anchors.leftMargin: Tokens.spaceSm
                    anchors.right: healthChip.visible ? healthChip.left : parent.right
                    anchors.rightMargin: Tokens.spaceSm
                    anchors.verticalCenter: parent.verticalCenter
                    text: health.modelData.text
                    color: Tokens.textPrimary
                    elide: Text.ElideRight
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }

                Chip {
                    id: healthChip
                    visible: health.modelData.action !== ""
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    label: health.modelData.action
                    onClicked: {
                        Mujo.run(["menu", "run", health.modelData.entry]);
                        Ui.popout = "";
                    }
                }
            }
        }

        Text {
            visible: root.kind === "about" && root.about !== null && root.about.recent.length > 0
            topPadding: Tokens.spaceXs
            text: "Latest changes"
            color: Tokens.accent
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontXs
        }

        // The newest journal entries; one that can be undone has a button.
        Repeater {
            model: root.kind === "about" && root.about ? root.about.recent : []

            delegate: Item {
                id: change

                required property var modelData

                width: body.width
                height: Math.max(changeText.implicitHeight, undo.visible ? undo.implicitHeight : 0) + Tokens.spaceXs

                Text {
                    id: changeText
                    anchors.left: parent.left
                    anchors.right: undo.visible ? undo.left : parent.right
                    anchors.rightMargin: Tokens.spaceSm
                    anchors.verticalCenter: parent.verticalCenter
                    // Folders are left out of file names to keep the line short.
                    text: change.modelData.summary.replace(/\/[^ ]*\//g, "")
                    color: change.modelData.undone ? Tokens.textMuted : Tokens.textPrimary
                    elide: Text.ElideRight
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }

                Chip {
                    id: undo
                    visible: change.modelData.reversible && !change.modelData.undone
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Undo"
                    onClicked: {
                        Mujo.run(["undo", change.modelData.id]);
                        aboutAgain.restart();
                    }
                }
            }
        }

        // Read the card again once an undo has had time to finish.
        Timer {
            id: aboutAgain
            interval: 1200
            onTriggered: About.refresh()
        }

        // Actions on the focused window. These are window management, which
        // goes to Hyprland directly, like the keybindings do.
        Flow {
            visible: root.kind === "window" && root.win !== null
            width: body.width
            spacing: Tokens.spaceXs

            Chip {
                label: "Float"
                onClicked: Hyprland.dispatch('hl.dsp.window.float({ action = "toggle" })')
            }
            Chip {
                label: "Fullscreen"
                onClicked: {
                    Hyprland.dispatch('hl.dsp.window.fullscreen({ action = "toggle", mode = "fullscreen" })');
                    Ui.popout = "";
                }
            }
            Chip {
                label: "Maximize"
                onClicked: Hyprland.dispatch('hl.dsp.window.fullscreen({ action = "toggle", mode = "maximized" })')
            }
            Chip {
                label: "Close"
                onClicked: {
                    Hyprland.dispatch("hl.dsp.window.close()");
                    Ui.popout = "";
                }
            }
        }

        // Power profile, in the battery pop-out.
        Row {
            visible: root.kind === "battery"
            spacing: Tokens.spaceXs

            Repeater {
                model: [
                    {
                        name: "power-saver",
                        label: "Saver",
                        value: PowerProfile.PowerSaver
                    },
                    {
                        name: "balanced",
                        label: "Balanced",
                        value: PowerProfile.Balanced
                    },
                    {
                        name: "performance",
                        label: "Fast",
                        value: PowerProfile.Performance
                    }
                ]

                delegate: Chip {
                    required property var modelData
                    visible: modelData.name !== "performance" || PowerProfiles.hasPerformanceProfile
                    label: modelData.label
                    chosen: PowerProfiles.profile === modelData.value
                    onClicked: Mujo.run(["power", "profile", modelData.name])
                }
            }
        }

        // A tray icon's menu.
        Chip {
            visible: root.kind === "tray" && root.menuStack.length > 0
            label: "Back"
            onClicked: root.menuStack = root.menuStack.slice(0, -1)
        }

        Repeater {
            model: root.kind === "tray" ? opener.children : []

            delegate: Item {
                id: entry

                required property QsMenuEntry modelData

                width: body.width
                height: modelData.isSeparator ? Tokens.spaceSm : Tokens.spaceXxl

                Rectangle {
                    visible: entry.modelData.isSeparator
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: Tokens.borderThin
                    color: Tokens.borderSubtle
                }

                Rectangle {
                    visible: !entry.modelData.isSeparator
                    anchors.fill: parent
                    radius: Tokens.radiusSm
                    color: entryArea.containsMouse && entry.modelData.enabled ? Tokens.bgControl : "transparent"

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Tokens.spaceSm
                        anchors.right: parent.right
                        anchors.rightMargin: Tokens.spaceSm
                        anchors.verticalCenter: parent.verticalCenter
                        text: (entry.modelData.checkState === Qt.Checked ? "\u2713 " : "") + entry.modelData.text + (entry.modelData.hasChildren ? "  \u203a" : "")
                        color: entry.modelData.enabled ? Tokens.textPrimary : Tokens.textMuted
                        elide: Text.ElideRight
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontSm
                    }

                    MouseArea {
                        id: entryArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: entry.modelData.enabled
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (entry.modelData.hasChildren) {
                                root.menuStack = root.menuStack.concat([entry.modelData]);
                            } else {
                                entry.modelData.triggered();
                                Ui.popout = "";
                            }
                        }
                    }
                }
            }
        }

        // Volume slider: click or drag.
        Item {
            visible: root.kind === "audio"
            width: body.width
            height: Tokens.spaceXl

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: Tokens.spaceSm
                radius: Tokens.radiusFull
                color: Tokens.bgControl

                Rectangle {
                    width: parent.width * Audio.volume / 100
                    height: parent.height
                    radius: Tokens.radiusFull
                    color: Audio.muted ? Tokens.textMuted : Tokens.accent

                    Behavior on width {
                        Anim {
                            duration: Tokens.durationFast
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor

                // One mujo run per rest of the pointer, not one per pixel.
                property int wanted: -1

                function ask(x: real): void {
                    wanted = Math.max(0, Math.min(100, Math.round(x * 100 / width)));
                    send.restart();
                }

                onPressed: event => ask(event.x)
                onPositionChanged: event => {
                    if (pressed)
                        ask(event.x);
                }

                Timer {
                    id: send
                    interval: Tokens.durationFast
                    onTriggered: Mujo.run(["audio", "volume", String(parent.wanted)])
                }
            }
        }
    }
}
