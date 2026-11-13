import Quickshell
import QtQuick
import "widgets"

// the add-widget sheet: search, a look for all previews, every widget live in each size; a tap adds it, a hold drags it out
Item {
    id: root

    property bool lock: false
    // the look of what gets added; picking one here also makes it the default
    property string look: Screens.widgetStyle
    property string query: ""
    signal picked(var w)
    signal dropped(var w, real x, real y)
    signal closed()

    readonly property real cellW: (width - 2 * Screens.pad) / Screens.cols
    readonly property real k: 0.78
    readonly property var catalog: [
        { group: "Clock", items: [
            { type: "clock", name: "Clock", sizes: [[2, 2], [2, 4], [4, 2]] },
            { type: "analog", name: "Analog clock" },
            { type: "world", name: "World clock" },
            { type: "date", name: "Date", sizes: [[2, 4], [1, 2], [4, 1]] }] },
        { group: "Device", items: [
            { type: "battery", name: "Battery", sizes: [[1, 2], [2, 2], [2, 1]] },
            { type: "storage", name: "Storage" }] },
        { group: "Controls", items: [
            { type: "wifi", name: "Wi-Fi" },
            { type: "bluetooth", name: "Bluetooth" },
            { type: "torch", name: "Torch" },
            { type: "airplane", name: "Airplane mode" },
            { type: "rotate", name: "Auto-rotate" },
            { type: "dark", name: "Dark mode" }] },
        { group: "Tools", items: [
            { type: "weather", name: "Weather" },
            { type: "timer", name: "Timer" },
            { type: "stopwatch", name: "Stopwatch" }] },
        { group: "Personal", items: [
            { type: "music", name: "Music" },
            { type: "note", name: "Short note" },
            { type: "photo", name: "Photo" }] }
    ]
    // what this screen may hold, narrowed by the search
    readonly property var shown: {
        const q = query.trim().toLowerCase();
        const out = [];
        for (const g of catalog) {
            const items = g.items.filter(i => (!lock || Screens.lockTypes.includes(i.type))
                && (q === "" || i.name.toLowerCase().includes(q) || g.group.toLowerCase().includes(q)));
            if (items.length)
                out.push({ group: g.group, items: items });
        }
        if (!lock) {
            const apps = Phone.apps.filter(e => q === "" || String(e.name).toLowerCase().includes(q) || "apps".includes(q));
            if (apps.length)
                out.push({ group: "Apps", apps: apps });
        }
        return out;
    }
    function sizesOf(item) { return item.sizes || Screens.sizes[item.type]; }
    function make(item, s) { return { type: item.type, w: s[0], h: s[1], style: look }; }

    // a held preview follows the finger out of the sheet
    property var dragW: null
    function startDrag(w, area, mx, my) {
        dragW = w;
        moveDrag(area, mx, my);
    }
    function moveDrag(area, mx, my) {
        const p = area.mapToItem(root, mx, my);
        ghost.x = p.x - ghost.width / 2;
        ghost.y = p.y - ghost.height / 2;
    }
    function endDrag() {
        const w = dragW;
        dragW = null;
        if (w)
            dropped(w, ghost.x, ghost.y);
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, root.dragW ? 0 : 0.4)
        MouseArea { anchors.fill: parent; onClicked: root.closed() }
    }

    Rectangle {
        id: sheet
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: -28 }
        height: parent.height * 0.74 + 28
        radius: 28
        color: Phone.mix("#161616", "#f2f2f7")
        opacity: root.dragW ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 120 } }
        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 8 }
            width: 36
            height: 5
            radius: 2.5
            color: Phone.mix("#444444", "#c7c7cc")
        }
        Text {
            x: 20
            y: 22
            text: "Add widgets"
            color: Phone.fg
            font.family: Phone.font
            font.pixelSize: 20
            font.weight: Font.Bold
        }
        Rectangle {
            anchors { right: parent.right; rightMargin: 16; top: parent.top; topMargin: 20 }
            width: 32
            height: 32
            radius: 16
            color: Phone.mix("#2c2c2c", "#e3e3e8")
            Icon {
                anchors.centerIn: parent
                name: "plus"
                rotation: 45
                color: Phone.dim
                size: 18
            }
            MouseArea { anchors { fill: parent; margins: -8 } onClicked: root.closed() }
        }
        Rectangle {
            id: search
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16; topMargin: 64 }
            height: 40
            radius: 12
            color: Phone.mix("#262626", "#e3e3e8")
            Icon {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                name: "search"
                color: Phone.dim
                size: 18
            }
            TextInput {
                id: field
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 38; rightMargin: 12 }
                color: Phone.fg
                selectionColor: Phone.accent
                font.family: Phone.font
                font.pixelSize: 15
                clip: true
                onTextChanged: root.query = text
                Text {
                    visible: !parent.text && !parent.activeFocus
                    text: "Search widgets"
                    color: Phone.dim
                    font: parent.font
                }
            }
        }
        Row {
            id: looks
            anchors { left: parent.left; leftMargin: 16; top: search.bottom; topMargin: 10 }
            spacing: 8
            Repeater {
                model: Screens.styles
                delegate: Rectangle {
                    required property string modelData
                    readonly property bool on: root.look === modelData
                    width: chip.implicitWidth + 28
                    height: 32
                    radius: 16
                    color: on ? Phone.fg : Phone.mix("#262626", "#e3e3e8")
                    Text {
                        id: chip
                        anchors.centerIn: parent
                        text: ({ "nothing-dark": "Nothing dark", "nothing-light": "Nothing light", "apple": "Apple" })[parent.modelData]
                        color: parent.on ? Phone.bg : Phone.fg
                        font.family: Phone.font
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { root.look = parent.modelData; Screens.setWidgetStyle(parent.modelData); }
                    }
                }
            }
        }

        Flickable {
            id: list
            anchors { left: parent.left; right: parent.right; top: looks.bottom; bottom: parent.bottom; topMargin: 8; bottomMargin: 28 }
            clip: true
            contentHeight: groups.height + 24
            boundsBehavior: Flickable.StopAtBounds
            interactive: !root.dragW
            Column {
                id: groups
                x: 16
                width: list.width - 32
                spacing: 6
                Repeater {
                    model: root.shown
                    delegate: Column {
                        id: grp
                        required property var modelData
                        width: groups.width
                        spacing: 6
                        Text {
                            topPadding: 10
                            text: grp.modelData.group
                            color: Phone.dim
                            font.family: Phone.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                        }
                        Repeater {
                            model: grp.modelData.items || []
                            delegate: Column {
                                id: it
                                required property var modelData
                                width: groups.width
                                spacing: 4
                                Text {
                                    text: it.modelData.name
                                    color: Phone.fg
                                    font.family: Phone.font
                                    font.pixelSize: 14
                                }
                                Flow {
                                    width: parent.width
                                    spacing: 8
                                    Repeater {
                                        model: root.sizesOf(it.modelData)
                                        delegate: Item {
                                            id: pv
                                            required property var modelData
                                            readonly property var w: root.make(it.modelData, modelData)
                                            width: w.w * root.cellW * root.k
                                            height: w.h * Screens.rowH * root.k
                                            Item {
                                                width: pv.w.w * root.cellW
                                                height: pv.w.h * Screens.rowH
                                                scale: root.k
                                                transformOrigin: Item.TopLeft
                                                // the bare clock and date of the home draw on the wallpaper; here on a dark plate
                                                Rectangle {
                                                    anchors.fill: parent
                                                    visible: Screens.bare(pv.w)
                                                    radius: 14
                                                    color: "#202020"
                                                    DotClock {
                                                        visible: pv.w.type === "clock"
                                                        anchors.centerIn: parent
                                                        pitch: Math.floor(Math.min(parent.width / 27, parent.height / 8))
                                                        time: Qt.formatTime(new Date(), "HH:mm")
                                                    }
                                                    Text {
                                                        visible: pv.w.type === "date"
                                                        anchors.centerIn: parent
                                                        text: Qt.formatDate(new Date(), "dddd, d MMMM")
                                                        color: Phone.white
                                                        font.family: Phone.font
                                                        font.pixelSize: 17
                                                    }
                                                }
                                                Widget {
                                                    anchors.fill: parent
                                                    visible: !Screens.bare(pv.w)
                                                    w: pv.w
                                                    lock: root.lock
                                                    preview: true
                                                }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: root.picked(pv.w)
                                                onPressAndHold: mouse => { preventStealing = true; root.startDrag(pv.w, this, mouse.x, mouse.y); }
                                                onPositionChanged: mouse => { if (root.dragW) root.moveDrag(this, mouse.x, mouse.y); }
                                                onReleased: { preventStealing = false; root.endDrag(); }
                                                onCanceled: { preventStealing = false; root.dragW = null; }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        // apps: one cell each, as on the home
                        Flow {
                            visible: !!grp.modelData.apps
                            width: parent.width
                            spacing: 4
                            Repeater {
                                model: grp.modelData.apps || []
                                delegate: Item {
                                    id: ap
                                    required property var modelData
                                    width: 76
                                    height: 84
                                    AppIcon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: 4
                                        entry: ap.modelData
                                        size: 48
                                    }
                                    Text {
                                        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                                        width: parent.width - 4
                                        horizontalAlignment: Text.AlignHCenter
                                        text: ap.modelData.name
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        color: Phone.fg
                                        font.family: Phone.font
                                        font.pixelSize: 11
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: root.picked({ type: "app", w: 1, h: 2, app: ap.modelData.id })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        Text {
            anchors.centerIn: list
            visible: root.shown.length === 0
            text: "No widget matches"
            color: Phone.dim
            font.family: Phone.font
            font.pixelSize: 14
        }
    }

    Widget {
        id: ghost
        visible: root.dragW !== null
        w: root.dragW || ({})
        width: root.dragW ? root.dragW.w * root.cellW : 0
        height: root.dragW ? root.dragW.h * Screens.rowH : 0
        lock: root.lock
        preview: true
        opacity: 0.85
    }
}
