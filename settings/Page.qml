import QtQuick

// back arrow and title on top, the page scrolling under them, any save failure on show
Rectangle {
    id: root
    property string title: S.titleOf(S.page)
    default property alias content: col.data
    property alias overlay: over.data
    color: S.black

    Item {
        id: head
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 56
        BackBtn { id: backBtn }
        DotText {
            anchors { left: backBtn.right; verticalCenter: parent.verticalCenter }
            text: root.title.toUpperCase()
        }
    }
    Flickable {
        anchors { top: head.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; bottomMargin: 20 }
        contentHeight: col.implicitHeight + 16
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Column {
            id: col
            width: parent.width
            Note { text: S.saveError; problem: true }
        }
    }
    Item { id: over; anchors.fill: parent }
}
