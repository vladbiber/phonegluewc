import QtQuick

// an incoming Android call over the lock screen: who, which app, and the two answers; Accept still asks for the PIN
Rectangle {
    color: "#e6000000"
    // touches stop here, the lock view under it waits
    MouseArea { anchors.fill: parent }
    Column {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.16 }
        spacing: 14
        AppIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            entry: ({ name: Droid.call ? Droid.call.app : "?", icon: Droid.call ? Droid.call.icon : "" })
            size: 72
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Droid.call ? Droid.call.app + " call" : ""
            color: "#a1a1a6"
            font.family: Phone.font
            font.pixelSize: 17
        }
        Text {
            width: parent.parent.width - 48
            horizontalAlignment: Text.AlignHCenter
            text: Droid.call ? Droid.call.who : ""
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: "#ffffff"
            font.family: Phone.font
            font.pixelSize: 34
        }
    }
    Row {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: parent.height * 0.12 }
        spacing: parent.width * 0.36
        CallButton { size: 76; onTapped: Droid.decline() }
        CallButton { size: 76; accept: true; onTapped: Droid.answer() }
    }
}
