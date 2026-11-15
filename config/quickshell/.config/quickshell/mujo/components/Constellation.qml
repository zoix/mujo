// A slow constellation: points on three rings that turn at different
// speeds, joined by faint lines to the ring inside them, with small pulses
// travelling inward along the lines. Drawn for the lock screen; still when
// reduce-motion is on. `energy` (0 to 1) makes it glow a little, for music.
import QtQuick
import qs.theme

Canvas {
    id: root

    property real time: 0
    property real energy: 0
    property color dot: Tokens.accent
    property color line: Tokens.textMuted

    readonly property var rings: [
        {
            radius: 0.16,
            count: 7,
            speed: 0.030
        },
        {
            radius: 0.29,
            count: 13,
            speed: -0.018
        },
        {
            radius: 0.43,
            count: 21,
            speed: 0.011
        }
    ]

    function point(ring: int, index: int): var {
        const r = root.rings[ring];
        const size = Math.min(root.width, root.height);
        const angle = index / r.count * Math.PI * 2 + root.time * r.speed;
        const wobble = 1 + 0.03 * Math.sin(root.time * 0.2 + index * 1.7 + ring);
        return {
            x: root.width / 2 + Math.cos(angle) * r.radius * size * wobble,
            y: root.height / 2 + Math.sin(angle) * r.radius * size * wobble
        };
    }

    onDotChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    Timer {
        interval: 50
        repeat: true
        running: root.visible && !Tokens.reduceMotion
        onTriggered: {
            root.time += 0.05;
            root.requestPaint();
        }
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const centre = {
            x: width / 2,
            y: height / 2
        };
        const glow = 1 + root.energy;

        // Lines from each point to the nearest point one ring in (or the centre).
        ctx.lineWidth = 1;
        for (let ring = 0; ring < rings.length; ring++) {
            for (let i = 0; i < rings[ring].count; i++) {
                const from = point(ring, i);
                const to = ring === 0 ? centre : point(ring - 1, Math.round(i * rings[ring - 1].count / rings[ring].count) % rings[ring - 1].count);
                ctx.strokeStyle = Qt.alpha(root.line, 0.16);
                ctx.beginPath();
                ctx.moveTo(from.x, from.y);
                ctx.lineTo(to.x, to.y);
                ctx.stroke();

                // A pulse on its way in.
                const phase = (root.time * 0.06 + i * 0.37 + ring * 0.21) % 1;
                ctx.fillStyle = Qt.alpha(root.dot, 0.5 * (1 - phase) * glow);
                ctx.beginPath();
                ctx.arc(from.x + (to.x - from.x) * phase, from.y + (to.y - from.y) * phase, 1.6, 0, Math.PI * 2);
                ctx.fill();
            }
        }

        for (let ring = 0; ring < rings.length; ring++) {
            for (let i = 0; i < rings[ring].count; i++) {
                const p = point(ring, i);
                ctx.fillStyle = Qt.alpha(root.dot, Math.min(1, (0.35 + 0.2 * ring) * glow));
                ctx.beginPath();
                ctx.arc(p.x, p.y, 2.2 + (2 - ring) * 0.6, 0, Math.PI * 2);
                ctx.fill();
            }
        }
    }
}
