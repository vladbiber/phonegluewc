import Quickshell
import Quickshell.Io
import QtQuick

// the lock's own editor over its wallpaper: swipe for a clock style, tap the clock for a colour; Done saves, Cancel forgets
Item {
    id: root

    signal closed()
    readonly property var styles: [["dot", "Dot matrix"], ["thin", "Thin"], ["bold", "Bold"], ["small", "Small"], ["stacked", "Stacked"]]
    property string tint: Phone.conf.lock_clock_color || "auto"
    property bool colours: false
    property bool picking: false
    // a picked wallpaper waits here until Done
    property string wall: Auth.config.wallpaper || ""
    readonly property string style: styles[Math.max(0, pages.currentIndex)][0]
    // widgets save as they are moved, so Cancel puts back what was there when the editor opened
    property string widgetsWere: ""
    Component.onCompleted: widgetsWere = JSON.stringify(Screens.screenOf("lock", -1).widgets)
    property bool placing: false
    function cancel() {
        if (JSON.stringify(Screens.screenOf("lock", -1).widgets) !== widgetsWere)
            Screens.setWidgets("lock", Screens.active("lock"), JSON.parse(widgetsWere));
        closed();
    }

    function save() {
        // one after the other: two writers at once would each rename over the other
        Quickshell.execDetached(["sh", "-c", '"$0" set phone lock_clock "$1" && "$0" set phone lock_clock_color "$2"',
            Quickshell.shellDir + "/../settings/pset", style, tint]);
        if (wall !== (Auth.config.wallpaper || ""))
            Screens.setWallpaper("lock", Screens.active("lock"), wall);
        closed();
    }

    LockWallpaper { anchors.fill: parent; path: root.wall }

    // a touch anywhere outside a button keeps the clock pages swipeable
    ListView {
        id: pages
        anchors.fill: parent
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        highlightMoveDuration: Dyn.anim ? 240 : 0
        boundsBehavior: Flickable.StopAtBounds
        model: root.styles
        currentIndex: Math.max(0, root.styles.findIndex(s => s[0] === (Phone.conf.lock_clock || "dot")))
        Component.onCompleted: positionViewAtIndex(currentIndex, ListView.Beginning)
        delegate: Item {
            id: page
            required property var modelData
            readonly property color wall: face.wallColor
            readonly property bool wallDistinct: face.wallDistinct
            width: pages.width
            height: pages.height
            LockClock {
                id: face
                anchors.fill: parent
                style: page.modelData[0]
                tint: root.tint
                wallpaper: root.wall
                // above the style's name at 400
                room: 392
            }
            ScreenWidgets {
                anchors.fill: parent
                lock: true
                preview: true
                clockStyle: page.modelData[0]
                room: 392
            }
            // the clock area: a tap shows the colours
            MouseArea {
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 64 }
                height: 300
                onClicked: root.colours = !root.colours
            }
        }
    }

    component Pill: Rectangle {
        id: pill
        property string label: ""
        property bool strong: false
        signal tapped()
        width: text.implicitWidth + 36
        height: 38
        radius: 19
        color: strong ? Phone.white : Qt.rgba(0, 0, 0, 0.45)
        Text {
            id: text
            anchors.centerIn: parent
            text: pill.label
            color: pill.strong ? Phone.black : Phone.white
            font.family: Phone.font
            font.pixelSize: 15
            font.weight: Font.Medium
        }
        MouseArea { anchors.fill: parent; onClicked: pill.tapped() }
    }

    Pill {
        anchors { left: parent.left; leftMargin: 16; top: parent.top; topMargin: Status.barHeight - 4 }
        label: "Cancel"
        onTapped: root.cancel()
    }
    Pill {
        anchors { right: parent.right; rightMargin: 16; top: parent.top; topMargin: Status.barHeight - 4 }
        label: "Done"
        strong: true
        onTapped: root.save()
    }

    // the style's name and where it is among them
    Column {
        anchors { top: parent.top; topMargin: 400; horizontalCenter: parent.horizontalCenter }
        spacing: 10
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.styles[Math.max(0, pages.currentIndex)][1]
            color: Phone.white
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.4)
            font.family: Phone.font
            font.pixelSize: 16
            font.weight: Font.Medium
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Repeater {
                model: root.styles.length
                delegate: Rectangle {
                    required property int index
                    width: 7
                    height: 7
                    radius: 3.5
                    color: index === pages.currentIndex ? Phone.white : Qt.rgba(1, 1, 1, 0.4)
                }
            }
        }
    }

    // auto (half white, half dark), white, the accent, and a colour from the wallpaper when it has one
    Gradient {
        id: half
        orientation: Gradient.Horizontal
        GradientStop { position: 0.5; color: Phone.white }
        GradientStop { position: 0.5001; color: "#141414" }
    }
    Rectangle {
        anchors { top: parent.top; topMargin: 470; horizontalCenter: parent.horizontalCenter }
        visible: root.colours
        width: swatches.width + 24
        height: 64
        radius: 32
        color: Qt.rgba(0, 0, 0, 0.45)
        Row {
            id: swatches
            anchors.centerIn: parent
            spacing: 14
            Repeater {
                model: [["auto", Phone.white], ["white", Phone.white], ["accent", Phone.accentSaved]].concat(
                    pages.currentItem && pages.currentItem.wallDistinct ? [["wallpaper", pages.currentItem.wall]] : [])
                delegate: Rectangle {
                    required property var modelData
                    width: 44
                    height: 44
                    radius: 22
                    color: modelData[1]
                    gradient: modelData[0] === "auto" ? half : null
                    border.width: root.tint === modelData[0] ? 3 : 0
                    border.color: Phone.white
                    Rectangle {
                        anchors { fill: parent; margins: 3 }
                        radius: width / 2
                        color: "transparent"
                        visible: root.tint === parent.modelData[0]
                        border.width: 2
                        border.color: Phone.black
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.tint = parent.modelData[0] }
                }
            }
        }
    }

    Row {
        anchors { bottom: parent.bottom; bottomMargin: 48; horizontalCenter: parent.horizontalCenter }
        spacing: 10
        Pill {
            label: "Wallpaper"
            onTapped: root.picking = true
        }
        Pill {
            label: "Widgets"
            onTapped: root.placing = true
        }
    }

    // the home editor's widget page, on the lock's own screen
    Loader {
        anchors.fill: parent
        active: root.placing
        sourceComponent: ScreenEditor {
            lock: true
            mode: "widgets"
            onModeChanged: if (mode !== "widgets") root.placing = false
            onClosed: root.placing = false
        }
    }

    // the pictures pset finds, as in the home editor; a tap only sets the pending one
    Loader {
        anchors.fill: parent
        active: root.picking
        sourceComponent: Rectangle {
            id: pick
            property var images: []
            color: Phone.black
            MouseArea { anchors.fill: parent }
            Process {
                running: true
                command: [Quickshell.shellDir + "/../settings/pset", "images"]
                stdout: StdioCollector { onStreamFinished: pick.images = text.split("\n").filter(l => l) }
            }
            Pill {
                anchors { left: parent.left; leftMargin: 16; top: parent.top; topMargin: Status.barHeight - 4 }
                label: "Back"
                onTapped: root.picking = false
            }
            GridView {
                anchors { fill: parent; topMargin: Status.barHeight + 48; margins: 12 }
                clip: true
                cellWidth: width / 3
                cellHeight: cellWidth * root.height / root.width
                model: [""].concat(pick.images)
                delegate: Item {
                    required property string modelData
                    width: GridView.view.cellWidth
                    height: GridView.view.cellHeight
                    Rectangle {
                        anchors { fill: parent; margins: 4 }
                        radius: 14
                        clip: true
                        color: "#171717"
                        border.color: root.wall === parent.modelData ? Phone.accentSaved : "#2a2a2a"
                        border.width: 2
                        Text {
                            anchors.centerIn: parent
                            visible: parent.parent.modelData === ""
                            text: "None"
                            color: Phone.grey
                            font.family: Phone.font
                            font.pixelSize: 14
                        }
                        Image {
                            anchors { fill: parent; margins: 2 }
                            visible: parent.parent.modelData !== ""
                            source: parent.parent.modelData ? "file://" + parent.parent.modelData : ""
                            sourceSize: Qt.size(width, height)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.wall = parent.modelData; root.picking = false; }
                    }
                }
            }
        }
    }
}
