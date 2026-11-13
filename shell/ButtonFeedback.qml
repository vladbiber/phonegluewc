import QtQuick

// the flash and the short message of a hardware button; takes no input
Item {
    Rectangle {
        anchors.fill: parent
        color: Phone.white
        opacity: Phone.flashOn ? 0.7 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
    Rectangle {
        // above where the keyboard opens
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 56 }
        width: Math.min(message.implicitWidth + 40, parent.width - 40)
        height: message.implicitHeight + 28
        radius: 20
        color: Phone.surface
        visible: Phone.toastText !== ""

        Text {
            id: message
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.parent.width - 80)
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            color: Phone.white
            font.family: Phone.font
            font.pixelSize: 15
            text: Phone.toastText
        }
    }
}
