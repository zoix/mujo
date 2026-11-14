// The wallpaper on the background layer of one screen. A new image fades in
// over the old one as soon as it is decoded. Without a wallpaper the screen is the plain base colour.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.theme
import qs.components
import qs.services

PanelWindow {
    id: root

    color: Tokens.bgBase
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "karma-wallpaper"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    property string current: ""
    property string previous: ""
    // What should be on screen: the picker's preview, or else the setting.
    readonly property string wanted: Ui.wallPreview !== "" ? Ui.wallPreview : Settings.wallpaper

    onWantedChanged: {
        if (wanted === current)
            return;
        previous = current;
        front.opacity = 0;
        current = wanted;
        if (current === "")
            previous = "";
    }

    // Once karma has applied the previewed image the preview is over.
    Connections {
        target: Settings
        function onWallpaperChanged(): void {
            if (Settings.wallpaper === Ui.wallPreview)
                Ui.wallPreview = "";
        }
    }

    Image {
        anchors.fill: parent
        visible: root.previous !== ""
        source: root.previous === "" ? "" : "file://" + root.previous
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: root.width
        sourceSize.height: root.height
    }

    Image {
        id: front
        anchors.fill: parent
        visible: root.current !== ""
        source: root.current === "" ? "" : "file://" + root.current
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: root.width
        sourceSize.height: root.height
        // The fade starts when the image is decoded, not before.
        onStatusChanged: {
            if (status === Image.Ready)
                fade.restart();
        }
    }

    // A clock in the lower right corner of the desktop, and beside it a few
    // bars that follow the music while something is playing. They sit on
    // the wallpaper, so windows cover them.
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    readonly property bool playing: Mpris.players.values.some(p => p.isPlaying)

    PwNodePeakMonitor {
        id: level
        node: Pipewire.defaultAudioSink
        enabled: root.playing && Settings.desktopClock && !Tokens.reduceMotion
    }

    Row {
        visible: Settings.desktopClock
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: Tokens.frame + Tokens.spaceXxl
        anchors.bottomMargin: Tokens.frame + Tokens.spaceXl
        spacing: Tokens.spaceLg

        Row {
            visible: level.enabled
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Tokens.spaceMd
            spacing: Tokens.spaceXs

            Repeater {
                // Each bar answers the same level a little differently.
                model: [0.55, 0.85, 1, 0.7, 0.45]

                delegate: Rectangle {
                    required property real modelData
                    anchors.bottom: parent.bottom
                    width: Tokens.spaceXs
                    height: Tokens.spaceXs + Tokens.fontDisplay * Math.min(1, level.peak * 1.6) * modelData
                    radius: Tokens.radiusFull
                    color: Tokens.accent

                    Behavior on height {
                        Anim {
                            duration: Tokens.durationNormal
                        }
                    }
                }
            }
        }

        Column {
            Text {
                anchors.right: parent.right
                text: Qt.formatDateTime(clock.date, "HH:mm")
                color: Tokens.textPrimary
                style: Text.Outline
                styleColor: Tokens.bgFrame
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontDisplay + Tokens.fontDisplay
                font.weight: Tokens.weightHeavy
            }

            Text {
                anchors.right: parent.right
                text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                color: Tokens.textPrimary
                style: Text.Outline
                styleColor: Tokens.bgFrame
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontLg
            }
        }
    }

    NumberAnimation {
        id: fade
        target: front
        property: "opacity"
        to: 1
        duration: Tokens.durationSlow
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Tokens.easeStandard
    }
}
