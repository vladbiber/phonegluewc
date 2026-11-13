import QtQuick

// a line up to a round thumb that stays under the finger, dots for the rest; the icon end has its own tap
Item {
    id: root

    property real value: 0
    property bool dimmed: false
    property string icon: ""
    property color iconColor: Phone.fg
    readonly property real startX: 44
    readonly property real endPad: 12
    readonly property real track: width - startX - endPad
    readonly property real at: Math.max(0, Math.min(1, value))
    readonly property real thumbX: startX + at * track
    readonly property int dots: Math.max(2, Math.floor(track / 11) + 1)
    signal moved(real v)
    signal iconTapped()

    height: 44

    Repeater {
        model: root.dots
        delegate: Rectangle {
            required property int index
            readonly property real dotX: root.startX + index / (root.dots - 1) * root.track
            x: dotX - 1.5
            anchors.verticalCenter: parent.verticalCenter
            visible: dotX > root.thumbX + 12
            width: 3
            height: 3
            radius: 1.5
            color: Phone.mix("#6a6a6a", "#aaaaaa")
        }
    }
    Rectangle {
        x: root.startX
        anchors.verticalCenter: parent.verticalCenter
        width: root.thumbX - x
        height: 4
        radius: 2
        color: root.dimmed ? Phone.dim : Phone.fg
    }
    Rectangle {
        x: root.thumbX - 10
        anchors.verticalCenter: parent.verticalCenter
        width: 20
        height: 20
        radius: 10
        color: root.dimmed ? Phone.dim : Phone.fg
    }
    Icon {
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        size: 22
        color: root.iconColor
    }
    MouseArea {
        anchors.fill: parent
        preventStealing: true
        property bool onIcon: false
        function set(x) { root.moved(Math.max(0, Math.min(1, (x - root.startX) / root.track))); }
        onPressed: mouse => {
            onIcon = mouse.x < root.startX - 4;
            if (!onIcon)
                set(mouse.x);
        }
        onPositionChanged: mouse => { if (!onIcon) set(mouse.x); }
        onClicked: mouse => { if (onIcon && mouse.x < root.startX) root.iconTapped(); }
    }
}
