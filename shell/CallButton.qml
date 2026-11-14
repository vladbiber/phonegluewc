import QtQuick

// a round Accept or Decline, its word under it
Item {
    id: root
    property bool accept: false
    property real size: 64
    property bool labelled: true
    signal tapped()
    width: size
    height: size + (labelled ? 26 : 0)
    Rectangle {
        width: root.size
        height: root.size
        radius: root.size / 2
        color: root.accept ? "#34c759" : "#ff3b30"
        opacity: tap.pressed ? 0.7 : 1
        Icon {
            anchors.centerIn: parent
            name: root.accept ? "phone" : "hangup"
            color: "#ffffff"
            size: root.size * 0.48
        }
    }
    Text {
        visible: root.labelled
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
        text: root.accept ? "Accept" : "Decline"
        color: "#ffffff"
        font.family: Phone.font
        font.pixelSize: 14
    }
    MouseArea { id: tap; anchors.fill: parent; onClicked: root.tapped() }
}
