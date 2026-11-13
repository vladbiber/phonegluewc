import Quickshell
import Quickshell.Io
import QtQuick
import qs

// one widget's settings as a bottom sheet: its look, and the city, offset, length or picture its type takes
Item {
    id: root

    property var w: ({})
    // the widget with the change in it, to save
    signal changed(var w)
    signal closed()

    function set(k, v) { const n = Object.assign({}, w); n[k] = v; changed(n); }
    function offsetText(m) { return "GMT" + (m < 0 ? "-" : "+") + Math.floor(Math.abs(m) / 60) + (Math.abs(m) % 60 ? ":" + Math.abs(m) % 60 : ""); }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        MouseArea { anchors.fill: parent; onClicked: root.closed() }
    }

    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool on: false
        signal tapped()
        width: t.implicitWidth + 28
        height: 36
        radius: 18
        color: on ? Phone.fg : Phone.mix("#262626", "#e3e3e8")
        Text {
            id: t
            anchors.centerIn: parent
            text: chip.label
            color: chip.on ? Phone.bg : Phone.fg
            font.family: Phone.font
            font.pixelSize: 14
            font.weight: Font.Medium
        }
        MouseArea { anchors { fill: parent; margins: -4 } onClicked: chip.tapped() }
    }
    component Heading: Text {
        color: Phone.dim
        font.family: Phone.font
        font.pixelSize: 13
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
    }
    // a value with a minus and a plus beside it
    component Stepper: Row {
        id: st
        property string text: ""
        signal step(int by)
        spacing: 12
        Chip { label: "−"; onTapped: st.step(-1) }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 110
            horizontalAlignment: Text.AlignHCenter
            text: st.text
            color: Phone.fg
            font.family: Phone.font
            font.pixelSize: 17
            font.weight: Font.Medium
        }
        Chip { label: "+"; onTapped: st.step(1) }
    }

    Rectangle {
        id: sheet
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: -28 }
        height: (root.w.type === "photo" ? parent.height * 0.7 : body.height + 96) + 28
        radius: 28
        color: Phone.mix("#161616", "#f2f2f7")
        MouseArea { anchors.fill: parent }

        Text {
            x: 20
            y: 22
            text: "Widget settings"
            color: Phone.fg
            font.family: Phone.font
            font.pixelSize: 20
            font.weight: Font.Bold
        }
        Chip {
            anchors { right: parent.right; rightMargin: 16; top: parent.top; topMargin: 18 }
            label: "Done"
            on: true
            onTapped: root.closed()
        }

        Column {
            id: body
            x: 20
            y: 70
            width: parent.width - 40
            spacing: 10

            Heading { text: "Look" }
            Row {
                spacing: 8
                Repeater {
                    model: Screens.styles
                    delegate: Chip {
                        required property string modelData
                        label: ({ "nothing-dark": "Nothing dark", "nothing-light": "Nothing light", "apple": "Apple" })[modelData]
                        on: Screens.styleOf(root.w) === modelData
                        onTapped: root.set("style", modelData)
                    }
                }
            }

            Heading { visible: root.w.type === "weather"; topPadding: 8; text: "City" }
            Rectangle {
                visible: root.w.type === "weather"
                width: parent.width
                height: 44
                radius: 12
                color: Phone.mix("#262626", "#e3e3e8")
                TextInput {
                    id: city
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.w.city || ""
                    maximumLength: 60
                    color: Phone.fg
                    selectionColor: Phone.accent
                    font.family: Phone.font
                    font.pixelSize: 16
                    clip: true
                    onEditingFinished: if (text.trim() !== (root.w.city || "")) root.set("city", text.trim())
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !parent.text && !parent.activeFocus
                        text: "Type a city, e.g. Iasi"
                        color: Phone.dim
                        font: parent.font
                    }
                }
            }

            Heading { visible: root.w.type === "world"; topPadding: 8; text: "Time zone" }
            Stepper {
                visible: root.w.type === "world"
                text: root.offsetText(root.w.offset | 0)
                onStep: by => root.set("offset", Math.max(-720, Math.min(840, (root.w.offset | 0) + by * 30)))
            }

            Heading { visible: root.w.type === "timer"; topPadding: 8; text: "Length" }
            Stepper {
                visible: root.w.type === "timer"
                readonly property int m: root.w.minutes || 5
                text: m + " min"
                // one minute at a time up to ten, then five
                onStep: by => root.set("minutes", Math.max(1, Math.min(600, m + by * ((by > 0 ? m >= 10 : m > 10) ? 5 : 1))))
            }

            Heading { visible: root.w.type === "photo"; topPadding: 8; text: "Picture" }
        }

        // the pictures pset finds, as in the wallpaper picker
        GridView {
            id: grid
            visible: root.w.type === "photo"
            anchors { left: parent.left; right: parent.right; top: body.bottom; bottom: parent.bottom; margins: 16; topMargin: 8; bottomMargin: 44 }
            clip: true
            cellWidth: width / 3
            cellHeight: cellWidth
            property var images: []
            model: images
            Process {
                running: root.w.type === "photo"
                command: [Quickshell.shellDir + "/../settings/pset", "images"]
                stdout: StdioCollector { onStreamFinished: grid.images = text.split("\n").filter(l => l) }
            }
            delegate: Item {
                required property string modelData
                width: GridView.view.cellWidth
                height: GridView.view.cellHeight
                Rectangle {
                    anchors { fill: parent; margins: 4 }
                    radius: 14
                    color: "#171717"
                    border.color: root.w.file === parent.modelData ? Phone.accent : "transparent"
                    border.width: 3
                    Image {
                        anchors { fill: parent; margins: 3 }
                        source: "file://" + parent.parent.modelData
                        sourceSize: Qt.size(width, height)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: root.set("file", parent.modelData) }
            }
            Text {
                anchors.centerIn: parent
                visible: grid.images.length === 0
                text: "No pictures found"
                color: Phone.dim
                font.family: Phone.font
                font.pixelSize: 14
            }
        }
    }
}
