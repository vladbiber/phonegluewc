import QtQuick

// 64 samples of a wallpaper: is the band from..to (fractions of its height) light, and its most colourful sample made light enough to read; white on a grey one
Canvas {
    id: root
    property string wallpaper: ""
    property real from: 0
    property real to: 0.5
    property color found: Phone.white
    property bool distinct: false
    property bool light: false
    width: 8
    height: 8
    opacity: 0
    readonly property string src: wallpaper ? "file://" + wallpaper : ""
    onSrcChanged: if (src) loadImage(src); else { found = Phone.white; distinct = false; light = false; }
    onFromChanged: requestPaint()
    onToChanged: requestPaint()
    Component.onCompleted: if (src) loadImage(src)
    onImageLoaded: requestPaint()
    onPaint: {
        if (!src || !isImageLoaded(src))
            return;
        const ctx = getContext("2d");
        ctx.drawImage(src, 0, 0, 8, 8);
        const d = ctx.getImageData(0, 0, 8, 8).data;
        const r0 = Math.floor(from * 8), r1 = Math.max(r0 + 1, Math.ceil(to * 8));
        let best = 0, at = 0, luma = 0;
        for (let i = 0; i < d.length; i += 4) {
            const c = Math.max(d[i], d[i + 1], d[i + 2]) - Math.min(d[i], d[i + 1], d[i + 2]);
            if (c > best) { best = c; at = i; }
            const row = Math.floor(i / 32);
            if (row >= r0 && row < r1)
                luma += (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]) / 255 / (8 * (r1 - r0));
        }
        const c = Qt.rgba(d[at] / 255, d[at + 1] / 255, d[at + 2] / 255, 1);
        distinct = best >= 24;
        light = luma > 0.6;
        found = !distinct ? Phone.white : Qt.hsla(c.hslHue, Math.max(0.55, c.hslSaturation), 0.72, 1);
    }
}
