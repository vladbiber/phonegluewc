import Quickshell
import Quickshell.Wayland
import QtQuick

// the round button offered when the phone turns while rotation is locked
PanelWindow {
    id: root

    readonly property var deg: ({ normal: 0, "90": 90, "180": 180, "270": 270 })
    // wl_output 90 means the phone turned clockwise: its right side went down
    readonly property int turn: (deg[Status.rotateOffer] - deg[Status.orientation || "normal"] + 360) % 360
    anchors { bottom: true; left: turn === 270; right: turn === 90 }
    margins { bottom: 72; left: 20; right: 20 }
    implicitWidth: 52
    implicitHeight: 52
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "phone-rotate"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        id: ball
        anchors.centerIn: parent
        width: 48
        height: 48
        radius: 24
        color: Phone.surface
        border.color: "#2a2a2a"
        scale: 0.6
        opacity: 0
        Component.onCompleted: { scale = 1; opacity = 1; }
        Behavior on scale { enabled: Dyn.anim; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on opacity { enabled: Dyn.anim; NumberAnimation { duration: 160 } }
        Icon {
            anchors.centerIn: parent
            name: "rotate"
            size: 22
        }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: Status.rotateTo(Status.rotateOffer)
    }
}
