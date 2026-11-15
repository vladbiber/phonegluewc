import Quickshell
import Quickshell.Wayland
import QtQuick

// the top bar; keeps windows below it and opens the pull down sheet
PanelWindow {
    id: root

    anchors { top: true; left: true; right: true }
    implicitHeight: Status.barHeight
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: Status.barHeight
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "phone-statusbar"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    BarRow { id: row; anchors.fill: parent }
    Binding { target: Dyn; property: "iconsLeft"; value: row.iconsLeft }

    // left half notifications, right half quick settings; the camera hole is in the left half
    MouseArea {
        anchors.fill: parent
        property real startY: 0
        property real startT: 0
        onPressed: mouse => {
            startY = mouse.y;
            startT = Date.now();
            Status.barHeld = true;
            Status.side = mouse.x < root.width / 2 ? 0 : 1;
        }
        onPositionChanged: mouse => {
            const dy = mouse.y - startY;
            if (!Status.dragging && dy <= 0)
                return;
            Status.grab(startT);
            Status.track(dy);
            Status.pull = Math.max(0.001, Math.min(1, dy / root.screen.height));
        }
        onReleased: {
            Status.barHeld = false;
            if (Status.dragging)
                Status.releasePull(root.screen.height, 0.3);
        }
        onCanceled: {
            Status.barHeld = false;
            if (Status.dragging)
                Status.settleTo(0);
        }
    }
}
