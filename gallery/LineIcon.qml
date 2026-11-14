import QtQuick

// thin line glyphs on a 24 unit grid, one stroke weight for all (the same drawing the video player uses)
Canvas {
    id: root
    property string name: "back"
    property color color: S.white
    property real size: 26
    width: size; height: size
    onNameChanged: requestPaint()
    onColorChanged: requestPaint()
    onSizeChanged: requestPaint()
    onPaint: {
        const c = getContext("2d");
        c.reset();
        c.scale(size / 24, size / 24);
        c.strokeStyle = String(color);
        c.fillStyle = String(color);
        c.lineWidth = 2.6;
        c.lineCap = "round";
        c.lineJoin = "round";
        c.beginPath();
        switch (name) {
        case "back": c.moveTo(15, 4); c.lineTo(7, 12); c.lineTo(15, 20); break;
        case "info": c.arc(12, 12, 9.5, 0, 2 * Math.PI); c.moveTo(12, 11); c.lineTo(12, 17); break;
        case "trash":
            c.moveTo(4, 7); c.lineTo(20, 7); c.moveTo(9, 7); c.lineTo(9, 4.5); c.lineTo(15, 4.5); c.lineTo(15, 7);
            c.moveTo(6, 7); c.lineTo(7.2, 20); c.lineTo(16.8, 20); c.lineTo(18, 7);
            c.moveTo(10, 11); c.lineTo(10, 16); c.moveTo(14, 11); c.lineTo(14, 16);
            break;
        case "close": c.moveTo(6, 6); c.lineTo(18, 18); c.moveTo(18, 6); c.lineTo(6, 18); break;
        case "plus": c.moveTo(12, 5); c.lineTo(12, 19); c.moveTo(5, 12); c.lineTo(19, 12); break;
        case "check": c.moveTo(5, 12.5); c.lineTo(10, 17.5); c.lineTo(19, 7); break;
        case "send": c.moveTo(5, 13); c.lineTo(5, 20); c.lineTo(19, 20); c.lineTo(19, 13); c.moveTo(12, 16); c.lineTo(12, 4); c.moveTo(7.5, 8.5); c.lineTo(12, 4); c.lineTo(16.5, 8.5); break;
        case "play": c.moveTo(7, 3.5); c.lineTo(20, 12); c.lineTo(7, 20.5); c.closePath(); break;
        }
        c.stroke();
        if (name === "info") {
            c.beginPath();
            c.arc(12, 7.6, 1.15, 0, 2 * Math.PI);
            c.fill();
        }
    }
}
