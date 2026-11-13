import QtQuick

// label, optional line under it, and whatever sits on the right; the whole row is one touch target
Item {
    id: root
    property string label: ""
    property string sub: ""
    property string icon: ""
    property bool active: false
    property bool chevron: false
    property bool tappable: true
    default property alias control: slot.data
    signal tapped()

    width: parent ? parent.width : 0
    height: Math.max(64, col.implicitHeight + 24)

    Rectangle {
        anchors.fill: parent
        color: tap.pressed && root.tappable ? S.surface : "transparent"
    }
    Rectangle {
        id: disc
        visible: root.icon !== ""
        x: S.margin
        anchors.verticalCenter: parent.verticalCenter
        width: 44; height: 44; radius: 22
        color: S.surface
        DotIcon {
            anchors.centerIn: parent
            name: root.icon
            px: 2.2; gap: 0.9
            color: root.active ? S.accent : S.white
        }
    }
    Column {
        id: col
        anchors { left: root.icon !== "" ? disc.right : parent.left; leftMargin: root.icon !== "" ? 14 : S.margin
                  right: slot.left; rightMargin: slot.width > 0 ? 12 : 0; verticalCenter: parent.verticalCenter }
        spacing: 2
        T { width: parent.width; text: root.label; color: root.active ? S.accent : S.white; wrapMode: Text.NoWrap; elide: Text.ElideRight }
        T { width: parent.width; visible: text !== ""; text: root.sub; color: S.grey; font.pixelSize: 13 }
    }
    Item {
        id: slot
        anchors { right: parent.right; rightMargin: root.chevron ? 18 : S.margin; verticalCenter: parent.verticalCenter }
        width: childrenRect.width
        height: childrenRect.height
        z: 1
    }
    Repeater {
        model: root.chevron ? [45, -45] : []
        delegate: Rectangle {
            required property int modelData
            anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter; verticalCenterOffset: modelData > 0 ? -3.5 : 3.5 }
            width: 10; height: 2; radius: 1
            rotation: modelData
            color: S.grey
        }
    }
    MouseArea {
        id: tap
        anchors.fill: parent
        enabled: root.tappable
        onClicked: root.tapped()
    }
}
