// The wallpaper on the background layer of one screen. A new image fades in
// over the old one as soon as it is decoded. Without a wallpaper the screen is the plain base colour.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.theme
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
