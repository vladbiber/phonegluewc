import QtQuick
import "DotFont.js" as DotFont

// a named bitmap from DotFont drawn as round dots, from glueqs
Canvas {
    id: root
    property string name: "dot"
    property real px: 2
    property real gap: 1
    property color color: S.white
    readonly property var bitmap: DotFont.ICONS[name] || DotFont.ICONS.dot
    readonly property real cell: px + gap
    implicitWidth: bitmap[0].length * cell - gap
    implicitHeight: bitmap.length * cell - gap
    onNameChanged: requestPaint()
    onColorChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        ctx.fillStyle = String(color);
        for (let y = 0; y < bitmap.length; y++)
            for (let x = 0; x < bitmap[y].length; x++)
                if (bitmap[y][x] === "1") {
                    ctx.beginPath();
                    ctx.arc(x * cell + px / 2, y * cell + px / 2, px / 2, 0, 2 * Math.PI);
                    ctx.fill();
                }
    }
}
