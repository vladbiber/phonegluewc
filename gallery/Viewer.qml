import Quickshell
import QtQuick

// one item full screen: it grows out of its tile, swipe to the next, pinch or double tap to zoom,
// a tap hides the bars, the strip scrubs through the roll, the sheet shows the details
Rectangle {
    id: root
    signal closing(int index)
    property int last: -1
    property real t: 0
    readonly property bool open: S.current >= 0
    readonly property bool clip: list.currentItem ? S.isClip(list.currentItem.fileName) : false
    color: S.black
    visible: t > 0
    opacity: Math.min(1, t * 2.5)
    // from the tile's size and place to the whole screen
    scale: s0 + (1 - s0) * t
    readonly property real s0: Math.max(0.1, S.origin.width / Math.max(1, width))
    transform: Translate {
        x: (S.origin.x + S.origin.width / 2 - root.width / 2) * (1 - root.t)
        y: (S.origin.y + S.origin.height / 2 - root.height / 2) * (1 - root.t)
    }
    NumberAnimation { id: grow; target: root; property: "t"; duration: S.anim ? 300 : 0; easing.type: Easing.OutCubic }

    // details follow the open item, a moment after a swipe settles
    Timer { id: infoWait; interval: 250; onTriggered: if (S.showInfo && list.currentItem) S.loadInfo(list.currentItem.filePath) }

    Connections {
        target: S
        function onShowInfoChanged() { infoWait.restart(); }
        function onCurrentChanged() {
            if (S.current < 0) {
                root.closing(root.last);
                grow.stop();
                grow.to = 0;
                grow.duration = S.anim ? 240 : 0;
                grow.start();
                return;
            }
            if (list.currentIndex !== S.current) {
                list.currentIndex = S.current;
                list.positionViewAtIndex(S.current, ListView.Beginning);
            }
            if (strip.currentIndex !== S.current)
                strip.positionViewAtIndex(S.current, ListView.Center);
            if (root.last < 0 || root.t < 1) {
                grow.stop();
                grow.to = 1;
                grow.duration = S.anim ? 300 : 0;
                grow.start();
            }
            root.last = S.current;
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        model: S.photos
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        highlightMoveDuration: 0
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: Math.max(0, width)
        interactive: !(currentItem && currentItem.zoomed)
        onCurrentIndexChanged: {
            del.armed = false;
            infoWait.restart();
            if (S.current >= 0 && currentIndex >= 0)
                S.current = currentIndex;
        }

        delegate: Flickable {
            id: fl
            required property int index
            required property url fileUrl
            required property string fileName
            required property string filePath
            required property var fileModified
            readonly property bool isClip: S.isClip(fileName)
            readonly property string thumb: S.thumbOf(fileName, fileModified)
            readonly property string poster: S.posterOf(fileName, fileModified)
            readonly property bool zoomed: contentWidth > width * 1.01
            readonly property bool near: Math.abs(index - list.currentIndex) <= 1 && root.visible
            width: list.width
            height: list.height
            contentWidth: width
            contentHeight: height
            interactive: zoomed
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            onNearChanged: if (!near) resizeContent(width, height, Qt.point(0, 0))
            function zoomTo(w, at) {
                resizeContent(Math.max(width, Math.min(width * 6, w)), Math.max(width, Math.min(width * 6, w)) * height / width, at);
                returnToBounds();
            }

            PinchArea {
                width: Math.max(fl.contentWidth, fl.width)
                height: Math.max(fl.contentHeight, fl.height)
                property real startW: 0
                onPinchStarted: startW = fl.contentWidth
                onPinchUpdated: pinch => {
                    fl.contentX += pinch.previousCenter.x - pinch.center.x;
                    fl.contentY += pinch.previousCenter.y - pinch.center.y;
                    fl.resizeContent(Math.max(fl.width * 0.8, Math.min(fl.width * 6, startW * pinch.scale)),
                        Math.max(fl.width * 0.8, Math.min(fl.width * 6, startW * pinch.scale)) * fl.height / fl.width, pinch.center);
                }
                onPinchFinished: fl.zoomTo(fl.contentWidth, Qt.point(fl.contentX + fl.width / 2, fl.contentY + fl.height / 2))

                // the grid's small copy shows at once, the big one replaces it when decoded
                Image {
                    anchors.fill: parent
                    source: !fl.near ? "" : fl.isClip ? (S.hasThumb(fl.poster) ? "file://" + fl.poster : "")
                        : (full.status !== Image.Ready && S.hasThumb(fl.thumb) ? "file://" + fl.thumb : "")
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                Image {
                    id: full
                    anchors.fill: parent
                    source: fl.near && !fl.isClip ? fl.fileUrl : ""
                    // shortcut: capped at 2400 px, a deep zoom on a 50 MP photo is soft; load a crop at full size if that matters
                    sourceSize: Qt.size(2400, 2400)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    autoTransform: true
                    cache: false
                }
                // a clip waits behind a thin play mark
                LineIcon {
                    visible: fl.isClip
                    anchors.centerIn: parent
                    name: "play"
                    size: 72
                    color: "#f5f5f5"
                    opacity: 0.92
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: fl.isClip ? Quickshell.execDetached([Quickshell.shellPath("phonegallery-play"), fl.filePath]) : single.restart()
                    onDoubleClicked: mouse => {
                        if (fl.isClip)
                            return;
                        single.stop();
                        fl.zoomTo(fl.zoomed ? fl.width : fl.width * 2.5, Qt.point(mouse.x, mouse.y));
                    }
                    Timer { id: single; interval: 250; onTriggered: S.bars = !S.bars }
                }
            }
        }
    }

    // ---- top: back chevron, the day and time, where in the roll; nothing behind them but a soft scrim
    Rectangle {
        id: top
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 112
        opacity: S.bars ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { enabled: S.anim; NumberAnimation { duration: 180 } }
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.62) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
        }
        Item {
            id: backBtn
            x: 8; y: 6; width: 56; height: 56
            LineIcon { anchors.centerIn: parent; name: "back"; opacity: backTap.pressed ? 0.5 : 1 }
            MouseArea { id: backTap; anchors.fill: parent; onClicked: S.back() }
        }
        Column {
            anchors { left: backBtn.right; right: sendBtn.left; verticalCenter: backBtn.verticalCenter }
            spacing: 1
            T {
                width: parent.width
                text: list.currentItem ? Qt.formatDateTime(list.currentItem.fileModified, "d MMMM yyyy") : ""
                font.pixelSize: 16
                font.weight: Font.Light
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }
            T {
                width: parent.width
                text: list.currentItem ? Qt.formatDateTime(list.currentItem.fileModified, "HH:mm") + "   " + (list.currentIndex + 1) + " / " + S.photos.count : ""
                color: S.grey
                font.pixelSize: 12
                font.weight: Font.Light
                wrapMode: Text.NoWrap
            }
        }
        Item {
            id: sendBtn
            anchors { right: infoBtn.left }
            y: 6; width: 56; height: 56
            LineIcon { anchors.centerIn: parent; name: "send"; opacity: sendTap.pressed ? 0.5 : 1 }
            MouseArea { id: sendTap; anchors.fill: parent; onClicked: if (list.currentItem) S.sendFiles([list.currentItem.filePath]) }
        }
        Item {
            id: infoBtn
            anchors { right: parent.right; rightMargin: 8 }
            y: 6; width: 56; height: 56
            LineIcon { anchors.centerIn: parent; name: "info"; color: S.showInfo ? S.accent : S.white; opacity: infoTap.pressed ? 0.5 : 1 }
            MouseArea { id: infoTap; anchors.fill: parent; onClicked: S.setInfo(!S.showInfo) }
        }
    }

    // ---- bottom: the roll as a strip, delete; they ride above the sheet when it is open
    Rectangle {
        id: bottom
        anchors { bottom: sheet.top; left: parent.left; right: parent.right }
        height: 140
        opacity: S.bars ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { enabled: S.anim; NumberAnimation { duration: 180 } }
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.68) }
        }
        // the whole roll as a strip: drag it to scrub, tap a frame to jump there
        ListView {
            id: strip
            anchors { left: parent.left; right: parent.right; leftMargin: 64; rightMargin: 64; verticalCenter: del.verticalCenter }
            height: 52
            visible: !del.armed
            clip: true
            model: S.photos
            orientation: ListView.Horizontal
            spacing: 3
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: width / 2 - 17
            preferredHighlightEnd: width / 2 + 17
            highlightMoveDuration: S.anim ? 160 : 0
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 400
            onCurrentIndexChanged: if (S.current >= 0 && currentIndex >= 0 && currentIndex !== S.current) S.current = currentIndex
            delegate: Item {
                id: sc
                required property int index
                required property string fileName
                required property var fileModified
                readonly property bool cur: index === strip.currentIndex
                width: 34
                height: 52
                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: S.surface
                    clip: true
                    scale: sc.cur ? 1 : 0.82
                    opacity: sc.cur ? 1 : 0.62
                    Behavior on scale { enabled: S.anim; NumberAnimation { duration: 140 } }
                    Image {
                        anchors.fill: parent
                        source: S.hasThumb(S.thumbOf(sc.fileName, sc.fileModified)) ? "file://" + S.thumbOf(sc.fileName, sc.fileModified) : ""
                        sourceSize: Qt.size(96, 96)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: strip.currentIndex = sc.index }
            }
        }
        Item {
            id: del
            property bool armed: false
            Connections { target: S; function onLastLinkChanged() { if (S.lastLink) del.armed = true; } }
            anchors { right: parent.right; rightMargin: 8; bottom: parent.bottom; bottomMargin: 26 }
            width: armed ? 56 + ask.implicitWidth + 4 : 56
            height: 56
            Timer { running: del.armed; interval: 3000; onTriggered: del.armed = false }
            T {
                id: ask
                anchors { right: trashIcon.left; verticalCenter: parent.verticalCenter }
                visible: del.armed
                text: S.lastLink ? "Last copy. Delete?" : "Delete?"
                color: S.accent
                font.pixelSize: 14
                wrapMode: Text.NoWrap
            }
            LineIcon {
                id: trashIcon
                anchors { right: parent.right; rightMargin: 15; verticalCenter: parent.verticalCenter }
                name: "trash"
                color: del.armed ? S.accent : S.white
                opacity: delTap.pressed ? 0.5 : 1
            }
            MouseArea {
                id: delTap
                anchors.fill: parent
                onClicked: {
                    if (!del.armed) { del.armed = true; return; }
                    del.armed = false;
                    S.remove(list.currentIndex, S.lastLink);
                }
            }
        }
    }

    // ---- the details sheet: slides up from the bottom, drag it down to put it away
    Rectangle {
        id: sheet
        anchors { left: parent.left; right: parent.right }
        y: S.showInfo ? parent.height - height : parent.height
        height: Math.min(parent.height * 0.55, body.implicitHeight + 56)
        radius: 28
        color: S.surface
        Behavior on y { enabled: S.anim; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        // squares off the bottom corners so the sheet meets the screen edge
        Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 28; color: parent.color }
        Rectangle { id: grab; anchors { top: parent.top; topMargin: 10; horizontalCenter: parent.horizontalCenter } width: 40; height: 4; radius: 2; color: S.grey; opacity: 0.6 }
        MouseArea {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 44
            property real from: 0
            onPressed: mouse => from = mouse.y
            onReleased: mouse => { if (mouse.y - from > 24) S.setInfo(false); }
            onClicked: S.setInfo(false)
        }
        Flickable {
            anchors { fill: parent; topMargin: 28; leftMargin: 20; rightMargin: 20; bottomMargin: 16 }
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: body
                width: parent.width
                spacing: 12
                T {
                    text: list.currentItem ? Qt.formatDateTime(list.currentItem.fileModified, "dddd") : ""
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    wrapMode: Text.NoWrap
                }
                T {
                    topPadding: -8
                    text: list.currentItem ? Qt.formatDateTime(list.currentItem.fileModified, "d MMMM yyyy  ·  HH:mm:ss") : ""
                    color: S.grey
                    font.pixelSize: 14
                    wrapMode: Text.NoWrap
                }
                // facts as small cards, two to a line
                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: S.details.filter(d => d[0] !== "File" && d[0] !== "Date")
                        delegate: Rectangle {
                            required property var modelData
                            width: (body.width - 8) / 2
                            height: card.implicitHeight + 24
                            radius: 16
                            color: S.press
                            Column {
                                id: card
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                                spacing: 6
                                DotText { text: String(parent.parent.modelData[0]).toUpperCase(); color: S.grey; px: 1.4; gap: 0.8 }
                                T { width: parent.width; text: parent.parent.modelData[1] || ""; font.pixelSize: 15; wrapMode: Text.Wrap }
                            }
                        }
                    }
                }
                Rectangle {
                    visible: S.details.length > 0
                    width: parent.width
                    height: nameCard.implicitHeight + 24
                    radius: 16
                    color: S.press
                    Column {
                        id: nameCard
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                        spacing: 6
                        DotText { text: "NAME"; color: S.grey; px: 1.4; gap: 0.8 }
                        T { width: parent.width; text: S.details.length ? S.details[0][1] : ""; font.pixelSize: 15; wrapMode: Text.WrapAnywhere }
                    }
                }
            }
        }
    }
}
