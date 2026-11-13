import Quickshell
import QtQuick
import "Icons.js" as Icons

// a vector icon drawn at the window's real pixels, on whole pixels so it stays sharp at 2.75x
Image {
    id: root

    property string name: ""
    property color color: Phone.white
    property int level: 0
    property real size: 16
    readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : 1
    readonly property real px: Math.round(size * dpr) / dpr

    width: px
    height: px
    sourceSize: Qt.size(Math.round(size * dpr), Math.round(size * dpr))
    source: Icons.url(name, color, level)
    smooth: false
}
