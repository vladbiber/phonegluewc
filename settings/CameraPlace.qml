import Quickshell
import Quickshell.Wayland
import QtQuick

// A light screen so the black hole shows, a ring to lay over it. Dragging moves the ring by the finger's path, from anywhere, so the finger never hides it.
PanelWindow {
    id: root
    property var start: null
    property var known: null
    signal finished()

    anchors { top: true; bottom: true; left: true; right: true }
    color: "#c8c8c8"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "phonesettings-camera"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // 1080 wide panel pixels, as in phone.conf
    readonly property real unit: width / 1080
    property real hx: start ? start.x : 513.81
    property real hy: start ? start.y : 42.31
    property real hd: start ? start.d : 52.38
    function save(value) {
        S.save(["set", "phone", "camera_hole", value]);
        finished();
    }

    MouseArea {
        anchors.fill: parent
        property real px: 0
        property real py: 0
        onPressed: mouse => { px = mouse.x; py = mouse.y; }
        onPositionChanged: mouse => {
            root.hx = Math.max(0, Math.min(1080 - root.hd, root.hx + (mouse.x - px) / root.unit));
            root.hy = Math.max(0, Math.min(400, root.hy + (mouse.y - py) / root.unit));
            px = mouse.x;
            py = mouse.y;
        }
    }
    Rectangle {
        x: root.hx * root.unit - 2
        y: root.hy * root.unit - 2
        width: root.hd * root.unit + 4
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: "#d71921"
    }
    Rectangle {
        x: 16
        width: parent.width - 32
        anchors.verticalCenter: parent.verticalCenter
        height: card.implicitHeight + 32
        radius: 24
        color: S.black
        Column {
            id: card
            y: 16
            width: parent.width
            spacing: 8
            T {
                x: S.margin
                width: parent.width - 2 * S.margin
                text: "Drag anywhere to lay the red ring exactly around the camera. It moves with your finger from wherever you touch."
                font.pixelSize: 15
            }
            T {
                x: S.margin
                width: parent.width - 2 * S.margin
                text: "Size"
                color: S.grey
                font.pixelSize: 13
            }
            Slider {
                id: size
                width: parent.width - 2 * S.margin
                value: (root.hd - 8) / 192
                onMoved: v => {
                    const d = 8 + v * 192;
                    // about the ring's centre, so the size does not undo the position
                    root.hx = Math.max(0, Math.min(1080 - d, root.hx + (root.hd - d) / 2));
                    root.hy = Math.max(0, root.hy + (root.hd - d) / 2);
                    root.hd = d;
                }
            }
            Flow {
                x: S.margin
                width: parent.width - 2 * S.margin
                spacing: 8
                Btn {
                    text: "Reset"
                    visible: root.known !== null
                    onTapped: {
                        root.hx = root.known.x;
                        root.hy = root.known.y;
                        root.hd = root.known.d;
                    }
                }
                Btn { text: "Automatic"; onTapped: root.save("auto") }
                Btn { text: "Cancel"; onTapped: root.finished() }
                Btn { text: "Done"; primary: true; onTapped: root.save(root.hx.toFixed(2) + "," + root.hy.toFixed(2) + "," + root.hd.toFixed(2)) }
            }
        }
    }
}
