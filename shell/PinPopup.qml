import Quickshell
import Quickshell.Wayland
import QtQuick

// exists only while a hold asks about an app; a tap anywhere else dismisses it
PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "phone-pin"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property bool pinned: Phone.pinnedIds.includes(Phone.pinId)
    readonly property bool blocked: !pinned && Phone.trayFull
    readonly property bool onHome: Screens.hasApp(Phone.pinId)
    property bool homeFull: false

    MouseArea {
        anchors.fill: parent
        onClicked: Phone.pinId = ""
    }
    Rectangle {
        width: 250
        height: 224
        radius: 20
        color: Phone.mix("#262626", "#ffffff")
        x: Math.max(12, Math.min(parent.width - width - 12, Phone.pinX - width / 2))
        // never over the status bar
        y: Math.max(44, parent.height - Phone.pinBottom - height - 8)

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 56
            radius: 20
            color: home.pressed ? Phone.mix("#333333", "#dcdcdc") : "transparent"

            Text {
                anchors.centerIn: parent
                color: Phone.fg
                font.family: Phone.font
                font.pixelSize: root.homeFull ? 13 : 15
                text: root.homeFull ? "No room on this home screen"
                    : root.onHome ? "Remove from current home screen" : "Add to current home screen"
            }
            MouseArea {
                id: home
                anchors.fill: parent
                enabled: !root.homeFull
                onClicked: {
                    if (Screens.setApp(Phone.pinId, !root.onHome))
                        Phone.pinId = "";
                    else
                        root.homeFull = true;
                }
            }
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 56 }
            height: 56
            radius: 20
            color: fresh.pressed ? Phone.mix("#333333", "#dcdcdc") : "transparent"

            Text {
                anchors.centerIn: parent
                color: Phone.fg
                font.family: Phone.font
                font.pixelSize: 15
                text: "New window"
            }
            MouseArea {
                id: fresh
                anchors.fill: parent
                onClicked: Phone.newWindow(Phone.apps.find(e => e.id === Phone.pinId))
            }
        }
        // pin stays where it was, right above the finger
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 56 }
            height: 56
            radius: 20
            color: remove.pressed ? Phone.mix("#333333", "#dcdcdc") : "transparent"

            Text {
                anchors.centerIn: parent
                color: Phone.fg
                font.family: Phone.font
                font.pixelSize: 15
                text: "Uninstall"
            }
            MouseArea {
                id: remove
                anchors.fill: parent
                onClicked: Phone.askRemove(Phone.pinId)
            }
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 56
            radius: 20
            color: action.pressed ? Phone.mix("#333333", "#dcdcdc") : "transparent"

            Text {
                anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Phone.fg
                font.family: Phone.font
                font.pixelSize: root.blocked || Phone.pinFailed ? 13 : 15
                text: Phone.pinFailed ? "Could not save the tray"
                    : root.blocked ? "Tray is full. Unpin an app first."
                    : root.pinned ? "Unpin from tray" : "Pin to tray"
            }
            MouseArea {
                id: action
                anchors.fill: parent
                enabled: !root.blocked && !Phone.pinFailed
                onClicked: Phone.setPinned(Phone.pinId, !root.pinned)
            }
        }
    }
}
