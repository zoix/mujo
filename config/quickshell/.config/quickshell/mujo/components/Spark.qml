// A small line graph of a list of numbers, oldest first, filled underneath.
// `ceiling` is the value at the top edge; 0 takes the largest value in the list.
import QtQuick
import qs.theme

Canvas {
    id: root

    property var values: []
    property real ceiling: 0
    property color tint: Tokens.accent

    onValuesChanged: requestPaint()
    onTintChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const n = values.length;
        if (n < 2 || width <= 0 || height <= 0)
            return;
        const line = Tokens.borderFocus;
        const peak = Math.max(root.ceiling > 0 ? root.ceiling : Math.max.apply(null, values), 1e-9);
        const px = i => i * width / (n - 1);
        const py = v => height - line - Math.max(0, Math.min(1, v / peak)) * (height - line - line);
        ctx.beginPath();
        ctx.moveTo(px(0), py(values[0]));
        for (let i = 1; i < n; i++)
            ctx.lineTo(px(i), py(values[i]));
        ctx.lineWidth = line;
        ctx.lineJoin = "round";
        ctx.strokeStyle = root.tint;
        ctx.stroke();
        ctx.lineTo(width, height);
        ctx.lineTo(0, height);
        ctx.closePath();
        ctx.fillStyle = Qt.alpha(root.tint, 0.16);
        ctx.fill();
    }
}
