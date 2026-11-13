import QtQuick

// one choice out of a few, wrapping onto more lines on a narrow screen
Flow {
    id: root
    property var options: []    // { value, label }
    property var current
    signal picked(var value)
    x: S.margin
    width: parent.width - 2 * S.margin
    spacing: 8
    Repeater {
        model: root.options
        delegate: Rectangle {
            required property var modelData
            readonly property bool sel: root.current === modelData.value
            width: chip.implicitWidth + 32
            height: 44
            radius: 22
            color: sel ? S.accent : S.surface
            T {
                id: chip
                anchors.centerIn: parent
                text: parent.modelData.label
                color: parent.sel ? S.inkOnAccent : S.white
                font.pixelSize: 15
                wrapMode: Text.NoWrap
            }
            MouseArea { anchors.fill: parent; onClicked: root.picked(parent.modelData.value) }
        }
    }
}
