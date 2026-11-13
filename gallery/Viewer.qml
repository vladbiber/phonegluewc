import Quickshell
import QtQuick

// one photo full screen: swipe to the next, pinch or double tap to zoom, tap hides the bars
Rectangle {
    id: root
    signal closing(int index)
    property bool bars: true
    property int last: -1
    color: S.black
    visible: opacity > 0
    opacity: S.current >= 0 ? 1 : 0
    Behavior on opacity { enabled: S.anim; NumberAnimation { duration: 150 } }

    Connections {
        target: S
        function onCurrentChanged() {
            if (S.current < 0) {
                root.closing(root.last);
            } else if (list.currentIndex !== S.current) {
                list.currentIndex = S.current;
                list.positionViewAtIndex(S.current, ListView.Beginning);
            }
            if (S.current >= 0)
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
            readonly property string thumb: S.thumbOf(fileName, fileModified)
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
                    source: fl.near && full.status !== Image.Ready && S.hasThumb(fl.thumb) ? "file://" + fl.thumb : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
                Image {
                    id: full
                    anchors.fill: parent
                    source: fl.near && !/\.mp4$/i.test(fl.fileName) ? fl.fileUrl : ""
                    // shortcut: capped at 2400 px, a deep zoom on a 50 MP photo is soft; load a crop at full size if that matters
                    sourceSize: Qt.size(2400, 2400)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    autoTransform: true
                    cache: false
                }
                MouseArea {
                    anchors.fill: parent
                    // a clip shows its thumbnail (play mark and length are in it); a tap plays it
                    onClicked: /\.mp4$/i.test(fl.fileName)
                        ? Quickshell.execDetached([Quickshell.shellPath("phonegallery-play"), fl.filePath])
                        : single.restart()
                    onDoubleClicked: mouse => {
                        single.stop();
                        fl.zoomTo(fl.zoomed ? fl.width : fl.width * 2.5, Qt.point(mouse.x, mouse.y));
                    }
                    Timer { id: single; interval: 250; onTriggered: root.bars = !root.bars }
                }
            }
        }
    }

    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 56
        color: Qt.rgba(S.black.r, S.black.g, S.black.b, 0.7)
        opacity: root.bars ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { enabled: S.anim; NumberAnimation { duration: 150 } }
        BackBtn { id: back }
        T {
            anchors { left: back.right; right: count.left; verticalCenter: parent.verticalCenter }
            text: list.currentItem ? Qt.formatDateTime(list.currentItem.fileModified, "d MMM yyyy, HH:mm") : ""
            font.pixelSize: 15
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
        }
        T {
            id: count
            anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
            text: (list.currentIndex + 1) + " / " + S.photos.count
            color: S.grey
            font.pixelSize: 15
        }
    }

    Rectangle {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: 80
        color: Qt.rgba(S.black.r, S.black.g, S.black.b, 0.7)
        opacity: root.bars ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { enabled: S.anim; NumberAnimation { duration: 150 } }
        Btn {
            id: del
            anchors.centerIn: parent
            text: "Delete"
            confirm: true
            onTapped: S.remove(list.currentIndex)
        }
    }
}
