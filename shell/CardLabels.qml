import Quickshell
import Quickshell.Wayland
import QtQuick

// never shown as it is: one row per workspace, the compositor copies a row above each card;
// below them the icon being carried, which it copies under the finger
PanelWindow {
    anchors { top: true; left: true }
    implicitWidth: 240
    implicitHeight: 28 * 9 + 56
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "phone-cardlabels"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Column {
        Repeater {
            model: 9
            // centred: the card's strip lies under the status bar, between the clock and the battery
            delegate: Item {
                required property int index
                readonly property var app: Phone.wsApp(index)
                width: 240
                height: 28
                Row {
                    id: label
                    readonly property var app: parent.app
                    readonly property int index: parent.index
                    anchors.centerIn: parent
                    spacing: 8

                AppIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    entry: parent.app
                    size: 20
                    visible: !!parent.app
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 150)
                    text: {
                        const app = parent.app;
                        const more = (Phone.counts[parent.index] || 0) - 1;
                        return app ? app.name + (more > 0 ? " +" + more : "") : "";
                    }
                    color: Phone.white
                    elide: Text.ElideRight
                    font.family: Phone.font
                    font.pixelSize: 13
                }
                }
            }
        }
        AppIcon {
            width: 56
            height: 56
            entry: Phone.dragEntry
            size: 56
            visible: !!Phone.dragEntry
        }
    }
}
