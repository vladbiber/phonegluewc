import Quickshell
import QtQuick

// the list behind the panel's active apps button; exists only while open
Rectangle {
    id: root

    required property var model
    signal back()

    color: Phone.mix("#0c0c0c", "#f2f2f2")

    // the panel's tap-to-close must not fire through this
    MouseArea { anchors.fill: parent }

    // changes wait for the finger: a row must not move or be rebuilt under a tap
    // a copy, not a binding: a binding would follow the model under the finger too
    property var shownRows: []
    Component.onCompleted: shownRows = model.rows
    Connections {
        target: root.model
        function onRowsChanged() { if (!root.pressing) root.shownRows = root.model.rows; }
    }
    // from the rows' own MouseAreas: a parent PointHandler never sees a press they accept
    property bool pressing: false
    function hold(p) {
        pressing = p;
        if (!p)
            Qt.callLater(() => root.shownRows = root.model.rows);
    }
    // the provider paints a missing theme icon as a magenta and black checker, and calls that Ready
    function goodTray(src) {
        const s = String(src);
        if (s === "")
            return false;
        if (!s.startsWith("image://icon/"))
            return true;
        return Quickshell.iconPath(s.slice(13).split("?")[0], true) !== "";
    }

    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Status.barHeight }
        height: 48
        Icon {
            color: Phone.fg
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            name: "back"
            size: 24
        }
        Text {
            x: 52
            anchors.verticalCenter: parent.verticalCenter
            text: root.model.title
            color: Phone.fg
            font.family: Phone.font
            font.pixelSize: 16
            font.weight: Font.Medium
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root.back()
        }
    }

    Text {
        visible: root.model.count === 0
        x: 16
        y: header.y + header.height + 8
        text: root.model.background ? "Nothing runs in the background" : "No active apps"
        color: Phone.dim
        font.family: Phone.font
        font.pixelSize: 14
    }

    Flickable {
        id: list
        anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; topMargin: 8; bottomMargin: 66; leftMargin: 16; rightMargin: 16 }
        clip: true
        contentHeight: rows.height
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: rows
            width: list.width
            spacing: 8
            Repeater {
                model: root.shownRows
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: rows.width
                    height: 64
                    radius: 16
                    color: Phone.card
                    border.color: Phone.mix("#2a2a2a", "#e2e2e2")

                    MouseArea {
                        anchors.fill: parent
                        onPressedChanged: root.hold(pressed)
                        onClicked: root.model.activate(row.modelData)
                    }
                    AppIcon {
                        x: 12
                        visible: !trayIcon.visible
                        anchors.verticalCenter: parent.verticalCenter
                        entry: ({ name: row.modelData.name || "?", icon: row.modelData.icon })
                        size: 36
                    }
                    Image {
                        id: trayIcon
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 36
                        sourceSize: Qt.size(108, 108)
                        visible: row.modelData.icon === "" && status === Image.Ready && root.goodTray(row.modelData.trayIcon)
                        source: root.goodTray(row.modelData.trayIcon) ? row.modelData.trayIcon : ""
                    }
                    Column {
                        x: 60
                        anchors.verticalCenter: parent.verticalCenter
                        width: action.x - x - 8
                        Text {
                            width: parent.width
                            text: row.modelData.name
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Phone.fg
                            font.family: Phone.font
                            font.pixelSize: 15
                        }
                        Text {
                            width: parent.width
                            readonly property int n: row.modelData.windows.length
                            visible: text !== ""
                            text: row.modelData.kind || (n > 1 ? n + " windows" : n === 0 && row.modelData.state === "idle" ? "In the background" : "")
                            color: Phone.dim
                            font.family: Phone.font
                            font.pixelSize: 12
                        }
                    }
                    Rectangle {
                        id: action
                        readonly property string mode: row.modelData.state
                        visible: mode !== "idle" || root.model.canClose(row.modelData)
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        width: 96
                        height: 36
                        radius: 18
                        color: mode === "force" ? Phone.accent : "transparent"
                        border.color: mode === "force" ? Phone.accent : Phone.dim
                        Text {
                            anchors.centerIn: parent
                            text: action.mode === "force" ? "Force stop" : root.model.background
                                ? (action.mode === "closing" ? "Stopping" : row.modelData.vpn ? "Disconnect" : "Stop")
                                : (action.mode === "closing" ? "Closing" : "Close")
                            color: action.mode === "closing" ? Phone.dim : action.mode === "force" ? Phone.inkOnAccent : Phone.fg
                            font.family: Phone.font
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                        // the whole height of the row is the target; Closing only swallows the tap
                        MouseArea {
                            anchors { fill: parent; margins: -12 }
                            onPressedChanged: root.hold(pressed)
                            onClicked: {
                                if (action.mode === "idle")
                                    root.model.close(row.modelData);
                                else if (action.mode === "force")
                                    root.model.force(row.modelData);
                            }
                        }
                    }
                }
            }
        }
    }
}
