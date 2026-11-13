import Quickshell
import Quickshell.Wayland
import QtQuick

// always mapped; the compositor slides it in with the overview and on an empty
// workspace, and keeps it out of the way the rest of the time
PanelWindow {
    id: root

    // landscape: a column on the right, the compositor slides it in from that edge and leaves its taps plain
    readonly property bool side: Dyn.sideways
    anchors { bottom: true; right: true; left: !side; top: side }
    // the top 48 is the button row: only the buttons take touches, and the compositor keeps a swipe from them
    // the slots shrink to fit the count; labels only where the column has room for them
    readonly property int count: Phone.dock.length + 1
    readonly property int gap: root.side ? 0 : count > 5 ? 4 : 12
    readonly property real slotW: root.side ? 64 : Math.min(64, Math.floor((width - 16 - gap * (count - 1)) / count))
    readonly property real slotH: root.side ? Math.min(labels ? 72 : 54, Math.floor((height - Status.barHeight - 104) / count)) : labels ? 78 : 60
    readonly property bool labels: Phone.trayLabels && (!root.side || (height - Status.barHeight - 104) / count >= 66)
    readonly property real iconSize: root.side ? Math.min(46, slotH - (labels ? 22 : 8)) : Math.min(54, slotW - 6)
    implicitHeight: 48 + slotH
    implicitWidth: 112
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "phone-tray"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {
        y: root.side ? 0 : 48
        width: root.width
        height: root.side ? root.height : root.slotH
        Region { item: trayApps.visible ? trayApps : null; intersection: Intersection.Combine }
        Region { item: closeAll.visible ? closeAll : null; intersection: Intersection.Combine }
    }

    Rectangle {
        visible: Phone.trayPlate
        anchors.centerIn: grid
        width: grid.width + (root.side ? 12 : 16)
        height: grid.height + (root.side ? 16 : 4)
        radius: root.side ? 28 : Math.min(28, height / 2)
        color: Phone.card
        opacity: 0.85
    }
    // landscape: the apps and more fit between the two pills under the bar
    Grid {
        id: grid
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.side ? (parent.height + Status.barHeight - height) / 2 : parent.height - height
        columns: root.side ? 1 : root.count
        spacing: root.gap

        Repeater {
            model: Phone.dock
            delegate: Item {
                id: slot
                required property var modelData
                width: root.slotW
                height: root.slotH

                AppIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: root.labels ? 2 : (parent.height - height) / 2
                    entry: slot.modelData
                    size: root.iconSize
                    scale: tap.pressed ? 0.9 : 1
                    Behavior on scale { NumberAnimation { duration: 90 } }
                }
                Text {
                    visible: root.labels
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    width: parent.width + root.gap
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: slot.modelData.name
                    color: Phone.fg
                    font.family: Phone.font
                    font.pixelSize: 11
                }
                MouseArea {
                    id: tap
                    anchors.fill: parent
                    pressAndHoldInterval: 500
                    // shortcut: the pin popup is placed above the icon even in the landscape column, move it beside once it clips there
                    onClicked: Phone.launch(slot.modelData)
                    onPressAndHold: { holdX = mouseX; holdY = mouseY; Phone.askPin(slot.modelData, mapToItem(null, width / 2, 0).x, Window.height - mapToItem(null, 0, 0).y + 26) }
                    property real holdX
                    property real holdY
                    // the compositor opens the cards under the finger when they are not up; only a command it can start itself
                    onPositionChanged: {
                        if (Phone.pinId === slot.modelData.id && !slot.modelData.runInTerminal
                                && Math.hypot(mouseX - holdX, mouseY - holdY) > 8)
                            Phone.startIconDrag(slot.modelData);
                    }
                }
            }
        }

        // more apps
        Item {
            width: root.slotW
            height: root.slotH

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.labels ? 2 : (parent.height - height) / 2
                width: root.iconSize
                height: width
                radius: width / 2
                color: more.pressed ? Phone.mix("#2a2a2a", "#e2e2e2") : Phone.card

                Grid {
                    anchors.centerIn: parent
                    columns: 3
                    spacing: 5
                    Repeater {
                        model: 9
                        delegate: Rectangle {
                            width: 4
                            height: 4
                            radius: 2
                            color: Phone.fg
                        }
                    }
                }
            }
            Text {
                visible: root.labels
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
                text: "All apps"
                color: Phone.fg
                font.family: Phone.font
                font.pixelSize: 11
            }
            MouseArea {
                id: more
                anchors.fill: parent
                onClicked: Phone.menuOpen = true
            }
        }
    }

    // which home page is in view, in the button row the overview uses
    Row {
        readonly property int cols: Screens.columns("home")
        visible: !Phone.overview && cols > 1
        x: (root.width - width) / 2
        y: root.side ? root.height - 24 - height / 2 : 30 - height / 2
        spacing: 6
        Repeater {
            model: parent.cols
            delegate: Rectangle {
                required property int index
                width: 6
                height: 6
                radius: 3
                color: Phone.fg
                opacity: index === Screens.screenOf("home", -1).x ? 1 : 0.35
            }
        }
    }

    component RowPill: Item {
        id: pill
        property string text
        signal tapped()
        width: Math.min(root.side ? root.width - 8 : 1000, Math.max(96, label.implicitWidth + 32))
        height: 48
        opacity: Phone.overview ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: 34
            radius: 17
            color: hit.pressed ? Phone.mix("#2a2a2a", "#e2e2e2") : Phone.card
        }
        Text {
            id: label
            anchors.centerIn: parent
            text: pill.text
            color: Phone.fg
            font.family: Phone.font
            font.pixelSize: 14
        }
        MouseArea {
            id: hit
            anchors.fill: parent
            enabled: Phone.overview
            onClicked: pill.tapped()
        }
    }
    // what runs without a window: tray, apps whose windows closed, known daemons, VPNs; only while it shows
    LazyLoader {
        id: running
        active: Phone.overview
        AppModel { background: true }
    }
    Binding { target: Phone; property: "runningCount"; value: running.item ? running.item.count : 0 }
    RowPill {
        id: trayApps
        x: root.side ? (root.width - width) / 2 : 16
        y: root.side ? root.height - height : 0
        visible: Phone.overview && Phone.runningCount > 0
        text: "Tray apps " + Phone.runningCount
        onTapped: {
            Phone.runningOpen = true;
            Status.side = 1;
            Status.settleTo(1);
        }
    }
    RowPill {
        id: closeAll
        x: root.side ? (root.width - width) / 2 : root.width - width - 16
        y: root.side ? Status.barHeight : 0
        visible: Phone.closeAllShown
        text: "Close all"
        onTapped: Quickshell.execDetached(["phonegluewc-msg", "do", "closeall"])
    }
}
