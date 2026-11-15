// One icon from the Nerd Font. The proportional variant of the font is
// used: in the monospace one an icon is wider than its cell and sits off
// centre.
import QtQuick
import qs.theme

Text {
    color: Tokens.textPrimary
    font.family: Tokens.fontIcon
    font.pixelSize: Tokens.fontXl
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter

    Behavior on color {
        Fade {}
    }
}
