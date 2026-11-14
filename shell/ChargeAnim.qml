import QtQuick

// charger in or out: a dot ring fills to the battery level around the level in dots, then fades
Item {
    id: root

    readonly property bool plugged: Status.chargePlugged
    readonly property int level: Status.chargeLevel
    readonly property color tone: plugged ? "#4cd964" : Phone.grey
    property real fill: 0

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.82 * face.opacity
    }
    Item {
        id: face
        anchors.centerIn: parent
        width: Math.min(root.width, root.height) * 0.62
        height: width
        opacity: 0
        scale: 0.92

        Canvas {
            id: ring
            anchors.fill: parent
            readonly property int dots: 60
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                const c = width / 2, r = c - 10, lit = Math.round(dots * root.fill);
                for (let i = 0; i < dots; i++) {
                    const a = -Math.PI / 2 + i * 2 * Math.PI / dots;
                    ctx.fillStyle = i < lit ? root.tone : Qt.rgba(1, 1, 1, 0.14);
                    ctx.beginPath();
                    ctx.arc(c + r * Math.cos(a), c + r * Math.sin(a), i < lit ? 5 : 3.5, 0, 2 * Math.PI);
                    ctx.fill();
                }
            }
            Connections {
                target: root
                function onFillChanged() { ring.requestPaint(); }
                function onToneChanged() { ring.requestPaint(); }
            }
        }
        Column {
            anchors.centerIn: parent
            spacing: 18
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "bolt"
                size: 34
                color: root.tone
                opacity: root.plugged ? 1 : 0.5
                SequentialAnimation on opacity {
                    running: root.plugged
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 650; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
                }
            }
            DotClock {
                anchors.horizontalCenter: parent.horizontalCenter
                pitch: 9
                time: Math.round(root.fill * 100) + "%"
                colon: root.tone
                implicitWidth: (time.length * 6 - 1) * pitch
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.plugged ? (root.level >= 100 ? "Charged" : "Charging") : "Unplugged"
                color: Phone.white
                opacity: 0.7
                font { family: Phone.font; pixelSize: 15; letterSpacing: 2; capitalization: Font.AllUppercase }
            }
        }
    }

    // plugged: counts up to the level; unplugged: shows the level, grey, a little longer
    SequentialAnimation {
        running: true
        ParallelAnimation {
            NumberAnimation { target: face; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: face; property: "scale"; to: 1; duration: 420; easing.type: Easing.OutBack }
            NumberAnimation {
                target: root; property: "fill"
                from: root.plugged ? 0 : root.level / 100; to: root.level / 100
                duration: root.plugged ? 1100 : 1; easing.type: Easing.OutCubic
            }
        }
        PauseAnimation { duration: root.plugged ? 1300 : 2100 }
        ParallelAnimation {
            NumberAnimation { target: face; property: "opacity"; to: 0; duration: 340 }
            NumberAnimation { target: face; property: "scale"; to: 1.04; duration: 340 }
        }
    }
}
