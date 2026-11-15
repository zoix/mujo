// Colour changes cross-fade.
import QtQuick
import qs.theme

ColorAnimation {
    duration: Tokens.durationFast
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Tokens.easeStandard
}
