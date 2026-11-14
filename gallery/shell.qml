import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel

// a program of its own like settings: the photos and clips by day, one tapped opens full screen
ShellRoot {
    settings.watchFiles: false

    IpcHandler {
        target: "gallery"
        function open(path: string): void { S.open(path); }
        function bars(on: bool): void { S.bars = on; }
        function info(on: bool): void { S.setInfo(on); }
        function view(v: string): void { S.view = v; if (v === "albums") S.refreshAlbums(); }
        function toggle(path: string): void { S.toggleSel(path); }
        function album(name: string): void { S.openAlbum(name); }
        function sheet(on: bool): void { android.visible = on; }
        function say(text: string): void { S.say(text); }
    }

    FloatingWindow {
        title: Quickshell.env("PHONEGALLERY_TITLE") || "Gallery"
        color: S.black
        visible: true
        onClosed: Qt.quit()

        Item {
            id: page
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: S.back()

            Item {
                id: head
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 64
                visible: !S.selecting
                BackBtn { id: backBtn }
                DotText {
                    anchors { left: backBtn.right; verticalCenter: parent.verticalCenter }
                    text: "GALLERY"
                }
                DotText {
                    anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                    text: S.photos.count ? String(S.photos.count) : ""
                    color: S.grey
                    px: 1.8
                    gap: 1
                }
            }

            // timeline of the open album, or the album tiles
            Row {
                id: tabs
                anchors { top: head.bottom; left: parent.left; leftMargin: 16 }
                height: 40
                spacing: 26
                visible: !S.selecting
                Repeater {
                    model: [{ key: "timeline", text: S.album === "Camera" ? "Timeline" : S.album }, { key: "albums", text: "Albums" }]
                    delegate: Item {
                        required property var modelData
                        width: tabLabel.implicitWidth
                        height: 40
                        T { id: tabLabel; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData.text; wrapMode: Text.NoWrap
                            font.pixelSize: 15; color: S.view === parent.modelData.key ? S.white : S.grey }
                        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 2; radius: 1; color: S.accent; visible: S.view === parent.modelData.key }
                        MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: { S.view = parent.modelData.key; if (S.view === "albums") S.refreshAlbums(); } }
                    }
                }
                // what Android may see, and the Android folder
                T { anchors.verticalCenter: parent.verticalCenter; text: "Android"; color: S.grey; font.pixelSize: 15
                    MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: { android.visible = true; S.refreshFolders(); } } }
                // rename or delete the open album (never Camera)
                T { visible: S.album !== "Camera" && S.view === "timeline"; anchors.verticalCenter: parent.verticalCenter; text: "Rename"; color: S.grey; font.pixelSize: 13
                    MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: prompt.ask("rename", "") } }
                T { id: delAlbum; visible: S.album !== "Camera" && S.view === "timeline"; anchors.verticalCenter: parent.verticalCenter
                    property bool armed: false
                    text: armed ? (S.lastLink ? "Files only here: tap to delete them too" : "Tap again") : "Delete album"
                    color: armed ? S.accent : S.grey; font.pixelSize: 13; wrapMode: Text.NoWrap
                    Timer { running: delAlbum.armed; interval: 4000; onTriggered: delAlbum.armed = false }
                    MouseArea { anchors.fill: parent; anchors.margins: -10
                        onClicked: {
                            if (!delAlbum.armed) { delAlbum.armed = true; return; }
                            S.albums(S.lastLink ? ["delete", S.album, "--force"] : ["delete", S.album], code => {
                                if (code === 3) { S.lastLink = true; return; }
                                delAlbum.armed = false; S.lastLink = false; S.album = "Camera"; S.refreshAlbums();
                            });
                        } } }
            }

            // selection bar: how many, and what to do with them
            Item {
                id: selBar
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 64
                visible: S.selecting
                Item { id: selClose; width: 56; height: 64
                    LineIcon { anchors.centerIn: parent; name: "close" }
                    MouseArea { anchors.fill: parent; onClicked: S.clearSel() } }
                T { anchors { left: selClose.right; verticalCenter: parent.verticalCenter } text: S.selCount + " selected"; font.pixelSize: 16; font.weight: Font.Light; wrapMode: Text.NoWrap }
                Row {
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    Repeater {
                        model: [{ k: "add", t: "Add" }, { k: "move", t: "Move" }, { k: "send", t: "Send" }, { k: "delete", t: "Delete" }]
                        delegate: Item {
                            id: act
                            required property var modelData
                            property bool armed: false
                            width: actText.implicitWidth + 20; height: 48
                            T { id: actText; anchors.centerIn: parent; text: act.armed ? "Sure?" : act.modelData.t; wrapMode: Text.NoWrap; font.pixelSize: 15
                                color: act.armed ? S.accent : S.white }
                            Timer { running: act.armed; interval: 3000; onTriggered: act.armed = false }
                            MouseArea { anchors.fill: parent
                                onClicked: {
                                    if (act.modelData.k === "send") { S.sendFiles(S.selPaths()); S.clearSel(); return; }
                                    if (act.modelData.k === "delete") {
                                        if (!act.armed) { act.armed = true; return; }
                                        act.armed = false;
                                        S.albums(S.album === "Camera" ? ["trash", ...S.selPaths()] : ["remove", S.album, ...S.selPaths(), "--force"], S.afterAction);
                                    } else {
                                        picker.mode = act.modelData.k;
                                        picker.visible = true;
                                    }
                                } }
                        }
                    }
                }
            }

            // the album tiles
            GridView {
                id: albumGrid
                anchors { top: tabs.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; margins: 12; topMargin: 8 }
                visible: S.view === "albums" && !S.selecting
                cellWidth: Math.floor(width / 2)
                cellHeight: cellWidth + 44
                clip: true
                model: S.albumList.concat([{ name: "", count: 0, cover: "" }])
                delegate: Item {
                    id: tile
                    required property var modelData
                    width: albumGrid.cellWidth; height: albumGrid.cellHeight
                    readonly property bool isNew: modelData.name === ""
                    Rectangle {
                        id: cover
                        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 4 }
                        height: width
                        radius: 16
                        color: S.surface
                        clip: true
                        Image {
                            anchors.fill: parent
                            visible: !tile.isNew && /\.(jpe?g|png|webp)$/i.test(tile.modelData.cover)
                            source: visible ? "file://" + tile.modelData.cover : ""
                            sourceSize: Qt.size(400, 400)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            autoTransform: true
                        }
                        LineIcon { anchors.centerIn: parent; visible: tile.isNew; name: "plus"; size: 34; color: S.grey }
                    }
                    T { anchors { top: cover.bottom; topMargin: 8; left: parent.left; leftMargin: 8 } width: parent.width - 16; elide: Text.ElideRight; wrapMode: Text.NoWrap
                        text: tile.isNew ? "New album" : tile.modelData.name; font.pixelSize: 15 }
                    T { anchors { top: cover.bottom; topMargin: 28; left: parent.left; leftMargin: 8 } visible: !tile.isNew; text: tile.modelData.count; color: S.grey; font.pixelSize: 12 }
                    MouseArea { anchors.fill: parent; onClicked: tile.isNew ? prompt.ask("create", "") : S.openAlbum(tile.modelData.name) }
                }
            }

            ListView {
                id: grid
                visible: S.view === "timeline"
                anchors { top: S.selecting ? selBar.bottom : tabs.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
                model: S.days
                readonly property int cell: Math.floor(width / 3)
                cacheBuffer: Math.max(0, height * 2)
                reuseItems: true
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                bottomMargin: 16
                delegate: Item {
                    id: row
                    required property int index
                    required property string label
                    required property int a
                    required property int b
                    required property int c
                    width: grid.width
                    height: label !== "" ? 42 : grid.cell
                    // day header: dotted caps left, how many that day right
                    DotText {
                        visible: row.label !== ""
                        anchors { left: parent.left; leftMargin: 16; bottom: parent.bottom; bottomMargin: 8 }
                        text: row.label.toUpperCase()
                        px: 1.5
                        gap: 0.9
                    }
                    DotText {
                        visible: row.label !== ""
                        anchors { right: parent.right; rightMargin: 16; bottom: parent.bottom; bottomMargin: 8 }
                        text: row.label !== "" ? String(S.dayCount(row.index)) : ""
                        color: S.grey
                        px: 1.5
                        gap: 0.9
                    }
                    Row {
                        visible: row.label === ""
                        Repeater {
                            model: [row.a, row.b, row.c]
                            delegate: Item {
                                id: cell
                                required property int modelData
                                readonly property bool has: modelData >= 0
                                readonly property string filePath: has ? (S.photos.get(modelData, "filePath") || "") : ""
                                readonly property bool picked: has && S.selected[filePath] === true
                                readonly property string thumb: has ? S.thumbOf(S.photos.get(modelData, "fileName"), S.photos.get(modelData, "fileModified")) : ""
                                width: grid.cell
                                height: grid.cell
                                Rectangle {
                                    anchors { fill: parent; margins: 1 }
                                    visible: cell.has
                                    color: S.surface
                                    scale: tap.pressed ? 0.96 : cell.picked ? 0.9 : 1
                                    Behavior on scale { enabled: S.anim; NumberAnimation { duration: 100 } }
                                    Image {
                                        anchors.fill: parent
                                        source: cell.has && S.hasThumb(cell.thumb) ? "file://" + cell.thumb : ""
                                        sourceSize: Qt.size(grid.cell * 2, grid.cell * 2)
                                        asynchronous: true
                                        fillMode: Image.PreserveAspectCrop
                                        clip: true
                                        opacity: status === Image.Ready ? 1 : 0
                                        Behavior on opacity { enabled: S.anim; NumberAnimation { duration: 160 } }
                                    }
                                }
                                Rectangle {
                                    visible: cell.picked
                                    anchors { top: parent.top; right: parent.right; margins: 10 }
                                    width: 26; height: 26; radius: 13; color: S.accent
                                    LineIcon { anchors.centerIn: parent; name: "check"; size: 18; color: S.inkOnAccent }
                                }
                                MouseArea {
                                    id: tap
                                    anchors.fill: parent
                                    enabled: cell.has
                                    onPressAndHold: S.toggleSel(cell.filePath)
                                    onClicked: {
                                        if (S.selecting) { S.toggleSel(cell.filePath); return; }
                                        const p = cell.mapToItem(page, 0, 0);
                                        S.origin = Qt.rect(p.x, p.y, cell.width, cell.height);
                                        S.current = cell.modelData;
                                    }
                                }
                            }
                        }
                    }
                }
            }

            T {
                anchors.centerIn: grid
                visible: S.photos.status === FolderListModel.Ready && S.photos.count === 0
                text: "No photos yet"
                color: S.grey
            }

            // a line of news that fades by itself
            Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 40 }
                width: toastText.implicitWidth + 40; height: 44; radius: 22; color: S.surface
                opacity: S.toast !== "" ? 1 : 0
                visible: opacity > 0
                z: 5
                Behavior on opacity { enabled: S.anim; NumberAnimation { duration: 200 } }
                T { id: toastText; anchors.centerIn: parent; text: S.toast; wrapMode: Text.NoWrap; font.pixelSize: 14 }
            }

            // what Android (Waydroid) can see of the gallery
            Rectangle {
                id: android
                anchors.fill: parent
                visible: false
                color: Qt.rgba(0, 0, 0, 0.9)
                z: 4
                MouseArea { anchors.fill: parent; onClicked: android.visible = false }
                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 130; margins: 24 }
                    spacing: 10
                    T { text: "What Android can see"; font.pixelSize: 18 }
                    Repeater {
                        model: [{ k: "send", t: "Only what I send", h: "Copies go into one folder, Pictures/PhoneGallery." },
                                { k: "album", t: "Selected albums only", h: "Only the albums you tick below, each read only." },
                                { k: "all", t: "The whole gallery", h: "Every Android app with photo access can then read all photos. Read only." }]
                        delegate: Rectangle {
                            id: opt
                            required property var modelData
                            width: parent.width; height: optCol.implicitHeight + 24; radius: 16
                            color: S.androidMode === modelData.k ? S.press : S.surface
                            border { width: S.androidMode === modelData.k ? 2 : 0; color: S.accent }
                            Column { id: optCol; anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 } spacing: 4
                                T { width: parent.width; text: opt.modelData.t; font.pixelSize: 16 }
                                T { width: parent.width; text: opt.modelData.h; color: S.grey; font.pixelSize: 12 } }
                            MouseArea { anchors.fill: parent
                                onClicked: S.setAndroid(opt.modelData.k) }
                        }
                    }
                    Row {
                        spacing: 10
                        Btn { text: S.androidStrip ? "Strip details: on" : "Strip details: off"; onTapped: { S.androidStrip = !S.androidStrip; S.saveAndroid(); } }
                        Btn { text: "Empty Android folder"; confirm: true; onTapped: S.clearAndroid() }
                    }
                    T { width: parent.width; text: "Stripping applies to copies that are sent. An album or the whole gallery is shown as it is."; color: S.grey; font.pixelSize: 12 }
                    // the albums to show when the middle choice is on: a box and a count each
                    Column {
                        visible: S.androidMode === "album"
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: S.folderList
                            delegate: Rectangle {
                                id: row
                                required property var modelData
                                readonly property bool on: S.androidAlbums.includes(modelData.name)
                                width: parent.width; height: 46; radius: 14; color: S.surface
                                Rectangle { id: box; anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter } width: 22; height: 22; radius: 6
                                    color: row.on ? S.accent : "transparent"; border { width: 2; color: row.on ? S.accent : S.grey }
                                    LineIcon { anchors.centerIn: parent; name: "check"; size: 16; visible: row.on; color: S.inkOnAccent } }
                                T { anchors { left: box.right; leftMargin: 14; verticalCenter: parent.verticalCenter } text: row.modelData.name; font.pixelSize: 15 }
                                T { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } text: row.modelData.count; color: S.grey; font.pixelSize: 13 }
                                MouseArea { anchors.fill: parent; onClicked: S.tickAlbum(row.modelData.name) }
                            }
                        }
                    }
                }
            }

            // pick the album for "add" and "move"
            Rectangle {
                id: picker
                property string mode: "add"
                anchors.fill: parent
                visible: false
                color: Qt.rgba(0, 0, 0, 0.82)
                MouseArea { anchors.fill: parent; onClicked: picker.visible = false }
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    spacing: 8
                    T { text: picker.mode === "move" ? "Move to album" : "Add to album"; color: S.grey; font.pixelSize: 14 }
                    Repeater {
                        model: S.albumList.filter(a => a.name !== S.album)
                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width; height: 52; radius: 16; color: S.surface
                            T { anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter } text: parent.modelData.name; font.pixelSize: 16 }
                            MouseArea { anchors.fill: parent
                                onClicked: { picker.visible = false; S.albums([picker.mode, parent.modelData.name, ...S.selPaths()], S.afterAction); } }
                        }
                    }
                    Rectangle {
                        width: parent.width; height: 52; radius: 16; color: S.surface
                        T { anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter } text: "New album"; color: S.accent; font.pixelSize: 16 }
                        MouseArea { anchors.fill: parent; onClicked: { picker.visible = false; prompt.ask("createWith", ""); } }
                    }
                }
            }

            // a name for a new or renamed album; the system keyboard comes up with the field
            Rectangle {
                id: prompt
                property string mode: "create"
                property string error: ""
                function ask(m, text) { mode = m; error = ""; field.text = text; visible = true; field.forceActiveFocus(); }
                anchors.fill: parent
                visible: false
                color: Qt.rgba(0, 0, 0, 0.82)
                MouseArea { anchors.fill: parent }
                onVisibleChanged: if (!visible) field.focus = false  // the keyboard goes with the prompt
                Column {
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 160; margins: 24 }
                    spacing: 14
                    T { text: prompt.mode === "rename" ? "Rename album" : "New album"; font.pixelSize: 18 }
                    Rectangle {
                        width: parent.width; height: 54; radius: 16; color: S.surface
                        TextInput { id: field; anchors { fill: parent; leftMargin: 18; rightMargin: 18 } verticalAlignment: TextInput.AlignVCenter
                            color: S.white; font.family: S.font; font.pixelSize: 17; maximumLength: 40; clip: true
                            onAccepted: go.clicked() }
                    }
                    T { visible: prompt.error !== ""; text: prompt.error; color: S.accent; font.pixelSize: 13 }
                    Row {
                        spacing: 10
                        Btn { text: "Cancel"; onTapped: prompt.visible = false }
                        Btn { id: go; primary: true; text: "OK"
                            signal clicked()
                            onTapped: {
                                const name = field.text.trim();
                                const done = code => { if (code !== 0) { prompt.error = "Letters, digits, space, - _ . only, and not taken"; return; } prompt.visible = false; S.refreshAlbums(); };
                                if (prompt.mode === "rename") S.albums(["rename", S.album, name], code => { if (code === 0) S.album = name; done(code); });
                                else if (prompt.mode === "createWith") S.albums(["create", name], code => { if (code !== 0) { done(code); return; } S.albums([picker.mode, name, ...S.selPaths()], c => { done(c); S.afterAction(); }); });
                                else S.albums(["create", name], done);
                            }
                            onClicked: tapped()
                        }
                    }
                }
            }

            Viewer {
                anchors.fill: parent
                // the way back lands on the tile of the item that is open now, wherever swiping took it
                onClosing: i => {
                    const r = S.rowOf(i);
                    grid.positionViewAtIndex(r, ListView.Contain);
                    const it = grid.itemAtIndex(r);
                    if (it) {
                        const p = it.mapToItem(page, 0, 0), col = it.a === i ? 0 : it.b === i ? 1 : 2;
                        S.origin = Qt.rect(p.x + col * grid.cell, p.y, grid.cell, grid.cell);
                    }
                }
            }
        }
    }
}
