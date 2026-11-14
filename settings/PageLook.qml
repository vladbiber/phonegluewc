import QtQuick
import Quickshell

Page {
    id: root
    property var images: []
    property bool listed: false
    readonly property string current: S.phone.wallpaper ?? Quickshell.shellDir.replace(/\/[^/]*\/?$/, "") + "/wallpapers/06-ribbons-dark.jpg"
    Cmd {
        running: true
        command: [S.pset, "images"]
        onDone: { root.images = S.lines(out); root.listed = true; }
    }

    Section { text: "Theme" }
    Chips {
        options: [{ value: "dark", label: "Dark" }, { value: "light", label: "Light" }]
        current: S.light ? "light" : "dark"
        onPicked: v => S.save(["set", "phone", "theme", v])
    }
    Section { text: "Accent colour" }
    Flow {
        x: S.margin
        width: parent.width - 2 * S.margin
        spacing: 12
        Repeater {
            model: ["#d71921", "#ff7a00", "#e0b000", "#21a366", "#2f7bff", "#a05cff", "#f5f5f5"]
            delegate: Rectangle {
                required property string modelData
                width: 48; height: 48; radius: 24
                // white shows as black on a light page, as the accent does
                color: S.light && modelData === "#f5f5f5" ? "#111111" : modelData
                border.width: 3
                border.color: S.accentSaved === modelData ? S.white : "transparent"
                Rectangle {
                    anchors.centerIn: parent
                    visible: S.accentSaved === parent.modelData
                    width: 12; height: 12; radius: 6
                    color: S.black
                }
                MouseArea { anchors.fill: parent; onClicked: S.save(["set", "phone", "accent", parent.modelData]) }
            }
        }
    }
    Section { text: "Wallpaper" }
    Flow {
        id: grid
        x: S.margin
        width: parent.width - 2 * S.margin
        spacing: 8
        readonly property real tile: (width - 16) / 3
        Rectangle {
            width: grid.tile; height: width * 1.6; radius: 12
            color: S.surface
            border.width: root.current === "" ? 3 : 0
            border.color: S.accent
            T { anchors.centerIn: parent; text: "Black"; font.pixelSize: 15 }
            MouseArea { anchors.fill: parent; onClicked: S.save(["wallpaper", ""]) }
        }
        Repeater {
            model: root.images
            delegate: Rectangle {
                id: tile
                required property string modelData
                width: grid.tile; height: width * 1.6; radius: 12
                color: S.surface
                clip: true
                Image {
                    anchors.fill: parent
                    source: "file://" + encodeURI(tile.modelData).replace(/#/g, "%23").replace(/\?/g, "%3F")
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    sourceSize.width: 220
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: "transparent"
                    border.width: root.current === tile.modelData ? 3 : 0
                    border.color: S.accent
                }
                MouseArea { anchors.fill: parent; onClicked: S.save(["wallpaper", tile.modelData]) }
            }
        }
    }
    Note {
        visible: root.listed && root.images.length === 0
        text: "To offer your own pictures here, put them in the Pictures folder."
    }
}
