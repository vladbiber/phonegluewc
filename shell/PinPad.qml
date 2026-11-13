import QtQuick

// dots for the digits typed, a number pad, delete and OK; it never shows the digits themselves
Item {
    id: root

    signal unlocked()
    signal usePassword()
    property string digits: ""
    readonly property bool waiting: Pin.wait > 0
    readonly property real key: Math.min(76, (width - 48) / 3)

    width: parent ? parent.width : 0
    height: col.implicitHeight

    // a hardware keyboard types on it too
    focus: visible
    onVisibleChanged: if (visible) forceActiveFocus()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Backspace)
            press("del");
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            press("ok");
        else if (/^[0-9]$/.test(event.text))
            press(event.text);
        else
            return;
        event.accepted = true;
    }

    function press(k) {
        forceActiveFocus();
        if (waiting || Pin.busy)
            return;
        note.wrong = false;
        if (k === "del")
            digits = digits.slice(0, -1);
        else if (k === "ok") {
            if (digits.length >= 4)
                Pin.submit(digits);
            digits = "";
        } else if (digits.length < 6)
            digits += k;
    }

    Connections {
        target: Pin
        function onAnswered(ok) {
            if (!root.visible)
                return;
            if (ok)
                root.unlocked();
            else {
                note.wrong = true;
                shake.restart();
            }
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 14

        Text {
            id: note
            property bool wrong: false
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.waiting ? "Too many tries. Wait " + Pin.wait + " s" : wrong ? "Wrong PIN" : "Enter PIN"
            color: root.waiting || wrong ? Phone.accent : Phone.white
            font.family: Phone.font
            font.pixelSize: 17
        }
        Item {
            id: dots
            width: parent.width
            height: 16
            Row {
                id: dotRow
                x: (parent.width - width) / 2
                spacing: 14
                Repeater {
                    model: root.digits.length
                    delegate: Rectangle { width: 12; height: 12; radius: 6; color: Phone.white }
                }
            }
            SequentialAnimation {
                id: shake
                NumberAnimation { target: col; property: "x"; to: 12; duration: 50 }
                NumberAnimation { target: col; property: "x"; to: -10; duration: 70 }
                NumberAnimation { target: col; property: "x"; to: 10; duration: 70 }
                NumberAnimation { target: col; property: "x"; to: 0; duration: 50 }
            }
        }
        Grid {
            anchors.horizontalCenter: parent.horizontalCenter
            columns: 3
            columnSpacing: 20
            rowSpacing: 6
            opacity: root.waiting ? 0.4 : 1
            Repeater {
                model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "del", "0", "ok"]
                delegate: Item {
                    id: k
                    required property string modelData
                    width: root.key
                    height: root.key * 0.86
                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height)
                        height: width
                        radius: width / 2
                        color: Phone.white
                        opacity: area.pressed ? 0.18 : 0
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: k.modelData !== "del"
                        text: k.modelData === "ok" ? "OK" : k.modelData
                        color: k.modelData === "ok" && root.digits.length < 4 ? Phone.grey : Phone.white
                        font.family: Phone.font
                        font.pixelSize: k.modelData === "ok" ? 20 : 30
                    }
                    Icon {
                        anchors.centerIn: parent
                        visible: k.modelData === "del"
                        name: "backspace"
                        size: 26
                        color: Phone.white
                    }
                    MouseArea { id: area; anchors.fill: parent; onClicked: root.press(k.modelData) }
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Use password"
            color: Phone.white
            font.family: Phone.font
            font.pixelSize: 15
            font.underline: true
            MouseArea {
                anchors.fill: parent
                anchors.margins: -12
                onClicked: { root.digits = ""; root.usePassword(); }
            }
        }
    }
}
