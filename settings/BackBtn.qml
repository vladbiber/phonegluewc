import QtQuick

Item {
    width: 64; height: 56
    Rectangle { x: 22; y: 27; width: 22; height: 2; radius: 1; color: S.white }
    Rectangle { x: 22; y: 27; width: 12; height: 2; radius: 1; color: S.white; transformOrigin: Item.Left; rotation: 42 }
    Rectangle { x: 22; y: 27; width: 12; height: 2; radius: 1; color: S.white; transformOrigin: Item.Left; rotation: -42 }
    MouseArea { anchors.fill: parent; onClicked: S.back() }
}
