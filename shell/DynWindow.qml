import Quickshell
import Quickshell.Wayland
import QtQuick

// only as tall as the card gets: this layer costs a buffer, and input stays on the shape
PanelWindow {
    id: root

    anchors { top: true; left: true; right: true }
    implicitHeight: Dyn.windowH
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "phone-camera"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // nothing active or the sheet on its way: touches go straight through
    readonly property bool takes: (!Dyn.idle || Dyn.moving) && (Status.pull === 0 || Dyn.held) && !Dyn.fullHidden
    mask: takes ? shapeRegion : noRegion
    Region { id: noRegion }
    Region {
        id: shapeRegion
        item: shape.pillItem
        Region { item: shape.bubbleItem; intersection: Intersection.Combine }
    }

    DynShape {
        id: shape
        anchors.fill: parent
    }
}
