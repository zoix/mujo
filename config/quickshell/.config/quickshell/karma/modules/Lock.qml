// The lock screen: a Wayland session lock on every screen, unlocked by the
// user's password through PAM, or by a fingerprint if one is enrolled
// (fprintd). The two are checked side by side: the reader waits for a
// finger the whole time, and the password is checked when Enter is pressed.
// `karma power lock` calls lock().
//
// While locked, a marker file exists in the runtime directory. If this
// process dies and is started again (karma-ui.service does that), it finds
// the marker and locks again straight away; Hyprland lets it take over the
// lock that was left behind.
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.theme
import qs.components
import qs.services

Scope {
    id: root

    property bool busy: false
    property bool failed: false
    property string password: ""

    readonly property string marker: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/karma-locked"

    // Whether a finger is enrolled (asked from fprintd each time the screen locks).
    property bool fingerprint: false
    property string fingerHint: ""

    function lock(): void {
        root.failed = false;
        root.fingerHint = "";
        sessionLock.locked = true;
        Quickshell.execDetached(["touch", root.marker]);
        enrolled.running = true;
    }

    function unlock(): void {
        sessionLock.locked = false;
        Quickshell.execDetached(["rm", "-f", root.marker]);
        root.fingerprint = false;
        if (finger.active)
            finger.abort();
    }

    Process {
        id: enrolled
        command: ["fprintd-list", Quickshell.env("USER")]
        stdout: StdioCollector {
            onStreamFinished: {
                root.fingerprint = sessionLock.locked && this.text.includes(" - #");
                if (root.fingerprint)
                    finger.start();
            }
        }
    }

    // The fingerprint reader, asked again after every attempt while locked.
    PamContext {
        id: finger
        configDirectory: Quickshell.shellPath("pam")
        config: "fingerprint.conf"

        onCompleted: result => {
            if (!sessionLock.locked)
                return;
            if (result === PamResult.Success) {
                root.unlock();
            } else {
                root.fingerHint = "Fingerprint not recognised";
                again.restart();
            }
        }

        onError: root.fingerprint = false
    }

    Timer {
        id: again
        interval: 800
        onTriggered: {
            if (sessionLock.locked && root.fingerprint && !finger.active)
                finger.start();
        }
    }

    // Finding the marker at start-up means the previous process died locked.
    FileView {
        path: root.marker
        printErrors: false
        onLoaded: root.lock()
    }

    function submit(text: string): void {
        if (root.busy || text === "")
            return;
        root.password = text;
        root.failed = false;
        root.busy = true;
        if (!pam.start()) {
            root.busy = false;
            root.failed = true;
            root.password = "";
        }
    }

    PamContext {
        id: pam
        configDirectory: Quickshell.shellPath("pam")
        config: "password.conf"

        onPamMessage: {
            if (pam.responseRequired)
                pam.respond(root.password);
        }

        onCompleted: result => {
            root.busy = false;
            root.password = "";
            if (result === PamResult.Success)
                root.unlock();
            else
                root.failed = true;
        }

        onError: {
            root.busy = false;
            root.password = "";
            root.failed = true;
        }
    }

    WlSessionLock {
        id: sessionLock

        WlSessionLockSurface {
            id: surface
            color: Tokens.bgFrame

            SystemClock {
                id: clock
                precision: SystemClock.Minutes
            }

            readonly property MprisPlayer player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null

            // The wallpaper, blurred and dimmed, behind everything.
            Image {
                id: backdrop
                anchors.fill: parent
                visible: false
                source: Settings.wallpaper === "" ? "" : "file://" + Settings.wallpaper
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: surface.width / 4
            }

            MultiEffect {
                anchors.fill: parent
                visible: Settings.wallpaper !== ""
                source: backdrop
                blurEnabled: true
                blur: 1
                blurMax: 48
            }

            Rectangle {
                anchors.fill: parent
                color: Tokens.bgFrame
                opacity: Settings.wallpaper === "" ? 0 : 0.55
            }

            // A slow constellation around the clock; it glows with the music.
            PwNodePeakMonitor {
                id: level
                node: Pipewire.defaultAudioSink
                enabled: surface.player !== null && surface.player.isPlaying && !Tokens.reduceMotion
            }

            Constellation {
                anchors.fill: parent
                energy: level.enabled ? Math.min(1, level.peak * 1.5) : 0

                Behavior on energy {
                    Anim {}
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Tokens.spaceLg

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    color: Tokens.accent
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontDisplay + Tokens.fontDisplay
                    font.weight: Tokens.weightHeavy
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLg
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Tokens.spaceSm
                    Layout.maximumWidth: Tokens.card + Tokens.card
                    visible: Quotes.text !== ""
                    text: Quotes.text
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    color: Tokens.textPrimary
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: -Tokens.spaceSm
                    visible: Quotes.text !== ""
                    text: Quotes.credit
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Tokens.spaceXl
                    implicitWidth: Tokens.notificationWidth
                    implicitHeight: input.implicitHeight + Tokens.spaceMd + Tokens.spaceMd
                    radius: Tokens.radiusFull
                    color: Tokens.bgControl
                    border.width: Tokens.borderFocus
                    border.color: root.failed ? Tokens.stateError : input.activeFocus ? Tokens.accent : Tokens.borderSubtle

                    Behavior on border.color {
                        Fade {}
                    }

                    TextInput {
                        id: input
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spaceLg
                        anchors.rightMargin: Tokens.spaceLg
                        verticalAlignment: TextInput.AlignVCenter
                        horizontalAlignment: TextInput.AlignHCenter
                        focus: true
                        enabled: !root.busy
                        echoMode: TextInput.Password
                        font.letterSpacing: Tokens.spaceSm
                        inputMethodHints: Qt.ImhSensitiveData
                        clip: true
                        color: Tokens.textPrimary
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontLg
                        onAccepted: {
                            root.submit(input.text);
                            input.text = "";
                        }
                        onTextEdited: root.failed = false
                        Component.onCompleted: input.forceActiveFocus()
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: Notifs.history.length > 0
                    text: Notifs.history.length === 1 ? "1 notification" : Notifs.history.length + " notifications"
                    color: Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }

                // What is playing, with previous, play or pause, next.
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Tokens.spaceLg
                    visible: surface.player !== null
                    spacing: Tokens.spaceSm

                    BarButton {
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: surface.player.previous()

                        Glyph {
                            anchors.centerIn: parent
                            text: "\uf048"
                            font.pixelSize: Tokens.fontMd
                        }
                    }

                    BarButton {
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: surface.player.togglePlaying()

                        Glyph {
                            anchors.centerIn: parent
                            text: surface.player && surface.player.isPlaying ? "\uf04c" : "\uf04b"
                            font.pixelSize: Tokens.fontMd
                            color: Tokens.accent
                        }
                    }

                    BarButton {
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: surface.player.next()

                        Glyph {
                            anchors.centerIn: parent
                            text: "\uf051"
                            font.pixelSize: Tokens.fontMd
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, Tokens.notificationWidth)
                        text: surface.player ? (surface.player.trackTitle || surface.player.identity) + (surface.player.trackArtist ? "  " + surface.player.trackArtist : "") : ""
                        color: Tokens.textMuted
                        elide: Text.ElideRight
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontSm
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.busy ? "Checking..." : root.failed ? "That password is not right. Try again." : root.fingerprint ? (root.fingerHint !== "" ? root.fingerHint + ". Try again, or type your password" : "Touch the fingerprint reader, or type your password") : "Type your password and press Enter"
                    color: root.failed ? Tokens.stateError : Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
            }
        }
    }
}
