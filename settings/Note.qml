import QtQuick

// an explanation, or why something cannot be done here; the accent marks it as a problem
Item {
    id: root
    property string text: ""
    property bool problem: false
    width: parent.width
    height: visible ? box.height + 16 : 0
    visible: text !== ""
    // the log says what the person was told, for bug reports and the tests
    property bool built: false
    function say() { if (built && visible && text !== "") console.info("note:", text); }
    onVisibleChanged: say()
    onTextChanged: say()
    // bindings settle while the page is built, nothing has been drawn before this
    Component.onCompleted: { built = true; say(); }
    Rectangle {
        id: box
        x: S.margin
        y: 8
        width: parent.width - 2 * S.margin
        height: label.implicitHeight + 28
        radius: 18
        color: S.surface
        Rectangle {
            visible: root.problem
            x: 16; y: 21
            width: 8; height: 8; radius: 4
            color: S.accent
        }
        T {
            id: label
            x: root.problem ? 34 : 16
            y: 14
            width: parent.width - x - 16
            text: root.text
            font.pixelSize: 15
        }
    }
}
