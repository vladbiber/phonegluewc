import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// exists only while open; asks for the keyboard so the search field can have it
PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    // over a wallpaper the sheet and its blur run on under the bar, which the compositor puts above the menu
    exclusionMode: Phone.wallpaper === "" ? ExclusionMode.Normal : ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "phone-menu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property bool shown: false
    Component.onCompleted: shown = true
    // the compositor fades its blur behind the menu along with the sheet
    onShownChanged: if (!shown) Quickshell.execDetached(["phonegluewc-msg", "do", "menuclose"])
    // a pull down that starts at the top of the list takes the menu down with it
    property bool pulling: false
    property real pull: 0
    function pullEnd() {
        const v = Status.speed();
        pulling = false;
        if (pull > sheet.height / 4 || v >= Status.flick)
            Phone.menuOpen = false;
        else
            pull = 0;
    }
    Connections {
        target: Phone
        function onMenuOpenChanged() { if (!Phone.menuOpen) root.shown = false; }
    }

    readonly property var sorts: [["used", "Most used"], ["az", "A to Z"], ["za", "Z to A"], ["custom", "Custom"]]
    readonly property string mode: sorts.some(s => s[0] === Phone.conf.menu_sort) ? Phone.conf.menu_sort : "used"
    readonly property bool custom: mode === "custom" && !searching

    // ---- the custom order: ids and folders, in its own file; ids of apps not installed now are kept ----
    property var order: []
    function parseOrder() {
        try {
            const v = JSON.parse(orderFile.text());
            order = Array.isArray(v) ? v : [];
        } catch (e) {
            order = [];
        }
    }
    FileView {
        id: orderFile
        path: Phone.stateDir + "/menu-order.json"
        blockLoading: true
        printErrors: false
        onLoaded: root.parseOrder()
        onLoadFailed: root.order = []
    }
    // Ș sorts with S whatever the locale
    readonly property var az: Phone.apps.slice().sort((a, b) => fold(a.name).localeCompare(fold(b.name)) || a.name.localeCompare(b.name))
    property var lost: []
    function customItems() {
        const byId = {};
        Phone.apps.forEach(e => byId[e.id] = e);
        const seen = {};
        const out = [];
        const gone = [];
        for (const it of order) {
            if (typeof it === "string") {
                if (byId[it] && !seen[it]) {
                    seen[it] = true;
                    out.push({ entry: byId[it] });
                } else if (!byId[it]) {
                    gone.push(it);
                }
            } else if (it && Array.isArray(it.apps)) {
                const ids = it.apps.filter(id => typeof id === "string");
                const here = ids.filter(id => byId[id] && !seen[id]);
                here.forEach(id => seen[id] = true);
                const extra = ids.filter(id => !byId[id]);
                if (here.length > 0)
                    out.push({ folder: String(it.folder || "Folder"), apps: here.map(id => byId[id]), extra: extra });
                else if (extra.length > 0)
                    gone.push(it);
            }
        }
        az.forEach(e => { if (!seen[e.id]) out.push({ entry: e }); });
        lost = gone;
        return out;
    }
    readonly property var items: {
        const apps = az;
        if (mode === "custom")
            return customItems();
        if (mode === "za")
            return apps.slice().reverse().map(e => ({ entry: e }));
        if (mode === "az")
            return apps.map(e => ({ entry: e }));
        const u = Phone.usage;
        // ties stay A to Z
        return apps.map((e, i) => [e, i]).sort((a, b) => (u[b[0].id] || 0) - (u[a[0].id] || 0) || a[1] - b[1])
            .map(p => ({ entry: p[0] }));
    }
    function save(list) {
        const out = list.map(it => it.folder !== undefined
            ? { folder: it.folder, apps: it.apps.map(e => e.id).concat(it.extra || []) }
            : it.entry.id).concat(lost);
        order = out;
        orderFile.setText(JSON.stringify(out) + "\n");
    }
    function setSort(key) {
        sortOpen = false;
        // the first custom order is the one on screen
        if (key === "custom" && order.length === 0)
            save(items);
        Phone.setConf("menu_sort", key);
    }

    // ---- search: case and accents do not matter ----
    function fold(s) { return (s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase(); }
    readonly property bool searching: field.text.trim() !== ""
    readonly property var results: {
        const q = fold(field.text.trim());
        if (q === "")
            return [];
        return Phone.apps.filter(e => fold(e.name).includes(q) || fold(e.genericName).includes(q)
            || (e.keywords || []).some(k => fold(k).includes(q))).map(e => ({ entry: e }));
    }
    readonly property var shown2: searching ? results : items
    function launchFirst() { if (results.length > 0) Phone.launch(results[0].entry); }

    property bool sortOpen: false
    property int openFolder: -1

    // ---- dragging in the custom order ----
    property int dragFrom: -1
    property point finger
    // landscape fits more apps in a row
    readonly property int cols: width > height ? 7 : 4
    readonly property real cellW: grid.width / cols
    readonly property real cellH: 100
    // the slot under the finger, and whether it is over that slot's icon
    function slotAt(p) {
        const c = grid.contentItem.mapFromItem(null, p.x, p.y);
        const col = Math.max(0, Math.min(cols - 1, Math.floor(c.x / cellW)));
        const row = Math.max(0, Math.floor(c.y / cellH));
        const i = Math.min(shown2.length - 1, row * cols + col);
        const dx = c.x - (col + 0.5) * cellW;
        const dy = c.y - row * cellH;
        return { i: i, onIcon: i === row * cols + col && Math.abs(dx) < 30 && dy > 4 && dy < 66 };
    }
    readonly property var hover: dragFrom >= 0 ? slotAt(finger) : null
    function drop(p) {
        const from = dragFrom;
        dragFrom = -1;
        if (p.x < 0 || !grid.contains(grid.mapFromItem(null, p.x, p.y)))
            return;
        const at = slotAt(p);
        if (at.i === from || at.i < 0)
            return;
        const list = items.slice();
        const it = list[from];
        if (at.onIcon && it.folder === undefined) {
            const to = list[at.i];
            list[at.i] = to.folder !== undefined
                ? { folder: to.folder, apps: to.apps.concat([it.entry]), extra: to.extra }
                : { folder: "Folder", apps: [to.entry, it.entry], extra: [] };
            list.splice(from, 1);
        } else {
            list.splice(from, 1);
            list.splice(at.i, 0, it);
        }
        save(list);
    }
    function takeOut(fi, ai) {
        const list = items.slice();
        const f = list[fi];
        const apps = f.apps.slice();
        const e = apps.splice(ai, 1)[0];
        list[fi] = apps.length === 1 && (f.extra || []).length === 0 ? { entry: apps[0] } : { folder: f.folder, apps: apps, extra: f.extra };
        list.splice(fi + 1, 0, { entry: e });
        if (apps.length <= 1)
            openFolder = -1;
        save(list);
    }
    function rename(fi, name) {
        const list = items.slice();
        const f = list[fi];
        if (!f || f.folder === undefined || name.trim() === "" || name.trim() === f.folder)
            return;
        list[fi] = { folder: name.trim(), apps: f.apps, extra: f.extra };
        save(list);
    }
    Timer {
        interval: 32
        repeat: true
        running: root.dragFrom >= 0
        onTriggered: {
            const y = grid.mapFromItem(null, root.finger.x, root.finger.y).y;
            const step = y < 48 ? -12 : y > grid.height - 48 ? 12 : 0;
            if (step !== 0) {
                grid.contentY = Math.max(0, Math.min(grid.contentHeight - grid.height, grid.contentY + step));
                root.fingerChanged();
            }
        }
    }

    Rectangle {
        id: sheet
        readonly property real barInset: Phone.wallpaper === "" ? 0 : Status.barHeight
        width: parent.width
        height: parent.height - barInset
        // a tint over the compositor's blur of the wallpaper; opaque with none to blur
        color: Phone.wallpaper === "" ? Phone.bg : Phone.light ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(0, 0, 0, 0.45)
        // rounded like the overview cards so it reads as a sheet; over a wallpaper it runs on into the bar's frosted strip
        topLeftRadius: Phone.wallpaper === "" ? 14 : 0
        topRightRadius: topLeftRadius
        opacity: root.shown ? 1 : 0
        // closing from a pull goes on down from where the finger left it
        y: barInset + (Dyn.anim ? (root.shown ? root.pull : Math.max(56, root.pull)) : root.shown ? 0 : 56)
        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !root.pulling; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        Keys.onEscapePressed: Phone.menuOpen = false

        Rectangle {
            y: -sheet.barInset
            width: parent.width
            height: sheet.barInset
            color: sheet.color
        }

        Rectangle {
            id: sortChip
            anchors { top: parent.top; topMargin: 26; left: parent.left; leftMargin: 20 }
            height: 40
            width: sortText.implicitWidth + 44
            radius: 20
            color: sortTap.pressed || root.sortOpen ? Phone.mix("#2a2a2a", "#e2e2e2") : Phone.card

            Text {
                id: sortText
                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                text: root.sorts.find(s => s[0] === root.mode)[1]
                color: Phone.fg
                font.family: Phone.font
                font.pixelSize: 15
            }
            Icon {
                color: Phone.fg
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                name: "chevron"
                size: 14
            }
            MouseArea {
                id: sortTap
                anchors.fill: parent
                onClicked: root.sortOpen = !root.sortOpen
            }
        }

        Item {
            id: close
            anchors { top: parent.top; topMargin: 20; right: parent.right; rightMargin: 12 }
            width: 52
            height: 52

            Repeater {
                model: [45, -45]
                delegate: Rectangle {
                    required property int modelData
                    anchors.centerIn: parent
                    width: 20
                    height: 2
                    radius: 1
                    rotation: modelData
                    color: Phone.fg
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: Phone.menuOpen = false
            }
        }

        Flickable {
            id: grid
            anchors { top: close.bottom; topMargin: 12; bottom: bar.top; bottomMargin: 8; left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 12 }
            clip: true
            contentWidth: width
            contentHeight: Math.ceil(root.shown2.length / root.cols) * root.cellH
            // the list itself stays put past its ends; the overshoot at the top is the pull
            boundsBehavior: Flickable.DragOverBounds
            boundsMovement: Flickable.StopAtBounds
            interactive: root.dragFrom < 0
            onDraggingChanged: {
                if (dragging && atYBeginning) {
                    root.pulling = true;
                    Status.trail = [[Date.now(), 0]];
                } else if (!dragging && root.pulling) {
                    root.pullEnd();
                }
            }

            Repeater {
                model: root.shown2
                delegate: AppCell {
                    required property var modelData
                    required property int index
                    x: (index % root.cols) * root.cellW
                    y: Math.floor(index / root.cols) * root.cellH
                    width: root.cellW
                    height: root.cellH
                    item: modelData
                    canDrag: root.custom
                    target: root.hover !== null && root.hover.onIcon && root.hover.i === index && index !== root.dragFrom
                        && root.shown2[root.dragFrom].folder === undefined
                    onTapped: {
                        if (modelData.folder !== undefined)
                            root.openFolder = index;
                        else
                            Phone.launch(modelData.entry);
                    }
                    onDragStarted: p => { Phone.pinId = ""; root.finger = p; root.dragFrom = index; }
                    onDragMoved: p => root.finger = p
                    onDragEnded: p => root.drop(p)
                }
            }
        }
        // the list's overshoot is damped, so the pull is the finger's own travel; above the icons, which take the press
        Item {
            anchors.fill: grid
            PointHandler {
                onPointChanged: {
                    if (!root.pulling)
                        return;
                    root.pull = Math.max(0, point.scenePosition.y - point.scenePressPosition.y);
                    Status.track(root.pull);
                }
            }
        }

        // what the finger carries
        AppCell {
            visible: root.dragFrom >= 0
            item: root.dragFrom >= 0 ? root.shown2[root.dragFrom] : ({})
            width: root.cellW
            height: root.cellH
            x: sheet.mapFromItem(null, root.finger.x, root.finger.y).x - width / 2
            y: sheet.mapFromItem(null, root.finger.x, root.finger.y).y - 36
            scale: 1.1
            enabled: false
        }

        Text {
            anchors { top: grid.top; topMargin: 28; left: parent.left; right: parent.right; leftMargin: 28; rightMargin: 28 }
            visible: root.searching && root.results.length === 0
            text: "No apps match “" + field.text.trim() + "”"
            color: Phone.glassDim
            wrapMode: Text.Wrap
            font.family: Phone.font
            font.pixelSize: 16
        }

        Rectangle {
            id: bar
            anchors { bottom: parent.bottom; bottomMargin: 20; left: parent.left; leftMargin: 20; right: parent.right; rightMargin: 20 }
            height: 52
            radius: 26
            color: Phone.card

            Icon {
                id: lens
                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                name: "search"
                size: 20
                color: Phone.glassDim
            }
            TextInput {
                id: field
                anchors { fill: parent; leftMargin: 48; rightMargin: 22 }
                verticalAlignment: TextInput.AlignVCenter
                color: Phone.fg
                selectionColor: Phone.accent
                font.family: Phone.font
                font.pixelSize: 17
                inputMethodHints: Qt.ImhNoPredictiveText
                Keys.onEscapePressed: Phone.menuOpen = false
                Keys.onReturnPressed: root.launchFirst()

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: field.text === ""
                    text: "Search apps"
                    color: Phone.glassDim
                    font: field.font
                }
            }
        }

        // ---- the sort choice ----
        MouseArea {
            anchors.fill: parent
            visible: root.sortOpen
            onClicked: root.sortOpen = false
        }
        Rectangle {
            anchors { top: sortChip.bottom; topMargin: 6; left: sortChip.left }
            visible: root.sortOpen
            width: 200
            height: sortCol.height + 12
            radius: 20
            color: Phone.mix("#262626", "#ffffff")

            Column {
                id: sortCol
                anchors { top: parent.top; topMargin: 6; left: parent.left; right: parent.right }
                Repeater {
                    model: root.sorts
                    delegate: Rectangle {
                        required property var modelData
                        width: sortCol.width
                        height: 48
                        color: pick.pressed ? Phone.mix("#333333", "#dcdcdc") : "transparent"
                        Text {
                            anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                            text: modelData[1]
                            color: modelData[0] === root.mode ? Phone.accent : Phone.fg
                            font.family: Phone.font
                            font.pixelSize: 15
                        }
                        MouseArea {
                            id: pick
                            anchors.fill: parent
                            onClicked: root.setSort(modelData[0])
                        }
                    }
                }
            }
        }

        // ---- an open folder: its apps, its name to edit, drag one out to take it out ----
        Rectangle {
            id: folderView
            anchors.fill: parent
            visible: f !== null
            color: "#d0000000"
            readonly property var f: root.openFolder >= 0 && root.custom && root.items[root.openFolder]
                && root.items[root.openFolder].folder !== undefined ? root.items[root.openFolder] : null
            property int dragAt: -1
            property point finger
            onFChanged: folderName.text = f ? f.folder : ""

            MouseArea {
                anchors.fill: parent
                // the name is saved before the folder goes
                onClicked: { folderName.focus = false; root.openFolder = -1; }
            }
            Rectangle {
                id: card
                anchors { left: parent.left; right: parent.right; leftMargin: 24; rightMargin: 24; verticalCenter: parent.verticalCenter }
                height: 76 + Math.ceil((folderView.f ? folderView.f.apps.length : 0) / root.cols) * root.cellH
                radius: 28
                color: Phone.mix("#1c1c1c", "#ffffff")

                MouseArea { anchors.fill: parent }
                TextInput {
                    id: folderName
                    anchors { top: parent.top; topMargin: 20; left: parent.left; right: parent.right; leftMargin: 24; rightMargin: 24 }
                    color: Phone.fg
                    font.family: Phone.font
                    font.pixelSize: 20
                    horizontalAlignment: TextInput.AlignHCenter
                    maximumLength: 40
                    onEditingFinished: root.rename(root.openFolder, text)
                }
                Repeater {
                    model: folderView.f ? folderView.f.apps : []
                    delegate: AppCell {
                        required property var modelData
                        required property int index
                        x: (index % root.cols) * (card.width / root.cols)
                        y: 64 + Math.floor(index / root.cols) * root.cellH
                        width: card.width / root.cols
                        height: root.cellH
                        item: ({ entry: modelData })
                        canDrag: true
                        onTapped: Phone.launch(modelData)
                        onDragStarted: p => { Phone.pinId = ""; folderView.finger = p; folderView.dragAt = index; }
                        onDragMoved: p => folderView.finger = p
                        onDragEnded: p => {
                            const at = folderView.dragAt;
                            folderView.dragAt = -1;
                            if (p.x >= 0 && !card.contains(card.mapFromItem(null, p.x, p.y)))
                                root.takeOut(root.openFolder, at);
                        }
                    }
                }
            }
            AppCell {
                visible: folderView.dragAt >= 0
                item: folderView.dragAt >= 0 && folderView.f ? ({ entry: folderView.f.apps[folderView.dragAt] }) : ({})
                width: root.cellW
                height: root.cellH
                x: folderView.mapFromItem(null, folderView.finger.x, folderView.finger.y).x - width / 2
                y: folderView.mapFromItem(null, folderView.finger.x, folderView.finger.y).y - 36
                scale: 1.1
                enabled: false
            }
        }
    }
}
