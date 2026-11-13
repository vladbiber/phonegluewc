import Quickshell
import Quickshell.Io
import QtQuick
import "widgets"

// the saved screens as cards; the home editor's window and the lock view both host this
Rectangle {
    id: root

    property bool lock: false
    signal closed()

    readonly property string kind: lock ? "lock" : "home"
    readonly property var screens: Screens.list(kind)
    readonly property int count: screens.length
    // a card per page; the arrows beside it pick the page's variant, the one in view is cur
    readonly property int cols: Screens.columns(kind)
    property int col: Screens.screenOf(kind, -1).x
    property var seen: ({})
    function rowIn(x) {
        const r = seen[x] !== undefined ? seen[x] : Screens.all[kind].picks[x] | 0;
        return Math.max(0, Math.min(r, Screens.variants(kind, x) - 1));
    }
    function see(x, y) { const s = Object.assign({}, seen); s[x] = y; seen = s; }
    function flat(x) { return Screens.indexAt(kind, x, rowIn(x)); }
    readonly property int cur: onPlus ? count : flat(col)
    readonly property int curY: onPlus ? 0 : rowIn(col)
    readonly property int curN: onPlus ? 0 : Screens.variants(kind, col)
    // gallery, wallpaper, widgets or tray
    property string mode: "gallery"
    property bool confirming: false
    property int noteIndex: -1
    property int wanted: col
    readonly property bool onPlus: col >= cols
    // turned, the height leaves room for the buttons and their labels under the card
    readonly property real cardW: Math.min(width * 0.62, (height - Status.barHeight - 44 - 20 - 76 - 12) * width / height)
    readonly property real cardH: cardW * height / width
    readonly property real cardScale: cardW / width

    color: Phone.bg

    // shortcut: a lock gallery left open closes after this long without a touch, a screen-off signal would close it sooner
    Timer {
        id: idle
        running: root.lock
        interval: 60000
        onTriggered: root.closed()
    }
    PointHandler { onActiveChanged: idle.restart() }

    Component.onCompleted: {
        if (Screens.noteRequest >= 0) {
            noteIndex = Screens.noteRequest;
            Screens.noteRequest = -1;
            mode = "widgets";
        }
    }

    // a tap, or a swipe up that leaves; a swipe sideways goes to the list around it
    component Swipe: MouseArea {
        property real pressY: 0
        property bool moved: false
        signal tapped()
        onPressed: mouse => { pressY = mouse.y; moved = false; }
        onPositionChanged: mouse => { if (Math.abs(mouse.y - pressY) > 10) moved = true; }
        onReleased: mouse => { if (pressY - mouse.y > 80) root.closed(); }
        onClicked: if (!moved) tapped()
    }
    component Action: Item {
        id: act
        property string icon: ""
        property string label: ""
        property bool can: true
        signal tapped()
        width: 76
        height: 76
        opacity: can ? 1 : 0.35
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 52
            height: 52
            radius: 26
            color: Phone.card
            border.color: Phone.mix("#2a2a2a", "#e2e2e2")
            scale: actTap.pressed ? 0.92 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }
            Icon {
                anchors.centerIn: parent
                name: act.icon
                color: Phone.fg
                size: 22
            }
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            text: act.label
            color: Phone.dim
            font.family: Phone.font
            font.pixelSize: 12
        }
        MouseArea {
            id: actTap
            anchors.fill: parent
            enabled: act.can
            onClicked: act.tapped()
        }
    }
    component Arrow: Rectangle {
        id: arrow
        property bool up: true
        property bool can: true
        property bool plus: false
        signal tapped()
        width: 40
        height: 40
        radius: 20
        color: Phone.card
        border.color: Phone.mix("#2a2a2a", "#e2e2e2")
        opacity: can ? 1 : 0.35
        Icon {
            anchors.centerIn: parent
            name: arrow.plus ? "plus" : "chevron"
            rotation: arrow.up && !arrow.plus ? 180 : 0
            color: Phone.fg
            size: 20
        }
        MouseArea {
            anchors.fill: parent
            enabled: arrow.can
            onClicked: arrow.tapped()
        }
    }
    component Pill: Rectangle {
        id: pill
        property string label: ""
        property bool primary: false
        signal tapped()
        width: Math.max(96, pillText.implicitWidth + 40)
        height: 48
        radius: 24
        color: primary ? Phone.accent : Phone.card
        border.color: primary ? Phone.accent : Phone.mix("#2a2a2a", "#e2e2e2")
        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.primary ? Phone.inkOnAccent : Phone.fg
            font.family: Phone.font
            font.pixelSize: 15
            font.weight: Font.Medium
        }
        MouseArea {
            anchors.fill: parent
            onClicked: pill.tapped()
        }
    }
    component Header: Item {
        id: head
        property string title: ""
        property color ink: Phone.fg
        signal back()
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Status.barHeight }
        height: 48
        Icon {
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            name: "back"
            color: head.ink
            size: 24
        }
        Text {
            x: 52
            anchors.verticalCenter: parent.verticalCenter
            text: head.title
            color: head.ink
            font.family: Phone.font
            font.pixelSize: 18
            font.weight: Font.Medium
        }
        MouseArea {
            width: 200
            height: parent.height
            onClicked: head.back()
        }
    }

    // ---- the cards ----
    Item {
        anchors.fill: parent
        visible: root.mode === "gallery"

        Swipe {
            anchors.fill: parent
            onTapped: root.closed()
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: Status.barHeight + 12 }
            text: root.onPlus ? (root.lock ? "New screen" : "New page")
                : (root.cur === Screens.active(root.kind) ? "Current · " : "")
                  + (root.lock ? "Screen " : "Page ") + (root.col + 1) + (root.curN > 1 ? " · Variant " + (root.curY + 1) + " of " + root.curN : "")
            color: Phone.dim
            font.family: Phone.font
            font.pixelSize: 14
        }
        ListView {
            id: cards
            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Status.barHeight + 44 }
            height: root.cardH
            orientation: ListView.Horizontal
            spacing: 16
            snapMode: ListView.SnapOneItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: (width - root.cardW) / 2
            preferredHighlightEnd: (width + root.cardW) / 2
            highlightMoveDuration: 200
            boundsBehavior: Flickable.StopAtBounds
            model: root.cols + 1
            // the list resets this as it likes, so it is told and never bound
            Component.onCompleted: { currentIndex = root.col; positionViewAtIndex(root.col, ListView.Center); }
            onCurrentIndexChanged: root.col = currentIndex
            onCountChanged: Qt.callLater(() => cards.currentIndex = Math.min(root.wanted, count - 1))
            delegate: Item {
                id: card
                required property int index
                readonly property bool plus: index >= root.cols
                readonly property int flat: plus ? -1 : root.flat(index)
                width: root.cardW
                height: root.cardH
                scale: index === cards.currentIndex ? 1 : 0.92
                Behavior on scale { NumberAnimation { duration: 140 } }

                Rectangle {
                    anchors.fill: parent
                    radius: 28
                    color: card.plus ? "transparent" : Phone.black

                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        visible: source != ""
                        source: {
                            const w = card.plus ? "" : Screens.wallpaperOf(root.kind, card.flat);
                            return w ? "file://" + w : "";
                        }
                        sourceSize: Qt.size(root.cardW, root.cardH)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Loader {
                        active: !card.plus
                        sourceComponent: Item {
                            width: root.width
                            height: root.height
                            scale: root.cardScale
                            transformOrigin: Item.TopLeft
                            ScreenWidgets {
                                anchors.fill: parent
                                lock: root.lock
                                preview: true
                                screenIndex: card.flat
                            }
                        }
                    }
                    Icon {
                        visible: card.plus
                        anchors.centerIn: parent
                        name: "plus"
                        color: Phone.fg
                        size: 40
                    }
                    // the picture's corners, without an effect that would cost a layer per card
                    Rectangle {
                        anchors { fill: parent; margins: -13 }
                        radius: parent.radius + 13
                        color: "transparent"
                        border.color: Phone.bg
                        border.width: 13
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: "transparent"
                        border.color: !card.plus && card.flat === Screens.active(root.kind) ? Phone.accent : Phone.mix("#333333", "#dcdcdc")
                        border.width: 2
                    }
                }
                Swipe {
                    anchors.fill: parent
                    onTapped: {
                        if (card.plus) {
                            root.wanted = root.cols;
                            Screens.add(root.kind);
                            return;
                        }
                        if (card.index !== cards.currentIndex) {
                            cards.currentIndex = card.index;
                            return;
                        }
                        Screens.activate(root.kind, card.flat);
                        root.closed();
                    }
                }
            }
        }
        // a page's variants: up and down only here, home itself swipes only sideways; past the last one adds a new one
        Column {
            visible: !root.lock && !root.onPlus
            anchors { right: parent.right; rightMargin: 4; verticalCenter: cards.verticalCenter }
            spacing: 6
            Arrow {
                up: true
                can: root.curY > 0
                onTapped: root.see(root.col, root.curY - 1)
            }
            Repeater {
                model: root.curN
                delegate: Rectangle {
                    required property int index
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 6
                    height: 6
                    radius: 3
                    color: index === root.curY ? Phone.fg : Phone.dim
                }
            }
            Arrow {
                up: false
                plus: root.curY >= root.curN - 1
                onTapped: {
                    if (plus) {
                        const x = root.col, y = root.curN;
                        Screens.add(root.kind, x);
                        root.see(x, y);
                    } else {
                        root.see(root.col, root.curY + 1);
                    }
                }
            }
        }
        Row {
            anchors { horizontalCenter: parent.horizontalCenter; top: cards.bottom; topMargin: 20 }
            visible: !root.onPlus
            Action {
                icon: "image"
                label: "Wallpaper"
                onTapped: root.mode = "wallpaper"
            }
            Action {
                icon: "pencil"
                label: "Widgets"
                onTapped: root.mode = "widgets"
            }
            Action {
                visible: !root.lock
                icon: "gear"
                label: "Settings"
                onTapped: root.mode = "settings"
            }
            Action {
                visible: !root.lock
                icon: "dock"
                label: "Tray"
                onTapped: root.mode = "tray"
            }
            Action {
                icon: "trash"
                label: "Delete"
                can: root.count > 1
                onTapped: root.confirming = true
            }
        }
    }

    // ---- the wallpaper of the card in view ----
    Loader {
        anchors.fill: parent
        active: root.mode === "wallpaper"
        sourceComponent: Item {
            id: pick
            property var images: []
            Process {
                running: true
                command: [Quickshell.shellDir + "/../settings/pset", "images"]
                stdout: StdioCollector {
                    onStreamFinished: pick.images = text.split("\n").filter(l => l)
                }
            }
            Header {
                id: wallHead
                title: "Wallpaper"
                onBack: root.mode = "gallery"
            }
            GridView {
                anchors { left: parent.left; right: parent.right; top: wallHead.bottom; bottom: parent.bottom; margins: 12; bottomMargin: 72 }
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
                        color: Phone.black
                        border.color: Screens.wallpaperOf(root.kind, root.cur) === parent.modelData ? Phone.accent : Phone.mix("#2a2a2a", "#e2e2e2")
                        border.width: 2
                        Text {
                            anchors.centerIn: parent
                            visible: parent.parent.modelData === ""
                            text: "None"
                            color: Phone.dim
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
                        onClicked: {
                            Screens.setWallpaper(root.kind, root.cur, parent.modelData);
                            root.mode = "gallery";
                        }
                    }
                }
            }
        }
    }

    // ---- the tray: how many apps, which, and how they look ----
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool on: false
        signal tapped()
        width: chipText.implicitWidth + 28
        height: 38
        radius: 19
        color: on ? Phone.accent : Phone.card
        border.color: on ? Phone.accent : Phone.mix("#2a2a2a", "#e2e2e2")
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: chip.on ? Phone.inkOnAccent : Phone.fg
            font.family: Phone.font
            font.pixelSize: 14
        }
        MouseArea {
            anchors.fill: parent
            onClicked: chip.tapped()
        }
    }
    component Caption: Text {
        color: Phone.dim
        font.family: Phone.font
        font.pixelSize: 13
        topPadding: 14
        bottomPadding: 6
    }
    Loader {
        anchors.fill: parent
        active: root.mode === "settings"
        sourceComponent: Item {
            Header {
                id: setHead
                title: "Home settings"
                onBack: root.mode = "gallery"
            }
            Column {
                anchors { left: parent.left; right: parent.right; top: setHead.bottom; leftMargin: 16; rightMargin: 16 }
                Caption { text: "Recent apps" }
                Row {
                    spacing: 8
                    Chip { label: "Carousel"; on: !Phone.overviewGrid; onTapped: Phone.setConf("overview", "carousel") }
                    Chip { label: "Grid"; on: Phone.overviewGrid; onTapped: Phone.setConf("overview", "grid") }
                }
                Caption { text: "Turning the phone" }
                Flow {
                    width: parent.width
                    spacing: 8
                    Chip { label: "Home turns too"; on: Phone.homeRotate; onTapped: Phone.setConf("home_rotate", "on") }
                    Chip { label: "Home stays upright"; on: !Phone.homeRotate; onTapped: Phone.setConf("home_rotate", "off") }
                }
                Caption { text: "More" }
                Chip {
                    label: "All settings"
                    onTapped: {
                        Status.settings("");
                        root.closed();
                    }
                }
            }
        }
    }
    Loader {
        anchors.fill: parent
        active: root.mode === "tray"
        sourceComponent: Item {
            id: tray
            readonly property var ids: Phone.dock.map(e => e.id)
            function move(i, d) {
                const l = ids.slice();
                [l[i], l[i + d]] = [l[i + d], l[i]];
                Phone.setPinnedOrder(l);
            }
            Header {
                id: trayHead
                title: "Tray"
                onBack: root.mode = "gallery"
            }
            Flickable {
                anchors { left: parent.left; right: parent.right; top: trayHead.bottom; bottom: parent.bottom; leftMargin: 16; rightMargin: 16 }
                clip: true
                contentHeight: trayCol.height + 24
                Column {
                    id: trayCol
                    width: parent.width
                    Caption { text: "Apps" }
                    Row {
                        spacing: 8
                        Repeater {
                            model: [3, 4, 5, 6]
                            delegate: Chip {
                                required property int modelData
                                label: modelData
                                on: Phone.dockSlots === modelData
                                onTapped: Phone.setConf("tray_count", modelData)
                            }
                        }
                    }
                    Caption { text: "Look" }
                    Flow {
                        width: parent.width
                        spacing: 8
                        Chip { label: "Icons only"; on: !Phone.trayLabels; onTapped: Phone.setConf("tray_labels", "off") }
                        Chip { label: "Icons with names"; on: Phone.trayLabels; onTapped: Phone.setConf("tray_labels", "on") }
                        Chip { label: "Background"; on: Phone.trayPlate; onTapped: Phone.setConf("tray_plate", Phone.trayPlate ? "off" : "on") }
                    }
                    Caption { text: "In the tray" }
                    Repeater {
                        model: Phone.dock
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: trayCol.width
                            height: 52
                            AppIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                entry: parent.modelData
                                size: 36
                            }
                            Text {
                                x: 48
                                width: parent.width - 48 - 140
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.modelData.name
                                elide: Text.ElideRight
                                color: Phone.fg
                                font.family: Phone.font
                                font.pixelSize: 15
                            }
                            Row {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: 6
                                Arrow { up: true; can: index > 0; onTapped: tray.move(index, -1) }
                                Arrow { up: false; can: index < tray.ids.length - 1; onTapped: tray.move(index, 1) }
                                Arrow {
                                    plus: true
                                    rotation: 45
                                    onTapped: Phone.setPinnedOrder(tray.ids.filter(id => id !== modelData.id))
                                }
                            }
                        }
                    }
                    Caption { text: "Add, in place of the last one when full" }
                    Repeater {
                        model: Phone.apps.filter(e => !tray.ids.includes(e.id))
                        delegate: Item {
                            required property var modelData
                            width: trayCol.width
                            height: 52
                            AppIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                entry: parent.modelData
                                size: 36
                            }
                            Text {
                                x: 48
                                width: parent.width - 48
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.modelData.name
                                elide: Text.ElideRight
                                color: Phone.fg
                                font.family: Phone.font
                                font.pixelSize: 15
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    const l = tray.ids.slice(0, Math.min(tray.ids.length, Phone.dockSlots - 1));
                                    l.push(parent.modelData.id);
                                    Phone.setPinnedOrder(l);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- the widgets of the card in view, at full size ----
    Loader {
        anchors.fill: parent
        active: root.mode === "widgets"
        sourceComponent: Item {
            id: edit
            property int selected: -1
            property bool adding: false
            property bool setting: false
            readonly property var widgets: Screens.screenOf(root.kind, root.cur).widgets
            readonly property var sel: widgets[selected] || null
            function save(list) { Screens.setWidgets(root.kind, root.cur, list); }
            function copy() { return JSON.parse(JSON.stringify(widgets)); }

            Component.onCompleted: {
                if (root.noteIndex >= 0)
                    noteSheet.open(root.noteIndex);
            }

            // the home as it is, under a scrim: white ink here in either theme
            Rectangle {
                anchors.fill: parent
                color: Phone.black
            }
            Image {
                anchors.fill: parent
                readonly property string wall: Screens.wallpaperOf(root.kind, root.cur)
                source: wall ? "file://" + wall : ""
                sourceSize: Qt.size(width, height)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.35)
            }
            MouseArea {
                anchors.fill: parent
                onClicked: edit.selected = -1
            }
            ScreenWidgets {
                id: layout
                anchors.fill: parent
                lock: root.lock
                preview: true
                ink: Phone.white
                dateInk: Phone.white
                screenIndex: root.cur
            }
            Repeater {
                model: edit.widgets
                delegate: MouseArea {
                    id: handle
                    required property var modelData
                    required property int index
                    readonly property var w: modelData
                    x: dragging ? layout.dragX : layout.xOf(w)
                    y: dragging ? layout.dragY : layout.yOf(w)
                    width: w.w * layout.cellW
                    height: w.h * Screens.rowH
                    preventStealing: true
                    property bool dragging: false
                    property real grabX: 0
                    property real grabY: 0
                    property bool moved: false
                    onPressed: mouse => { grabX = mouse.x; grabY = mouse.y; moved = false; }
                    onPositionChanged: mouse => {
                        const p = mapToItem(layout, mouse.x, mouse.y);
                        if (!dragging && Math.hypot(mouse.x - grabX, mouse.y - grabY) < 10)
                            return;
                        layout.dragX = p.x - grabX;
                        layout.dragY = p.y - grabY;
                        layout.dragIndex = index;
                        dragging = true;
                        moved = true;
                    }
                    function finish(commit) {
                        if (!dragging)
                            return;
                        const at = layout.cellAt(layout.dragX, layout.dragY, w);
                        const c = at.col, r = at.row;
                        dragging = false;
                        layout.dragIndex = -1;
                        // a spot that is taken sends it back where it was
                        if (commit && !Screens.overlaps(edit.widgets, index, c, r, w.w, w.h)) {
                            const list = edit.copy();
                            list[index].col = c;
                            list[index].row = r;
                            edit.save(list);
                        }
                    }
                    onReleased: finish(true)
                    onCanceled: finish(false)
                    onClicked: if (!moved) edit.selected = index
                    Rectangle {
                        anchors.fill: parent
                        visible: edit.selected === handle.index || handle.dragging
                        color: "transparent"
                        radius: 12
                        border.color: Phone.accent
                        border.width: 2
                    }
                }
            }

            Header {
                title: "Widgets"
                ink: Phone.white
                onBack: root.mode = "gallery"
            }
            Text {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: buttons.top; bottomMargin: 12 }
                id: noRoom
                property bool shown: false
                visible: shown
                text: "No room left on this screen"
                color: Phone.accent
                font.family: Phone.font
                font.pixelSize: 14
            }
            Row {
                id: buttons
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 84 }
                spacing: 8
                visible: !edit.adding && !edit.setting
                Pill {
                    visible: edit.sel === null
                    primary: true
                    label: "Add widget"
                    onTapped: { noRoom.shown = false; edit.adding = true; }
                }
                Pill {
                    visible: edit.sel !== null && Screens.sizes[edit.sel.type].length > 1
                    label: "Size"
                    onTapped: {
                        const list = edit.copy();
                        const w = list[edit.selected];
                        const all = Screens.sizes[w.type];
                        const at = all.findIndex(s => s[0] === w.w && s[1] === w.h);
                        for (let n = 1; n < all.length; n++) {
                            const s = all[(at + n) % all.length];
                            const c = Math.min(w.col, Screens.cols - s[0]);
                            if (!Screens.overlaps(list, edit.selected, c, w.row, s[0], s[1]) && w.row + s[1] <= layout.maxRows) {
                                w.col = c;
                                w.w = s[0];
                                w.h = s[1];
                                edit.save(list);
                                return;
                            }
                        }
                        noRoom.shown = true;
                    }
                }
                Pill {
                    visible: edit.sel !== null && edit.sel.type !== "app" && !Screens.bare(edit.sel)
                    label: "Settings"
                    onTapped: edit.setting = true
                }
                Pill {
                    visible: edit.sel !== null && edit.sel.type === "note"
                    label: "Edit text"
                    onTapped: noteSheet.open(edit.selected)
                }
                Pill {
                    visible: edit.sel !== null
                    label: "Remove"
                    onTapped: {
                        const list = edit.copy();
                        list.splice(edit.selected, 1);
                        edit.selected = -1;
                        edit.save(list);
                    }
                }
            }

            // where a dropped widget lands, or the first free spot for a tapped one
            function add(w, x, y) {
                const list = edit.copy();
                let spot = x === undefined ? null : layout.cellAt(x, y, w);
                if (spot && (Screens.overlaps(list, -1, spot.col, spot.row, w.w, w.h) || spot.row + w.h > layout.maxRows))
                    spot = null;
                spot = spot || Screens.freeSpot(list, w.w, w.h, layout.maxRows);
                edit.adding = false;
                if (!spot) {
                    noRoom.shown = true;
                    return;
                }
                list.push(Object.assign({}, w, { col: spot.col, row: spot.row }));
                edit.selected = list.length - 1;
                edit.save(list);
            }
            Loader {
                anchors.fill: parent
                active: edit.setting && edit.sel !== null
                sourceComponent: WidgetSettings {
                    w: edit.sel
                    onChanged: w => { const list = edit.copy(); list[edit.selected] = w; edit.save(list); }
                    onClosed: edit.setting = false
                }
            }
            Loader {
                anchors.fill: parent
                active: edit.adding
                sourceComponent: WidgetPicker {
                    lock: root.lock
                    onPicked: w => edit.add(w)
                    onDropped: (w, x, y) => edit.add(w, x, y)
                    onClosed: edit.adding = false
                }
            }

            // a short note, kept in the screens file and nowhere else
            Rectangle {
                id: noteSheet
                property int at: -1
                function open(i) {
                    at = i;
                    const w = edit.widgets[i];
                    noteField.text = w ? w.text || "" : "";
                    noteField.forceActiveFocus();
                }
                anchors.fill: parent
                visible: at >= 0
                color: Phone.bg
                MouseArea { anchors.fill: parent }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16; topMargin: Status.barHeight + 16 }
                    height: 160
                    radius: 20
                    color: Phone.card
                    TextEdit {
                        id: noteField
                        anchors { fill: parent; margins: 16 }
                        color: Phone.fg
                        selectionColor: Phone.accent
                        wrapMode: TextEdit.Wrap
                        font.family: Phone.font
                        font.pixelSize: 16
                        textFormat: TextEdit.PlainText
                        onTextChanged: if (text.length > Screens.noteMax) remove(Screens.noteMax, text.length)
                    }
                }
                Pill {
                    anchors { right: parent.right; rightMargin: 16 }
                    y: Status.barHeight + 192
                    primary: true
                    label: "Done"
                    onTapped: {
                        const list = edit.copy();
                        if (list[noteSheet.at]) {
                            list[noteSheet.at].text = noteField.text;
                            edit.save(list);
                        }
                        noteSheet.at = -1;
                        root.noteIndex = -1;
                    }
                }
            }
        }
    }

    // ---- delete asks first ----
    Item {
        anchors.fill: parent
        visible: root.confirming
        Rectangle {
            anchors.fill: parent
            color: "#b0000000"
        }
        MouseArea {
            anchors.fill: parent
            onClicked: root.confirming = false
        }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 48
            height: 148
            radius: 28
            color: Phone.mix("#222222", "#ffffff")
            border.color: Phone.mix("#333333", "#dcdcdc")
            MouseArea { anchors.fill: parent }
            Text {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 28 }
                text: "Delete this screen?"
                color: Phone.fg
                font.family: Phone.font
                font.pixelSize: 17
                font.weight: Font.Medium
            }
            Row {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 20 }
                spacing: 8
                Pill {
                    label: "Cancel"
                    onTapped: root.confirming = false
                }
                Pill {
                    primary: true
                    label: "Delete"
                    onTapped: {
                        root.confirming = false;
                        root.wanted = root.curN > 1 ? root.col : Math.max(0, root.col - 1);
                        if (root.curN > 1)
                            root.see(root.col, Math.max(0, root.curY - 1));
                        Screens.remove(root.kind, root.cur);
                    }
                }
            }
        }
    }
}
