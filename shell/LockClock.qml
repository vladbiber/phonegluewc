import Quickshell
import QtQuick

// the lock's clock and date in one of five styles, placed as on the lock; the theme never changes it, it sits on the wallpaper
Item {
    id: root

    property string style: Phone.conf.lock_clock || "dot"
    // auto, white, accent or wallpaper
    property string tint: Phone.conf.lock_clock_color || "auto"
    property string wallpaper: Auth.config.wallpaper
    // auto: near black over a light wallpaper behind the clock, white over a dark one
    readonly property color autoInk: sampler.light ? Qt.rgba(0.08, 0.08, 0.08, 0.9) : Phone.white
    // the accent as saved: the light theme's black stand-in for white is not for the wallpaper
    readonly property color ink: tint === "accent" ? Phone.accentSaved : tint === "wallpaper" ? sampler.found
        : tint === "white" ? Phone.white : autoInk
    readonly property color dateInk: tint === "white" || (tint === "auto" && !sampler.light) ? Phone.grey
        : tint === "auto" ? Qt.rgba(0.08, 0.08, 0.08, 0.7) : ink
    readonly property color wallColor: sampler.found
    // false when the wallpaper has no colour of its own to offer
    readonly property bool wallDistinct: sampler.distinct
    // where the clock must end, e.g. the PIN pad's top; tall styles shrink to fit above it
    property real room: height
    function fit(h) { return h > 0 ? Math.min(1, (room - 72 - 12) / h) : 1; }
    readonly property string time: Qt.formatTime(clock.date, "HH:mm")
    readonly property string date: Qt.formatDate(clock.date, "dddd, d MMMM")

    SystemClock { id: clock; precision: SystemClock.Minutes }

    component DateLine: Text {
        text: root.date
        color: root.dateInk
        font.family: Phone.font
        font.pixelSize: 17
    }
    component Digits: Text {
        color: root.ink
        font.family: Phone.font
        font.features: { "tnum": 1 }
    }

    // 1: the dot matrix
    Column {
        visible: root.style === "dot"
        anchors { top: parent.top; topMargin: 72; horizontalCenter: parent.horizontalCenter }
        spacing: 16
        DotClock {
            anchors.horizontalCenter: parent.horizontalCenter
            time: root.time
            ink: root.ink
            colon: root.tint === "accent" ? Phone.white : Phone.accentSaved
        }
        DateLine { anchors.horizontalCenter: parent.horizontalCenter }
    }

    // 2: tall thin condensed digits across the width, the date above
    TextMetrics {
        id: thinM
        font.family: Phone.font
        font.styleName: "ExtraCondensed Thin"
        font.features: { "tnum": 1 }
        font.pixelSize: 100
        text: "00:00"
    }
    Column {
        visible: root.style === "thin"
        anchors { top: parent.top; topMargin: 72; horizontalCenter: parent.horizontalCenter }
        transformOrigin: Item.Top
        scale: root.fit(implicitHeight)
        DateLine { anchors.horizontalCenter: parent.horizontalCenter }
        Digits {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.time
            font.styleName: "ExtraCondensed Thin"
            font.pixelSize: Math.floor(100 * (root.width - 40) / Math.max(1, thinM.advanceWidth))
        }
    }

    // 3: big bold classic
    Column {
        visible: root.style === "bold"
        anchors { top: parent.top; topMargin: 80; horizontalCenter: parent.horizontalCenter }
        Digits {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.time
            font.weight: Font.Black
            font.pixelSize: 104
        }
        DateLine { anchors.horizontalCenter: parent.horizontalCenter }
    }

    // 4: small and light at the top left, the date under it
    Column {
        visible: root.style === "small"
        anchors { top: parent.top; topMargin: 76; left: parent.left; leftMargin: 28 }
        Digits {
            text: root.time
            font.weight: Font.Light
            font.pixelSize: 60
        }
        DateLine {}
    }

    // 5: hours over minutes
    Column {
        visible: root.style === "stacked"
        anchors { top: parent.top; topMargin: 72; horizontalCenter: parent.horizontalCenter }
        transformOrigin: Item.Top
        scale: root.fit(implicitHeight)
        DateLine { anchors.horizontalCenter: parent.horizontalCenter }
        Digits {
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            text: root.time.replace(":", "\n")
            font.weight: Font.Bold
            font.pixelSize: 150
            lineHeight: 0.82
        }
    }

    // the top half, where every style draws
    WallLuma { id: sampler; wallpaper: root.wallpaper }
}
