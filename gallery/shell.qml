import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel

// a program of its own like settings: the grid of photos, one tapped opens full screen
ShellRoot {
    settings.watchFiles: false

    IpcHandler {
        target: "gallery"
        function open(path: string): void { S.open(path); }
    }

    FloatingWindow {
        title: "Gallery"
        color: S.black
        visible: true
        onClosed: Qt.quit()

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: S.back()

            Item {
                id: head
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 56
                BackBtn { id: backBtn }
                DotText {
                    anchors { left: backBtn.right; verticalCenter: parent.verticalCenter }
                    text: "GALLERY"
                }
                T {
                    anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                    text: S.photos.count || ""
                    color: S.grey
                    font.pixelSize: 15
                }
            }

            GridView {
                id: grid
                anchors { top: head.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
                model: S.photos
                cellWidth: Math.floor(width / 3)
                cellHeight: cellWidth
                cacheBuffer: Math.max(0, height * 2)
                reuseItems: true
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                delegate: Item {
                    id: cell
                    required property int index
                    required property string fileName
                    required property var fileModified
                    readonly property string thumb: S.thumbOf(fileName, fileModified)
                    width: grid.cellWidth
                    height: grid.cellHeight
                    Rectangle {
                        anchors { fill: parent; margins: 1 }
                        color: S.surface
                        Image {
                            anchors.fill: parent
                            source: S.hasThumb(cell.thumb) ? "file://" + cell.thumb : ""
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            clip: true
                            opacity: status === Image.Ready ? (tap.pressed ? 0.7 : 1) : 0
                            Behavior on opacity { enabled: S.anim; NumberAnimation { duration: 120 } }
                        }
                    }
                    MouseArea { id: tap; anchors.fill: parent; onClicked: S.current = cell.index }
                }
            }

            T {
                anchors.centerIn: grid
                visible: S.photos.status === FolderListModel.Ready && S.photos.count === 0
                text: "No photos yet"
                color: S.grey
            }

            Viewer {
                anchors.fill: parent
                onClosing: i => grid.positionViewAtIndex(i, GridView.Contain)
            }
        }
    }
}
