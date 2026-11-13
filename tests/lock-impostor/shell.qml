import Quickshell
import Quickshell.Wayland
import QtQuick

// a stranger claiming the keyboard's name, to see that it stays under the lock
ShellRoot {
    PanelWindow {
        anchors { top: true; bottom: true; left: true; right: true }
        color: "#ff0000"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "phone-keyboard"
    }
}
