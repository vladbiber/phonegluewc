import QtQuick

Rectangle {
    id: root
    color: S.black
    readonly property var shown: {
        const q = field.text.trim().toLowerCase();
        return q === "" ? S.pages.filter(p => !p.parent) : S.pages.filter(p => (p.label + " " + p.sub + " " + p.keys).toLowerCase().includes(q));
    }

    Item {
        id: head
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 56
        BackBtn { id: backBtn }
        DotText {
            anchors { left: backBtn.right; verticalCenter: parent.verticalCenter }
            text: "SETTINGS"
        }
    }
    Rectangle {
        id: bar
        anchors { top: head.bottom; topMargin: 4; left: parent.left; right: parent.right; leftMargin: S.margin; rightMargin: S.margin }
        height: 52
        radius: 26
        color: S.surface
        TextInput {
            id: field
            anchors { fill: parent; leftMargin: 22; rightMargin: 22 }
            verticalAlignment: TextInput.AlignVCenter
            color: S.white
            selectionColor: S.accent
            font.family: S.font
            font.pixelSize: 17
            inputMethodHints: Qt.ImhNoPredictiveText
            Keys.onEscapePressed: S.back()
            Keys.onReturnPressed: if (root.shown.length > 0) S.open(root.shown[0].id)
            T {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: field.text === ""
                text: "Search settings"
                color: S.grey
                wrapMode: Text.NoWrap
            }
        }
    }
    ListView {
        id: list
        anchors { top: bar.bottom; topMargin: 10; bottom: parent.bottom; bottomMargin: 20; left: parent.left; right: parent.right }
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.shown
        delegate: RowItem {
            required property var modelData
            width: list.width
            label: modelData.label
            sub: modelData.sub
            icon: modelData.icon
            chevron: true
            onTapped: S.open(modelData.id)
        }
    }
    T {
        anchors { top: bar.bottom; topMargin: 32; left: parent.left; right: parent.right; leftMargin: S.margin + 8; rightMargin: S.margin }
        visible: root.shown.length === 0
        text: "No settings match “" + field.text.trim() + "”"
        color: S.grey
    }
}
