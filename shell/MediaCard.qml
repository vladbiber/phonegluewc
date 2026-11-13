import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// what is playing, from whichever player reports it; no player, no card
// shortcut: neutral grey, no tint from the album art; sampling it needs a layer per track, add when art is shown here
Rectangle {
    id: root

    readonly property var player: {
        const all = Mpris.players.values;
        return all.find(p => p.isPlaying) || all[0] || null;
    }
    // a small home widget has room for one line only
    readonly property bool roomy: height >= 110
    readonly property var desktop: player && player.desktopEntry ? DesktopEntries.byId(player.desktopEntry) : null

    visible: player !== null
    height: visible ? 120 : 0
    radius: 32
    color: Phone.mix("#2a2a2a", "#e2e2e2")

    component Key: Item {
        id: key
        property string icon: ""
        property bool big: false
        property bool can: true
        signal tapped()
        width: big ? 48 : 40
        height: 48
        opacity: can ? 1 : 0.3
        Rectangle {
            anchors.centerIn: parent
            width: 48
            height: 48
            visible: key.big
            radius: 24
            color: Phone.fg
            scale: area.pressed ? 0.9 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }
        }
        Icon {
            anchors.centerIn: parent
            name: key.icon
            color: key.big ? Phone.mix("#141414", "#ffffff") : Phone.fg
            size: 22
        }
        MouseArea {
            id: area
            anchors.fill: parent
            enabled: key.can
            onClicked: key.tapped()
        }
    }

    AppIcon {
        x: 16
        y: 14
        visible: root.roomy
        entry: ({ name: root.player ? (root.player.identity || "?") : "?", icon: root.desktop ? root.desktop.icon : "" })
        size: 28
    }
    Rectangle {
        visible: root.roomy && chip.text !== ""
        anchors { right: parent.right; rightMargin: 14; top: parent.top; topMargin: 14 }
        width: Math.min(chip.implicitWidth + 20, root.width * 0.5)
        height: 26
        radius: 13
        color: Phone.mix("#3a3a3a", "#cfcfcf")
        Text {
            id: chip
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            verticalAlignment: Text.AlignVCenter
            text: root.player ? (root.player.identity || "") : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Phone.fg
            font.family: Phone.font
            font.pixelSize: 12
        }
    }
    Column {
        anchors { left: parent.left; right: keys.left; bottom: parent.bottom; leftMargin: 20; rightMargin: 8; bottomMargin: root.roomy ? 16 : (root.height - height) / 2 }
        spacing: 2
        Text {
            width: parent.width
            text: root.player ? (root.player.trackTitle || root.player.identity || "") : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Phone.fg
            font.family: Phone.font
            font.pixelSize: 15
            font.weight: Font.Medium
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: root.player ? (root.player.trackArtist || "") : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Phone.dim
            font.family: Phone.font
            font.pixelSize: 12
        }
    }
    Row {
        id: keys
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 12; bottomMargin: root.roomy ? 12 : (root.height - height) / 2 }
        Key {
            icon: "prev"
            can: !!root.player && root.player.canGoPrevious
            onTapped: root.player.previous()
        }
        Key {
            icon: "next"
            can: !!root.player && root.player.canGoNext
            onTapped: root.player.next()
        }
        Key {
            icon: root.player && root.player.isPlaying ? "pause" : "play"
            big: true
            can: !!root.player && root.player.canTogglePlaying
            onTapped: root.player.togglePlaying()
        }
    }
}
