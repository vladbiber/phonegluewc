import QtQuick

// a pill whose dot slides over and turns accent when on; the row around it takes the tap
Rectangle {
    id: root
    property bool on: false
    property bool enabled_: true
    width: 54; height: 30; radius: 15
    color: S.black
    border.width: 1.5
    border.color: on ? S.accent : S.edge
    opacity: enabled_ ? 1 : 0.4
    Rectangle {
        width: 18; height: 18; radius: 9
        y: 6
        x: root.on ? root.width - width - 6 : 6
        color: root.on ? S.accent : S.grey
        Behavior on x { NumberAnimation { duration: 120 } }
    }
}
