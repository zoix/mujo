// The power panel: slides in from the right edge. Lock and suspend run at
// once; log out, reboot and shut down ask for a second press, because they
// cannot be undone. Everything runs through `mujo power`.
import QtQuick
import Quickshell
import qs.theme
import qs.components
import qs.services

Item {
    id: root

    property bool active: false
    property int index: 0
    property int armed: -1

    readonly property var actions: [
        {
            name: "lock",
            label: "Lock",
            glyph: "",
            confirm: false
        },
        {
            name: "suspend",
            label: "Sleep",
            glyph: "",
            confirm: false
        },
        {
            name: "logout",
            label: "Log out",
            glyph: "",
            confirm: true
        },
        {
            name: "reboot",
            label: "Reboot",
            glyph: "",
            confirm: true
        },
        {
            name: "shutdown",
            label: "Shut down",
            glyph: "",
            confirm: true
        }
    ]

    implicitWidth: column.implicitWidth + Tokens.spaceMd + Tokens.spaceMd
    implicitHeight: column.implicitHeight + Tokens.spaceMd + Tokens.spaceMd

    function activate(at: int): void {
        const action = root.actions[at];
        root.index = at;
        if (action.confirm && root.armed !== at) {
            root.armed = at;
            return;
        }
        Mujo.run(action.confirm ? ["power", action.name, "--yes"] : ["power", action.name]);
        Ui.closeAll();
    }

    onActiveChanged: {
        root.armed = -1;
        root.index = 0;
        if (active)
            keys.forceActiveFocus();
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                Ui.closeAll();
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J || event.key === Qt.Key_Tab) {
                root.index = (root.index + 1) % root.actions.length;
                root.armed = -1;
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K || event.key === Qt.Key_Backtab) {
                root.index = (root.index + root.actions.length - 1) % root.actions.length;
                root.armed = -1;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                root.activate(root.index);
            } else {
                return;
            }
            event.accepted = true;
        }
    }

    Column {
        id: column

        x: Tokens.spaceMd
        y: Tokens.spaceMd
        spacing: Tokens.spaceSm

        Repeater {
            model: root.actions

            delegate: Column {
                id: entry

                required property var modelData
                required property int index
                readonly property bool selected: root.index === index
                readonly property bool armed: root.armed === index

                spacing: Tokens.spaceXs

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Tokens.button
                    height: Tokens.button
                    radius: Tokens.radiusFull
                    color: entry.armed ? Tokens.stateError : entry.selected ? Tokens.accent : Tokens.bgBase

                    Behavior on color {
                        Fade {}
                    }

                    Glyph {
                        anchors.centerIn: parent
                        text: entry.modelData.glyph
                        color: entry.armed || entry.selected ? Tokens.textOnAccent : Tokens.textPrimary
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            if (root.index !== entry.index) {
                                root.index = entry.index;
                                root.armed = -1;
                            }
                        }
                        onClicked: root.activate(entry.index)
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Tokens.button + Tokens.spaceLg
                    horizontalAlignment: Text.AlignHCenter
                    text: entry.armed ? "Again to confirm" : entry.modelData.label
                    color: entry.armed ? Tokens.stateError : entry.selected ? Tokens.textPrimary : Tokens.textMuted
                    wrapMode: Text.Wrap
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontXs
                }
            }
        }
    }
}
