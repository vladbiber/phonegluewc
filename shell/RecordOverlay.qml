import Quickshell
import Quickshell.Wayland
import QtQuick

// the recorder's sheet, its countdown, and while it records a small control that can be moved
PanelWindow {
    id: root

    readonly property bool full: Recorder.stage !== ""
    screen: Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "phone-recorder"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: full ? allRegion : chipRegion
    Region { id: allRegion; width: root.width; height: root.height }
    Region { id: chipRegion; item: chip }

    Rectangle {
        anchors.fill: parent
        visible: root.full
        color: "#99000000"
        MouseArea { anchors.fill: parent; onClicked: Recorder.cancel() }
    }

    Rectangle {
        visible: Recorder.stage === "sheet"
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
        height: 270
        radius: 28
        color: "#1e1e1e"
        MouseArea { anchors.fill: parent }

        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 22 }
            spacing: 14
            Text {
                text: "Record the screen?"
                color: Phone.white
                font.family: Phone.font
                font.pixelSize: 20
                font.weight: Font.Medium
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: "Everything on screen is recorded, notifications too. Saved in Videos, Screen recordings."
                color: Phone.grey
                font.family: Phone.font
                font.pixelSize: 14
            }
            QuickTile {
                width: parent.width
                icon: "mic"
                label: "Record sound"
                sub: "Microphone"
                on: Recorder.sound
                MouseArea { anchors.fill: parent; onClicked: Phone.setConf("record_sound", Recorder.sound ? "off" : "on") }
            }
        }
        Row {
            anchors { right: parent.right; bottom: parent.bottom; margins: 18 }
            spacing: 10
            Repeater {
                model: [["Cancel", false], ["Start", true]]
                Rectangle {
                    required property var modelData
                    width: 104
                    height: 48
                    radius: 24
                    color: modelData[1] ? Phone.accent : "#2e2e2e"
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData[0]
                        color: Phone.white
                        font.family: Phone.font
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }
                    MouseArea { anchors.fill: parent; onClicked: parent.modelData[1] ? Recorder.go() : Recorder.cancel() }
                }
            }
        }
    }

    Text {
        visible: Recorder.stage === "count"
        anchors.centerIn: parent
        text: Recorder.count
        color: Phone.white
        font.family: Phone.font
        font.pixelSize: 120
        font.weight: Font.Light
    }

    // the time and a stop button; dragged anywhere, it stays where it was let go
    Rectangle {
        id: chip
        visible: !root.full && Status.recording
        x: root.width - width - 12
        y: 52
        width: row.width + 24
        height: 44
        radius: 22
        color: "#e0141414"
        border.color: "#3a3a3a"

        property int now: 0
        Timer { interval: 1000; repeat: true; running: chip.visible; triggeredOnStart: true; onTriggered: chip.now = Date.now() - Dyn.recStart }
        MouseArea {
            anchors.fill: parent
            drag.target: chip
            drag.minimumX: 0; drag.maximumX: root.width - chip.width
            drag.minimumY: 0; drag.maximumY: root.height - chip.height
        }
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 10
            Rectangle { width: 10; height: 10; radius: 5; color: Phone.accent; anchors.verticalCenter: parent.verticalCenter }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Dyn.clock(chip.now)
                color: Phone.white
                font.family: Phone.font
                font.pixelSize: 15
                font.features: { "tnum": 1 }
            }
            Rectangle {
                width: 32; height: 32; radius: 16
                color: stopArea.pressed ? "#444444" : "#2e2e2e"
                Icon { anchors.centerIn: parent; name: "stop"; color: Phone.white; size: 16 }
                MouseArea { id: stopArea; anchors.fill: parent; onClicked: Recorder.stop() }
            }
        }
    }
}
