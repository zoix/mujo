// The lock screen: a Wayland session lock on every screen, unlocked by the
// user's password through PAM. `karma power lock` calls lock().
//
// While locked, a marker file exists in the runtime directory. If this
// process dies and is started again (karma-ui.service does that), it finds
// the marker and locks again straight away; Hyprland lets it take over the
// lock that was left behind.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs.theme
import qs.components

Scope {
    id: root

    property bool busy: false
    property bool failed: false
    property string password: ""

    readonly property string marker: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/karma-locked"

    function lock(): void {
        root.failed = false;
        sessionLock.locked = true;
        Quickshell.execDetached(["touch", root.marker]);
    }

    function unlock(): void {
        sessionLock.locked = false;
        Quickshell.execDetached(["rm", "-f", root.marker]);
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
                    text: root.busy ? "Checking..." : root.failed ? "That password is not right. Try again." : "Type your password and press Enter"
                    color: root.failed ? Tokens.stateError : Tokens.textMuted
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontSm
                }
            }
        }
    }
}
