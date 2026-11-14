// The standard motion: every size and position change in the UI uses it.
import QtQuick
import qs.theme

NumberAnimation {
    duration: Tokens.durationNormal
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Tokens.easeStandard
}
