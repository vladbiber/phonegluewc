import Quickshell
import Quickshell.Wayland
import QtQuick

// the boot login: under the keyboard's layer and over everything else
PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    color: Phone.black
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "phone-greeter"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    LockView { anchors.fill: parent }
}
