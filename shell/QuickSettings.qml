import Quickshell
import QtQuick

// the right hand view, one scrolling page; every block and tile moves with the same drag
Item {
    id: root

    required property var model
    property int activeApps: 0
    property bool sinksOpen: false
    property bool powerOpen: false
    property bool turnOpen: false
    property bool editing: false
    signal openApps()

    SystemClock { id: time; precision: SystemClock.Minutes }

    // the finger, in this item's coordinates; dragId is what it carries
    property string dragId: ""
    property bool dragTile: false
    property bool lifted: false
    property bool landing: false
    property real fx: 0
    property real fy: 0
    property real fb: 0
    property real grabX: 0
    property real grabY: 0
    property int fromIndex: 0
    readonly property bool moving: dragId !== ""
    // the panel's swipes keep off while a finger rests on something movable
    readonly property bool busy: moving || lifted

    // ---- tiles ----
    readonly property int perPage: 6
    readonly property real pageW: flick.width
    readonly property real cellW: (pageW - 8) / 2
    readonly property int pages: Math.max(1, Math.ceil(shown.count / perPage))
    property int page: 0
    property real pageX: 0
    onPagesChanged: if (page >= pages) setPage(pages - 1)

    ListModel { id: shown }
    function sync() {
        if (moving)
            return;
        const want = model.ids;
        let same = want.length === shown.count;
        for (let i = 0; same && i < want.length; i++)
            same = shown.get(i).tid === want[i];
        if (same)
            return;
        shown.clear();
        for (const id of want)
            shown.append({ tid: id });
    }
    // here, not in the badge: the change destroys the badge's delegate mid handler
    function removeTile(i) { shown.remove(i); saveTiles(); }
    function addTile(id) { shown.append({ tid: id }); saveTiles(); }
    function saveTiles() {
        const out = [];
        for (let i = 0; i < shown.count; i++)
            out.push(shown.get(i).tid);
        model.saveOrder(out);
    }
    function indexOfTile(id) {
        for (let i = 0; i < shown.count; i++)
            if (shown.get(i).tid === id)
                return i;
        return -1;
    }
    function slotX(i) { return i % 2 * (cellW + 8); }
    function slotY(i) { return Math.floor(i % perPage / 2) * 72; }
    function clampPage(p) { return Math.max(0, Math.min(pages - 1, p)); }
    function setPage(p) {
        page = clampPage(p);
        pageAnim.stop();
        pageAnim.to = page * pageW;
        pageAnim.start();
    }
    NumberAnimation {
        id: pageAnim
        target: root
        property: "pageX"
        duration: 220
        easing.type: Easing.OutCubic
    }

    // ---- what the panel's sideways handler asks ----
    function wantsPage(p, dx) {
        const q = mapToItem(gridBox, p.x, p.y);
        if (q.x < 0 || q.y < 0 || q.x > gridBox.width || q.y > gridBox.height)
            return false;
        return dx < 0 ? page < pages - 1 : page > 0;
    }
    function pageDrag(dx) {
        pageAnim.stop();
        pageX = Math.max(0, Math.min((pages - 1) * pageW, page * pageW - dx));
    }
    function pageEnd(v) {
        setPage(Math.abs(v) >= Status.flick ? page + (v < 0 ? 1 : -1) : Math.round(pageX / pageW));
    }

    function begin(id, tile, p, item) {
        const o = item.mapToItem(root, 0, 0);
        grabX = p.x - o.x;
        grabY = tile ? p.y - o.y : mapToItem(body, p.x, p.y).y - blockY(id);
        dragTile = tile;
        fromIndex = tile ? indexOfTile(id) : 0;
        landing = false;
        dragId = id;
        follow(p);
    }
    function follow(p) {
        fx = p.x;
        fy = p.y;
        fb = mapToItem(body, p.x, p.y).y;
        if (dragTile)
            placeTile();
        else
            placeBlock();
    }
    function placeTile() {
        const q = mapToItem(gridBox, fx, fy);
        const inside = q.x >= -8 && q.x <= gridBox.width + 8 && q.y >= -8 && q.y <= gridBox.height + 8;
        const row = Math.max(0, Math.min(2, Math.floor(q.y / 72)));
        const to = inside ? Math.min(shown.count - 1, page * perPage + row * 2 + (q.x < pageW / 2 ? 0 : 1)) : fromIndex;
        const at = indexOfTile(dragId);
        if (at >= 0 && to !== at)
            shown.move(at, to, 1);
    }
    function drop() {
        if (!dragTile) {
            model.saveBlocks(blockList);
            dragId = "";
            sync();
            return;
        }
        const i = indexOfTile(dragId);
        setPage(Math.floor(i / perPage));
        const o = gridBox.mapToItem(root, slotX(i), slotY(i));
        landing = true;
        fx = o.x + grabX;
        fy = o.y + grabY;
        if (i !== fromIndex)
            saveTiles();
        landed.restart();
    }
    Timer {
        id: landed
        interval: 170
        onTriggered: {
            root.landing = false;
            root.dragId = "";
            root.sync();
        }
    }
    // resting at an edge turns the page; at the top or bottom of a long page it scrolls
    Timer {
        running: root.moving && root.dragTile && !root.landing
        interval: 500
        repeat: true
        onTriggered: {
            const q = root.mapToItem(gridBox, root.fx, root.fy);
            if (q.y < 0 || q.y > gridBox.height)
                return;
            if (q.x < 24 && root.page > 0)
                root.setPage(root.page - 1);
            else if (q.x > gridBox.width - 24 && root.page < root.pages - 1)
                root.setPage(root.page + 1);
            else
                return;
            root.placeTile();
        }
    }
    Timer {
        running: root.moving && !root.landing && flick.contentHeight > flick.height
        interval: 32
        repeat: true
        onTriggered: {
            const q = root.mapToItem(flick, root.fx, root.fy);
            const step = q.y < 40 ? -8 : q.y > flick.height - 40 ? 8 : 0;
            if (step === 0)
                return;
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + step));
            root.follow(Qt.point(root.fx, root.fy));
        }
    }

    // ---- blocks ----
    property var blockList: model.blocks
    function heightOf(id) {
        return id === "big" ? bigBlock.height : id === "brightness" ? brightBlock.height : id === "volume" ? volBlock.height : gridBlock.height;
    }
    function blockY(id) {
        let y = 0;
        for (const b of blockList) {
            if (b === id)
                return y;
            if (heightOf(b) > 0)
                y += heightOf(b) + 12;
        }
        return y;
    }
    readonly property real stackH: {
        let y = 0;
        for (const b of blockList)
            if (heightOf(b) > 0)
                y += heightOf(b) + 12;
        return y;
    }
    function placeBlock() {
        const others = blockList.filter(b => b !== dragId);
        const mid = fb - grabY + heightOf(dragId) / 2;
        let at = 0;
        let y = 0;
        for (const b of others) {
            if (heightOf(b) === 0)
                continue;
            if (mid > y + heightOf(b) / 2)
                at = others.indexOf(b) + 1;
            y += heightOf(b) + 12;
        }
        others.splice(at, 0, dragId);
        if (others.join() !== blockList.join())
            blockList = others;
    }
    Connections {
        target: root.model
        function onIdsChanged() { root.sync(); }
        function onBlocksChanged() { if (!root.moving) root.blockList = root.model.blocks; }
    }
    Component.onCompleted: sync()

    component Block: Item {
        id: blk
        required property string bid
        width: body.width
        y: root.dragId === bid ? root.fb - root.grabY : root.blockY(bid)
        z: root.dragId === bid ? 3 : 0
        Behavior on y { enabled: root.dragId !== blk.bid; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    // over a block in reorder mode: the whole of it is the handle
    component BlockHandle: DragArea {
        required property string bid
        anchors.fill: parent
        z: 5
        visible: root.editing
        immediate: true
        space: root
        onDragStarted: p => root.begin(bid, false, p, parent)
        onDragMoved: p => root.follow(p)
        onDragEnded: root.drop()
        Rectangle {
            anchors { fill: parent; margins: -2 }
            radius: 16
            color: "transparent"
            border.color: Phone.mix("#3a3a3a", "#cfcfcf")
        }
    }
    component RoundButton: Rectangle {
        id: rb
        property string icon: ""
        property bool bright: false
        signal tapped()
        width: 48
        height: 48
        radius: 24
        color: bright ? Phone.fg : Phone.frost
        scale: rbTap.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Icon {
            anchors.centerIn: parent
            name: rb.icon
            color: rb.bright ? Phone.mix("#141414", "#ffffff") : Phone.fg
            size: 22
        }
        MouseArea {
            id: rbTap
            anchors.fill: parent
            onClicked: rb.tapped()
        }
    }
    component BigTile: Rectangle {
        id: big
        property string icon: ""
        property int level: 0
        property string label: ""
        property string sub: ""
        property bool on: false
        signal toggled()
        signal held()
        height: 148
        radius: 56
        // frosted both ways over a wallpaper; over a bright one white labels keep 4.5:1 only up to about white 0.06 on the dark sheet
        readonly property bool glass: Phone.wallpaper !== ""
        color: !glass ? (on ? Phone.mix("#2a2a2a", "#e2e2e2") : Phone.mix("#1c1c1c", "#ffffff"))
            : Phone.light ? Qt.rgba(1, 1, 1, on ? 0.75 : 0.2) : on ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.12)
        scale: bigTap.pressed ? 0.98 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Behavior on color { ColorAnimation { duration: 140 } }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 18
            width: 52
            height: 52
            radius: 26
            color: !big.glass ? (big.on ? Phone.mix("#ececec", "#141414") : Phone.mix("#3a3a3a", "#cfcfcf"))
                : Phone.light ? Qt.rgba(0, 0, 0, big.on ? 0.16 : 0.06) : Qt.rgba(1, 1, 1, big.on ? 0.28 : 0.12)
            Behavior on color { ColorAnimation { duration: 140 } }
            Icon {
                anchors.centerIn: parent
                name: big.icon
                level: big.level
                color: big.on && !big.glass ? Phone.mix("#141414", "#ffffff") : Phone.fg
                size: 24
            }
        }
        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 18; rightMargin: 18; bottomMargin: 18 }
            spacing: 1
            Text {
                width: parent.width
                text: big.label
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                color: Phone.fg
                font.family: Phone.font
                font.pixelSize: 15
                font.weight: Font.Medium
            }
            Text {
                width: parent.width
                text: big.sub
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                color: Phone.glassDim
                font.family: Phone.font
                font.pixelSize: 12
            }
        }
        DragArea {
            id: bigTap
            anchors.fill: parent
            space: root
            onLiftedChanged: root.lifted = lifted
            onTapped: big.toggled()
            onHeld: big.held()
            onDragStarted: p => root.begin("big", false, p, big)
            onDragMoved: p => root.follow(p)
            onDragEnded: root.drop()
        }
    }
    component Badge: Rectangle {
        property string icon: ""
        anchors { right: parent.right; top: parent.top; margins: -2 }
        width: 26
        height: 26
        radius: 13
        color: Phone.mix("#444444", "#d0d0d0")
        border.color: Phone.bg
        Icon {
            color: Phone.fg
            anchors.centerIn: parent
            name: parent.icon
            size: 14
        }
    }

    // ---- what is on screen ----
    // the bar is covered here; the same line, the same places
    Row {
        x: Status.startFor(width, root.width)
        height: Status.barHeight
        spacing: 8
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatTime(time.date, "HH:mm")
            color: Phone.fg
            font.family: Phone.font
            font.pixelSize: 15
            font.weight: Font.Medium
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDate(time.date, "ddd, d MMM")
            color: Phone.glassDim
            font.family: Phone.font
            font.pixelSize: 13
        }
    }
    Row {
        x: (Dyn.holeKnown && Dyn.side === "right" ? Math.min(root.width - Status.cornerPad, Status.holeLeft(root.width)) : root.width - Status.cornerPad) - width
        height: Status.barHeight
        spacing: 6
        Rectangle {
            visible: Status.recording
            anchors.verticalCenter: parent.verticalCenter
            width: 8
            height: 8
            radius: 4
            color: Phone.accent
        }
        Icon {
            color: Phone.fg
            visible: Status.hasCell
            anchors.verticalCenter: parent.verticalCenter
            name: "cell"
            level: Status.cellLevel
        }
        Icon {
            visible: Status.hasWifi && Status.wifiOn
            anchors.verticalCenter: parent.verticalCenter
            name: "wifi"
            level: Status.wifiLevel
            color: Status.wifiConnected ? Phone.fg : Phone.glassDim
        }
        Icon {
            visible: Status.hasBt && Status.btOn
            anchors.verticalCenter: parent.verticalCenter
            name: "bt"
            color: Status.btConnected > 0 ? Phone.fg : Phone.glassDim
        }
        Icon {
            visible: Status.hasVolume
            anchors.verticalCenter: parent.verticalCenter
            name: Status.ringer === "normal" && Status.muted ? "volx" : Status.ringerIcon
            color: Status.ringer === "silent" || Status.muted ? Phone.accent : Phone.fg
        }
        BatteryPill {
            visible: Status.hasBattery
            anchors.verticalCenter: parent.verticalCenter
            level: Status.battery
            charging: Status.charging
        }
    }

    // in reorder mode a tap beside something must not close the panel
    MouseArea {
        anchors.fill: parent
        enabled: root.editing
    }

    Flickable {
        id: flick
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: footer.top; topMargin: Status.barHeight + 8; leftMargin: 16; rightMargin: 16; bottomMargin: 8 }
        clip: true
        contentHeight: body.height
        interactive: contentHeight > height && !root.busy && !Status.dragging
        boundsBehavior: Flickable.StopAtBounds

        Item {
            id: body
            width: flick.width
            height: root.stackH + (media.height > 0 && !root.editing ? media.height : 0) + (root.editing ? addSection.height : 0)

            Block {
                id: bigBlock
                bid: "big"
                visible: Status.hasWifi || Status.hasBt
                height: visible ? 148 : 0
                readonly property real bigW: Status.hasWifi && Status.hasBt ? (width - 8) / 2 : width
                BigTile {
                    visible: Status.hasWifi
                    width: bigBlock.bigW
                    icon: "wifi"
                    level: Status.wifiConnected ? Math.max(1, Status.wifiLevel) : 3
                    label: Status.wifiConnected && Status.s.wifiname ? Status.s.wifiname : "Wi-Fi"
                    sub: !Status.wifiOn ? "Off" : Status.wifiConnected ? "Connected" : "On"
                    on: Status.wifiOn
                    onToggled: Status.toggleWifi()
                    onHeld: if (!root.editing) Status.settings("wifi")
                }
                BigTile {
                    visible: Status.hasBt
                    x: Status.hasWifi ? bigBlock.bigW + 8 : 0
                    width: bigBlock.bigW
                    icon: "bt"
                    label: Status.btConnected > 0 && Status.s.btname ? Status.s.btname : "Bluetooth"
                    sub: !Status.btOn ? "Off" : Status.btConnected > 0 ? "Connected" : "On"
                    on: Status.btOn
                    onToggled: Status.toggleBt()
                    onHeld: if (!root.editing) Status.settings("bluetooth")
                }
                BlockHandle { bid: "big" }
            }
            Block {
                id: brightBlock
                bid: "brightness"
                visible: Status.hasBrightness
                height: visible ? 44 : 0
                DotSlider {
                    width: parent.width
                    icon: "sun"
                    value: Status.brightness
                    onMoved: v => Status.setBrightness(v)
                }
                BlockHandle { bid: "brightness" }
            }
            Block {
                id: volBlock
                bid: "volume"
                visible: Status.hasVolume
                height: visible ? 44 : 0
                DotSlider {
                    width: parent.width - (output.visible ? 52 : 0)
                    icon: Status.volIcon
                    iconColor: Status.muted ? Phone.accent : Phone.fg
                    value: Status.volume
                    dimmed: Status.muted
                    onMoved: v => Status.setVolume(v)
                    onIconTapped: Status.toggleMute()
                }
                Rectangle {
                    id: output
                    visible: root.model.sinks.length > 1
                    anchors.right: parent.right
                    width: 44
                    height: 44
                    radius: 22
                    color: Phone.frost
                    Icon {
                        color: Phone.fg
                        anchors.centerIn: parent
                        name: "output"
                        size: 20
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.sinksOpen = true
                    }
                }
                BlockHandle { bid: "volume" }
            }
            Block {
                id: gridBlock
                bid: "grid"
                readonly property bool any: shown.count + root.model.available.length > 0
                visible: any
                height: any ? gridBox.height + 36 : 0
                Item {
                    id: gridBox
                    width: parent.width
                    readonly property int rows: Math.min(3, Math.ceil(shown.count / 2))
                    height: rows > 0 ? rows * 72 - 8 : 0
                    clip: !root.moving
                    Item {
                        x: -root.pageX
                        Repeater {
                            model: shown
                            delegate: Item {
                                id: cell
                                required property int index
                                required property string tid
                                readonly property var t: root.model.tile(tid)
                                x: Math.floor(index / root.perPage) * root.pageW + root.slotX(index)
                                y: root.slotY(index)
                                width: root.cellW
                                height: 64
                                opacity: root.dragId === tid ? 0 : 1
                                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                QuickTile {
                                    width: parent.width
                                    scale: tap.lifted ? 1.05 : tap.pressed ? 0.97 : 1
                                    Behavior on scale { NumberAnimation { duration: 90 } }
                                    icon: cell.t.icon || ""
                                    label: cell.t.label || ""
                                    sub: cell.t.sub !== undefined ? cell.t.sub : cell.t.on ? "On" : "Off"
                                    on: !root.editing && !!cell.t.on
                                    // frosted off, the solid on stays
                                    color: on ? Phone.mix("#ececec", "#141414") : Phone.frost
                                    chevron: !root.editing && !!cell.t.page
                                }
                                DragArea {
                                    id: tap
                                    anchors.fill: parent
                                    immediate: root.editing
                                    space: root
                                    onLiftedChanged: root.lifted = lifted
                                    onTapped: x => {
                                        if (root.editing)
                                            return;
                                        if (cell.t.page && x > width - 36)
                                            Status.settings(cell.t.page);
                                        else
                                            cell.t.tap();
                                    }
                                    onHeld: {
                                        if (root.editing)
                                            return;
                                        if (cell.tid === "turn")
                                            root.turnOpen = true;
                                        else if (cell.t.page)
                                            Status.settings(cell.t.page);
                                    }
                                    onDragStarted: p => root.begin(cell.tid, true, p, cell)
                                    onDragMoved: p => root.follow(p)
                                    onDragEnded: root.drop()
                                }
                                Badge {
                                    visible: root.editing
                                    icon: "minus"
                                    MouseArea {
                                        anchors { fill: parent; margins: -8 }
                                        onClicked: root.removeTile(cell.index)
                                    }
                                }
                            }
                        }
                    }
                }
                Row {
                    anchors { horizontalCenter: parent.horizontalCenter; top: gridBox.bottom; topMargin: 10 }
                    visible: root.pages > 1
                    spacing: 6
                    Repeater {
                        model: root.pages
                        delegate: Rectangle {
                            required property int index
                            width: 6
                            height: 6
                            radius: 3
                            color: index === root.page ? Phone.fg : Phone.mix("#555555", "#bbbbbb")
                        }
                    }
                }
                // in reorder mode a swipe over a tile is a drag, so the dots turn the page too
                MouseArea {
                    anchors { left: parent.left; right: pencil.left; top: gridBox.bottom; bottom: parent.bottom }
                    enabled: root.pages > 1
                    onClicked: mouse => root.setPage(root.page + (mouse.x > width / 2 ? 1 : -1))
                }
                Item {
                    id: pencil
                    anchors { right: parent.right; top: gridBox.bottom }
                    width: 44
                    height: 36
                    Icon {
                        anchors.centerIn: parent
                        name: "pencil"
                        color: root.editing ? Phone.glassDim : Phone.fg
                        size: 18
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.editing = !root.editing
                    }
                }
            }
            MediaCard {
                id: media
                y: root.stackH
                width: parent.width
                visible: !root.editing && player !== null
                color: Phone.frost
            }
            Column {
                id: addSection
                y: root.stackH
                width: parent.width
                visible: root.editing
                spacing: 8
                Text {
                    visible: root.model.available.length > 0
                    text: "Add"
                    color: Phone.glassDim
                    font.family: Phone.font
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Grid {
                    columns: 2
                    spacing: 8
                    Repeater {
                        model: root.model.available
                        delegate: Item {
                            required property string modelData
                            readonly property var t: root.model.tile(modelData)
                            width: root.cellW
                            height: 64
                            QuickTile {
                                width: parent.width
                                icon: parent.t.icon || ""
                                label: parent.t.label || ""
                                color: Phone.frost
                            }
                            Badge { icon: "plus" }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.addTile(parent.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    // follows the finger above everything, so no page or scroll edge cuts it off
    QuickTile {
        id: ghost
        visible: root.moving && root.dragTile
        z: 4
        x: root.fx - root.grabX
        y: root.fy - root.grabY
        width: root.cellW
        scale: root.landing ? 1 : 1.05
        Behavior on x { enabled: root.landing; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: root.landing; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 90 } }
        readonly property var t: root.moving && root.dragTile ? root.model.tile(root.dragId) : ({})
        icon: t.icon || ""
        label: t.label || ""
        sub: t.sub !== undefined ? t.sub : t.on ? "On" : "Off"
        on: !root.editing && !!t.on
        chevron: !root.editing && !!t.page
    }

    Item {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; bottomMargin: 16 }
        height: 48
        Rectangle {
            visible: root.activeApps > 0 && !root.editing
            width: Math.min(appsRow.implicitWidth + 28, parent.width - 112)
            height: 48
            radius: 24
            color: Phone.frost
            Row {
                id: appsRow
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Icon {
                    color: Phone.fg
                    anchors.verticalCenter: parent.verticalCenter
                    name: "info"
                    size: 18
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.activeApps === 1 ? "1 app active" : root.activeApps + " apps active"
                    color: Phone.fg
                    font.family: Phone.font
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron"
                    rotation: -90
                    color: Phone.glassDim
                    size: 14
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.openApps()
            }
        }
        Row {
            anchors.right: parent.right
            spacing: 8
            visible: !root.editing
            RoundButton {
                icon: "gear"
                onTapped: Status.settings("")
            }
            RoundButton {
                icon: "power"
                bright: true
                onTapped: root.powerOpen = true
            }
        }
        Rectangle {
            visible: root.editing
            anchors.right: parent.right
            width: 96
            height: 48
            radius: 24
            color: Phone.fg
            Text {
                anchors.centerIn: parent
                text: "Done"
                color: Phone.mix("#141414", "#ffffff")
                font.family: Phone.font
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.editing = false
            }
        }
    }

    // above the tiles, it takes over from one only once a swipe has started; a resting finger turns it off
    // shortcut: when the page scrolls, only the footer closes it; add overscroll if testers miss it
    Item {
        y: flick.interactive ? footer.y : 0
        width: parent.width
        height: root.height - y
        DragHandler {
            target: null
            xAxis.enabled: false
            enabled: !root.busy && !root.editing && !root.sinksOpen && !root.powerOpen && !root.turnOpen
            onActiveChanged: {
                if (active) {
                    Status.grab();
                    Status.track(0);
                } else {
                    Status.releasePull(root.height, 0.75);
                }
            }
            onActiveTranslationChanged: {
                if (!active)
                    return;
                Status.track(activeTranslation.y);
                Status.pull = Math.max(0.001, Math.min(1, 1 + activeTranslation.y / root.height));
            }
        }
    }

    component Sheet: Item {
        id: sh
        default property alias rows: list.data
        signal dismissed()
        anchors.fill: parent
        z: 6
        MouseArea {
            anchors.fill: parent
            onClicked: sh.dismissed()
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16; bottomMargin: 72 }
            height: list.height + 24
            radius: 28
            color: Phone.mix("#222222", "#ffffff")
            border.color: Phone.mix("#333333", "#dcdcdc")
            MouseArea { anchors.fill: parent }
            Column {
                id: list
                x: 12
                y: 12
                width: parent.width - 24
            }
        }
    }
    component SheetRow: Item {
        id: row
        property string text: ""
        property bool active: false
        property bool marks: false
        signal picked()
        width: parent.width
        height: 52
        Text {
            anchors { left: parent.left; right: mark.left; verticalCenter: parent.verticalCenter; leftMargin: 12; rightMargin: 8 }
            text: row.text
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Phone.fg
            font.family: Phone.font
            font.pixelSize: 15
        }
        Rectangle {
            id: mark
            visible: row.marks
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            width: 12
            height: 12
            radius: 6
            color: row.active ? Phone.fg : "transparent"
            border.color: row.active ? Phone.fg : Phone.glassDim
        }
        MouseArea {
            anchors.fill: parent
            onClicked: row.picked()
        }
    }
    // where the sound goes
    Sheet {
        visible: root.sinksOpen
        onDismissed: root.sinksOpen = false
        Repeater {
            model: root.model.sinks
            delegate: SheetRow {
                required property var modelData
                text: modelData.name
                active: modelData.active
                marks: true
                onPicked: {
                    root.model.setSink(modelData.id);
                    root.sinksOpen = false;
                }
            }
        }
    }
    Sheet {
        visible: root.turnOpen
        onDismissed: root.turnOpen = false
        Repeater {
            model: ["normal", "90", "270", "180"]
            delegate: SheetRow {
                required property string modelData
                text: Status.turnName(modelData)
                active: Status.orientation === modelData
                marks: true
                onPicked: {
                    Status.turnTo(modelData);
                    root.turnOpen = false;
                }
            }
        }
    }
    Sheet {
        visible: root.powerOpen
        onDismissed: root.powerOpen = false
        SheetRow { text: "Sleep"; onPicked: Status.power("suspend") }
        SheetRow { text: "Restart"; onPicked: Status.power("reboot") }
        SheetRow { text: "Power off"; onPicked: Status.power("poweroff") }
    }
}
