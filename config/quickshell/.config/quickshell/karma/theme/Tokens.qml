pragma Singleton

// Design tokens for the interface. The values live in tokens.json next to
// this file, which `karma theme build` generates from design/tokens.json.
// They are read at run time, so a new accent or a switch between light and
// dark changes the colours in place, without reloading the interface.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var t: JSON.parse(file.text())

    function reload(): void {
        file.reload();
    }

    FileView {
        id: file
        path: Quickshell.shellPath("theme/tokens.json")
        blockLoading: true
        watchChanges: true
        onFileChanged: file.reload()
        onLoaded: {
            try {
                root.t = JSON.parse(file.text());
            } catch (error) {
                console.warn("karma: tokens.json is not valid JSON:", error);
            }
        }
    }

    // Colour roles
    readonly property color bgFrame: t.bgFrame
    readonly property color bgBase: t.bgBase
    readonly property color bgRaised: t.bgRaised
    readonly property color bgControl: t.bgControl
    readonly property color borderSubtle: t.borderSubtle
    readonly property color textPrimary: t.textPrimary
    readonly property color textMuted: t.textMuted
    readonly property color textOnAccent: t.textOnAccent
    readonly property color accent: t.accent
    readonly property color stateSuccess: t.stateSuccess
    readonly property color stateWarning: t.stateWarning
    readonly property color stateError: t.stateError
    readonly property color stateInfo: t.stateInfo
    readonly property string accentName: t.accentName
    readonly property var accentColors: t.accentColors
    readonly property string mode: t.mode

    // Typography
    readonly property string fontFamily: t.fontFamily
    readonly property string fontIcon: t.fontIcon
    readonly property int fontXs: t.fontXs
    readonly property int fontSm: t.fontSm
    readonly property int fontMd: t.fontMd
    readonly property int fontLg: t.fontLg
    readonly property int fontXl: t.fontXl
    readonly property int fontDisplay: t.fontDisplay
    readonly property int weightRegular: t.weightRegular
    readonly property int weightEmphasis: t.weightEmphasis
    readonly property int weightHeavy: t.weightHeavy

    // Spacing, shape, layout
    readonly property int spaceXs: t.spaceXs
    readonly property int spaceSm: t.spaceSm
    readonly property int spaceMd: t.spaceMd
    readonly property int spaceLg: t.spaceLg
    readonly property int spaceXl: t.spaceXl
    readonly property int spaceXxl: t.spaceXxl
    readonly property int radiusSm: t.radiusSm
    readonly property int radiusMd: t.radiusMd
    readonly property int radiusLg: t.radiusLg
    readonly property int radiusXl: t.radiusXl
    readonly property int radiusFull: t.radiusFull
    readonly property int borderThin: t.borderThin
    readonly property int borderFocus: t.borderFocus
    readonly property int frame: t.frame
    readonly property int bar: t.bar
    readonly property int gapIn: t.gapIn
    readonly property int gapOut: t.gapOut
    readonly property int osdWidth: t.osdWidth
    readonly property int osdHeight: t.osdHeight
    readonly property int notificationWidth: t.notificationWidth
    readonly property int launcherWidth: t.launcherWidth
    readonly property int row: t.row
    readonly property int icon: t.icon
    readonly property int button: t.button
    readonly property int thumbWidth: t.thumbWidth
    readonly property int thumbHeight: t.thumbHeight
    readonly property int card: t.card
    // The frame and its panels: the frame colour, see-through with "glass" on.
    readonly property real panelOpacity: t.panelOpacity
    readonly property color panel: Qt.alpha(bgFrame, panelOpacity)
    readonly property int ring: t.ring

    // How long transient UI stays on screen, in ms (not affected by reduce_motion)
    readonly property int notificationTimeout: t.notificationTimeout
    readonly property int osdTimeout: t.osdTimeout

    // Motion (durations are 0 when reduce_motion is on)
    readonly property bool reduceMotion: t.reduceMotion
    readonly property int durationFast: t.durationFast
    readonly property int durationNormal: t.durationNormal
    readonly property int durationSlow: t.durationSlow
    readonly property var easeStandard: t.easeStandard
    readonly property var easeEnter: t.easeEnter
    readonly property var easeExit: t.easeExit
}
