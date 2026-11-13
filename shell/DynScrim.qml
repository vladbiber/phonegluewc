import Quickshell
import Quickshell.Wayland
import QtQuick

// while the card is open a touch outside closes it and reaches nothing below
PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "phone-camera-scrim"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {
        width: 100000
        height: 100000
        Region {
            intersection: Intersection.Subtract
            x: Dyn.pL
            y: Dyn.pT
            width: Dyn.pR - Dyn.pL
            height: Dyn.shapeH
        }
    }
    MouseArea {
        anchors.fill: parent
        onPressed: Dyn.collapse()
    }
}
