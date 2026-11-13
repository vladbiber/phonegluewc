import Quickshell
import Quickshell.Wayland
import QtQuick

// only there when one is set; the cards copy this layer
PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    color: Phone.black
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "phone-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Image {
        anchors.fill: parent
        source: "file://" + Phone.wallpaper
        sourceSize: Qt.size(root.width * root.screen.devicePixelRatio, root.height * root.screen.devicePixelRatio)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
}
