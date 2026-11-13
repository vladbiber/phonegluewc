import QtQuick

// one cell of the menu: an app, or a folder of them
Item {
    id: root

    // { entry } or { folder, apps }
    required property var item
    // a hold then a move drags it instead of asking about pinning
    property bool canDrag: false
    // a drop here makes or fills a folder
    property bool target: false
    property int iconSize: 54
    signal tapped()
    signal dragStarted(point p)
    signal dragMoved(point p)
    signal dragEnded(point p)

    readonly property var entry: item && item.entry ? item.entry : null
    readonly property bool isFolder: !!item && item.folder !== undefined
    readonly property bool dragging: tap.moving
    opacity: dragging ? 0.25 : 1

    Rectangle {
        anchors.centerIn: icon
        width: root.iconSize + 14
        height: width
        radius: width / 2
        color: "transparent"
        border.color: Phone.fg
        border.width: 2
        visible: root.target
    }
    Item {
        id: icon
        anchors { top: parent.top; topMargin: 8; horizontalCenter: parent.horizontalCenter }
        width: root.iconSize
        height: root.iconSize
        scale: tap.pressed && !root.dragging ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }

        AppIcon {
            anchors.fill: parent
            visible: !root.isFolder
            entry: root.entry
            size: root.iconSize
        }
        Rectangle {
            anchors.fill: parent
            visible: root.isFolder
            radius: width / 2
            color: Phone.mix("#2a2a2a", "#e2e2e2")

            Grid {
                anchors.centerIn: parent
                columns: 2
                spacing: 3
                Repeater {
                    model: root.isFolder ? root.item.apps.slice(0, 4) : []
                    delegate: AppIcon {
                        required property var modelData
                        entry: modelData
                        size: Math.round(root.iconSize * 0.34)
                    }
                }
            }
        }
    }
    Text {
        anchors { top: icon.bottom; topMargin: 7; left: parent.left; right: parent.right; leftMargin: 4; rightMargin: 4 }
        text: root.isFolder ? root.item.folder : root.entry ? root.entry.name : ""
        color: Phone.fg
        font.family: Phone.font
        font.pixelSize: 12
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }
    MouseArea {
        id: tap
        anchors.fill: parent
        pressAndHoldInterval: 500
        property bool armed: false
        property bool moving: false
        property point start
        preventStealing: armed
        function askPin() {
            if (root.entry)
                Phone.askPin(root.entry, mapToItem(null, width / 2, 0).x, Window.height - mapToItem(null, 0, 0).y);
        }
        onPressed: mouse => { armed = false; moving = false; start = Qt.point(mouse.x, mouse.y); }
        onPressAndHold: {
            if (root.canDrag)
                armed = true;
            else
                askPin();
        }
        onPositionChanged: mouse => {
            if (armed && !moving && Math.hypot(mouse.x - start.x, mouse.y - start.y) > 8) {
                moving = true;
                root.dragStarted(mapToItem(null, mouse.x, mouse.y));
            } else if (moving) {
                root.dragMoved(mapToItem(null, mouse.x, mouse.y));
            }
        }
        onReleased: mouse => {
            if (moving)
                root.dragEnded(mapToItem(null, mouse.x, mouse.y));
            else if (armed)
                askPin();
            armed = false;
            moving = false;
        }
        // a lost grab puts it back where it was
        onCanceled: {
            if (moving)
                root.dragEnded(Qt.point(-1, -1));
            armed = false;
            moving = false;
        }
        onClicked: root.tapped()
    }
}
