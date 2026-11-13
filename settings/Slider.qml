import QtQuick

// a dot along a line; moved reports while dragging, released at the end
Item {
    id: root
    property real value: 0      // 0..1
    property real low: 0
    readonly property bool dragging: area.pressed
    signal moved(real value)
    signal released(real value)
    x: S.margin
    width: parent.width - 2 * S.margin
    height: 52
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: 4; radius: 2
        color: S.surface
    }
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: knob.x + knob.width / 2; height: 4; radius: 2
        color: S.accent
    }
    Rectangle {
        id: knob
        anchors.verticalCenter: parent.verticalCenter
        x: root.value * (root.width - width)
        width: 26; height: 26; radius: 13
        color: S.white
    }
    MouseArea {
        id: area
        anchors.fill: parent
        preventStealing: true
        function at(px) { return Math.max(root.low, Math.min(1, (px - knob.width / 2) / (root.width - knob.width))); }
        onPressed: mouse => { root.value = at(mouse.x); root.moved(root.value); }
        onPositionChanged: mouse => { root.value = at(mouse.x); root.moved(root.value); }
        onReleased: mouse => root.released(root.value)
    }
}
