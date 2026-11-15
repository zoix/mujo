// Choosing the area for a screenshot. The screen is frozen and dimmed; the
// window under the pointer lights up. Click to take that window, or drag to
// take any rectangle. Escape or the right button cancels. The picture
// itself is taken by `mujo shot region --geometry ...`.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.theme
import qs.services

PanelWindow {
    id: root

    required property ShellScreen modelData
    readonly property bool active: Ui.picker && Ui.screen === modelData.name
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)

    // The chosen rectangle, in this screen's coordinates.
    property rect area: Qt.rect(0, 0, 0, 0)
    property point origin: Qt.point(0, 0)
    property bool dragging: false

    // Windows on the workspace in view, as rectangles on this screen.
    readonly property var windows: {
        if (!root.active || !root.monitor || !root.monitor.activeWorkspace)
            return [];
        return root.monitor.activeWorkspace.toplevels.values.filter(t => t.lastIpcObject && t.lastIpcObject.at).map(t => Qt.rect(t.lastIpcObject.at[0] - root.monitor.x, t.lastIpcObject.at[1] - root.monitor.y, t.lastIpcObject.size[0], t.lastIpcObject.size[1]));
    }

    function windowAt(x: real, y: real): rect {
        for (const w of root.windows) {
            if (x >= w.x && x <= w.x + w.width && y >= w.y && y <= w.y + w.height)
                return w;
        }
        return Qt.rect(0, 0, 0, 0);
    }

    function finish(): void {
        const a = root.area;
        Ui.picker = false;
        if (a.width < 2 || a.height < 2)
            return;
        take.geometry = Math.round(a.x + root.monitor.x) + "," + Math.round(a.y + root.monitor.y) + " " + Math.round(a.width) + "x" + Math.round(a.height);
        take.restart();
    }

    screen: modelData
    visible: root.active
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "mujo-picker"
    WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    onActiveChanged: {
        if (!active)
            return;
        root.area = Qt.rect(0, 0, 0, 0);
        root.dragging = false;
        Hyprland.refreshToplevels();
        keys.forceActiveFocus();
    }

    // Wait until this window is gone, so that it is not in the picture.
    Timer {
        id: take
        property string geometry: ""
        interval: 250
        onTriggered: Mujo.run(["shot", "region", "--geometry", geometry])
    }

    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: Ui.picker = false
    }

    // The screen as it was when the picker opened (one frame, not live).
    ScreencopyView {
        anchors.fill: parent
        captureSource: root.active ? root.modelData : null
        live: false
    }

    // Everything outside the chosen rectangle is dimmed: four rectangles around it.
    component Dim: Rectangle {
        color: Tokens.bgFrame
        opacity: 0.55
    }

    Dim {
        width: parent.width
        height: root.area.y
    }
    Dim {
        y: root.area.y + root.area.height
        width: parent.width
        height: parent.height - y
    }
    Dim {
        y: root.area.y
        width: root.area.x
        height: root.area.height
    }
    Dim {
        x: root.area.x + root.area.width
        y: root.area.y
        width: parent.width - x
        height: root.area.height
    }

    Rectangle {
        x: root.area.x
        y: root.area.y
        width: root.area.width
        height: root.area.height
        visible: root.area.width > 0
        color: "transparent"
        border.width: Tokens.borderFocus
        border.color: Tokens.accent
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Tokens.frame + Tokens.spaceLg
        text: "Click a window, or drag an area. Escape cancels."
        color: Tokens.textPrimary
        style: Text.Outline
        styleColor: Tokens.bgFrame
        font.family: Tokens.fontFamily
        font.pixelSize: Tokens.fontMd
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor

        onPositionChanged: event => {
            if (root.dragging) {
                root.area = Qt.rect(Math.min(root.origin.x, event.x), Math.min(root.origin.y, event.y), Math.abs(event.x - root.origin.x), Math.abs(event.y - root.origin.y));
            } else {
                root.area = root.windowAt(event.x, event.y);
            }
        }

        onPressed: event => {
            if (event.button === Qt.RightButton) {
                Ui.picker = false;
                return;
            }
            root.origin = Qt.point(event.x, event.y);
            root.dragging = true;
        }

        onReleased: event => {
            if (!root.dragging)
                return;
            root.dragging = false;
            // A click without a drag takes the window under the pointer.
            if (Math.abs(event.x - root.origin.x) < 4 && Math.abs(event.y - root.origin.y) < 4)
                root.area = root.windowAt(event.x, event.y);
            root.finish();
        }
    }
}
