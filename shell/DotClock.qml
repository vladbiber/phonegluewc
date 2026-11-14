import QtQuick

// the time as a dot matrix, repainted once a minute; the colon carries the accent
Canvas {
    id: root

    property string time: "00:00"
    property int pitch: 12
    readonly property real dot: pitch * 4.6 / 12
    readonly property var glyphs: ({
        "0": ["01110","10001","10011","10101","11001","10001","01110"],
        "1": ["00100","01100","00100","00100","00100","00100","01110"],
        "2": ["01110","10001","00001","00010","00100","01000","11111"],
        "3": ["11111","00010","00100","00010","00001","10001","01110"],
        "4": ["00010","00110","01010","10010","11111","00010","00010"],
        "5": ["11111","10000","11110","00001","00001","10001","01110"],
        "6": ["00110","01000","10000","11110","10001","10001","01110"],
        "7": ["11111","00001","00010","00100","01000","01000","01000"],
        "8": ["01110","10001","10001","01110","10001","10001","01110"],
        "9": ["01110","10001","10001","01111","00001","00010","01100"],
        ":": ["0","0","1","0","1","0","0"],
        "%": ["11001","11010","00010","00100","01000","01011","10011"]
    })

    implicitWidth: 26 * pitch
    implicitHeight: 7 * pitch
    onTimeChanged: requestPaint()
    property color colon: Phone.accent
    property color ink: Phone.white
    onColonChanged: requestPaint()
    onInkChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        let col = 0;
        for (const ch of time) {
            const rows = glyphs[ch];
            ctx.fillStyle = ch === ":" ? colon : ink;
            for (let y = 0; y < 7; y++) {
                for (let x = 0; x < rows[y].length; x++) {
                    if (rows[y][x] !== "1")
                        continue;
                    ctx.beginPath();
                    ctx.arc((col + x + 0.5) * pitch, (y + 0.5) * pitch, dot, 0, 2 * Math.PI);
                    ctx.fill();
                }
            }
            col += rows[0].length + 1;
        }
    }
}
