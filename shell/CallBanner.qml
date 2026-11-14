import Quickshell
import Quickshell.Wayland
import QtQuick

// an incoming Android call over whatever is open: caller, app and the two answers
PanelWindow {
    id: root
    anchors { top: true; left: true; right: true }
    implicitHeight: card.height + 20
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "phone-call"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: card }

    Rectangle {
        id: card
        x: 10
        y: 10
        width: parent.width - 20
        height: 92
        radius: 30
        color: "#1c1c1e"
        AppIcon {
            id: icon
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            entry: ({ name: Droid.call ? Droid.call.app : "?", icon: Droid.call ? Droid.call.icon : "" })
            size: 48
        }
        Column {
            anchors { left: icon.right; leftMargin: 12; right: buttons.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 2
            Text {
                width: parent.width
                text: Droid.call ? Droid.call.who : ""
                elide: Text.ElideRight
                color: "#ffffff"
                font.family: Phone.font
                font.pixelSize: 19
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: Droid.call ? Droid.call.app + " call" : ""
                elide: Text.ElideRight
                color: "#a1a1a6"
                font.family: Phone.font
                font.pixelSize: 14
            }
        }
        Row {
            id: buttons
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            spacing: 14
            CallButton { size: 56; labelled: false; onTapped: Droid.decline() }
            CallButton { size: 56; labelled: false; accept: true; onTapped: Droid.answer() }
        }
    }
}
