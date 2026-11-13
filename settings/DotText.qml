import QtQuick
import "DotFont.js" as DotFont

// a line of caps drawn as round dots, from glueqs
Canvas {
    id: root
    property string text: ""
    property real px: 2.4
    property real gap: 1.2
    property color color: S.white
    readonly property real cell: px + gap
    implicitWidth: Math.max(1, DotFont.textCells(text) * cell - gap)
    implicitHeight: 7 * cell - gap
    onTextChanged: requestPaint()
    onColorChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.fillStyle = String(color);
        let cx = 0;
        for (const ch of text) {
            const g = DotFont.glyph(ch);
            for (let y = 0; y < 7; y++)
                for (let x = 0; x < g[y].length; x++)
                    if (g[y][x] === "1") {
                        ctx.beginPath();
                        ctx.arc((cx + x) * cell + px / 2, y * cell + px / 2, px / 2, 0, 2 * Math.PI);
                        ctx.fill();
                    }
            cx += g[0].length + 1;
        }
    }
}
