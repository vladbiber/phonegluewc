import QtQuick

// a pill: light when on, dark grey when off; the owner handles the finger
Rectangle {
    id: root

    property string icon: ""
    property int level: 0
    property string label: ""
    property string sub: ""
    property bool on: false
    property bool chevron: false
    readonly property color ink: on ? Phone.mix("#141414", "#ffffff") : Phone.fg

    height: 64
    radius: 32
    color: on ? Phone.mix("#ececec", "#141414") : Phone.mix("#262626", "#ffffff")
    Behavior on color { ColorAnimation { duration: 140 } }

    Icon {
        x: 18
        anchors.verticalCenter: parent.verticalCenter
        name: root.icon
        level: root.level
        color: root.ink
        size: 22
    }
    Column {
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 50; rightMargin: root.chevron ? 28 : 14 }
        Text {
            width: parent.width
            text: root.label
            elide: Text.ElideRight
            color: root.ink
            font.family: Phone.font
            font.pixelSize: 14
            font.weight: Font.Medium
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: root.sub
            elide: Text.ElideRight
            color: root.ink
            opacity: 0.7
            font.family: Phone.font
            font.pixelSize: 12
        }
    }
    Icon {
        visible: root.chevron
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        name: "chevron"
        rotation: -90
        color: root.ink
        opacity: 0.6
        size: 14
    }
}
