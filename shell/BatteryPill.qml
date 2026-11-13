import Quickshell
import QtQuick

// the battery as a pill with the number inside, in one colour over both parts
Item {
    id: root

    property int level: 0
    property bool charging: false
    // the fill and the number inside it; swapped on a light status bar
    property color ink: Phone.white
    property color paper: "#141414"
    readonly property bool low: level <= 15 && !charging
    readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    function snap(v) { return Math.round(v * dpr) / dpr; }
    readonly property int shown: Math.max(0, Math.min(100, level))
    readonly property real inkW: ink.tightBoundingRect.width / dpr

    width: snap(charging ? 37 : 27)
    height: snap(12.5)

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: "#707070"
    }
    // a rectangular clip over the same pill: a straight edge at every level, and no layer
    // it overhangs the pill on three sides, or its rounding eats a row of the fill at fractional scales
    Item {
        x: -1
        y: -1
        width: 1 + (root.shown > 0 ? Math.max(2 / root.dpr, root.snap(root.width * root.shown / 100)) : 0)
        height: root.height + 2
        clip: true
        Rectangle {
            x: 1
            y: 1
            width: root.width
            height: root.height
            radius: height / 2
            color: root.low ? Phone.accent : root.ink
        }
    }
    TextMetrics {
        id: ink
        // measured at device size: at logical size hinting rounds the box by up to a whole logical pixel
        font.family: number.font.family
        font.weight: number.font.weight
        font.features: number.font.features
        font.pixelSize: number.font.pixelSize * root.dpr
        text: number.text
    }
    // height from one digit, or a lone 1 sits a pixel lower than the rest
    TextMetrics {
        id: digit
        font: ink.font
        text: "0"
    }
    Icon {
        id: bolt
        visible: root.charging
        name: "bolt"
        color: number.color
        size: 10
        x: root.snap((root.width - width - 1 - root.inkW) / 2)
        y: root.snap((root.height - height) / 2)
    }
    // placed by its ink, not its advance: a tabular 1 otherwise sits off centre
    // left unsnapped so the ink lands within a device pixel; 0.7 is measured for Noto Sans, baselineOffset rounds at logical size
    Text {
        id: number
        x: ((root.charging ? bolt.x + bolt.width + 1 + root.inkW / 2 : root.width / 2) - root.inkW / 2 - ink.tightBoundingRect.x / root.dpr)
        y: ((root.height - digit.tightBoundingRect.height / root.dpr) / 2 - digit.tightBoundingRect.y / root.dpr - baselineOffset + 0.7)
        text: root.shown
        color: root.paper
        font.family: Phone.font
        font.pixelSize: 11
        font.weight: Font.Medium
        font.features: { "tnum": 1 }
    }
}
