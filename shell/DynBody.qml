import Quickshell
import QtQuick

// the expanded card's content; the shape around it measures its height from here
Item {
    id: root

    property var owner: null
    readonly property var i: Dyn.main || Dyn.lastMain
    readonly property string kind: i ? i.kind : ""
    readonly property real bodyHeight: main.item ? main.item.implicitHeight + 16 : 80
    implicitHeight: Dyn.headH + bodyHeight

    // the strip beside the camera: a label on the side that has room
    Item {
        id: strip
        width: parent.width
        height: Dyn.headH
        readonly property real holeL: Dyn.holeKnown ? Dyn.hx - 8 - Dyn.margin - 8 : width
        readonly property real holeR: Dyn.holeKnown ? Dyn.hx + Dyn.hd - 8 + Dyn.margin + 8 : 0
        readonly property real start: Dyn.side === "left" ? holeR : 18
        readonly property real end: Dyn.side === "left" ? width - 18 : Dyn.side === "right" ? holeL : (Dyn.holeKnown ? holeL : width - 18)
        Text {
            x: strip.start
            width: Math.max(0, strip.end - strip.start)
            anchors.verticalCenter: parent.verticalCenter
            text: root.i ? root.i.head || "" : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Phone.grey
            font.family: Phone.font
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }

    Loader {
        id: main
        y: strip.height
        x: 18
        width: parent.width - 36
        sourceComponent: root.kind === "music" ? musicBody : root.kind === "call" ? callBody : plainBody
    }

    component Key: Item {
        id: key
        property string icon: ""
        property string label: ""
        property color fill: "transparent"
        property color tint: Phone.white
        property bool can: true
        property real diameter: 44
        signal tapped()
        width: diameter
        height: diameter + (label !== "" ? 20 : 0)
        opacity: can ? 1 : 0.3
        Rectangle {
            width: key.diameter
            height: key.diameter
            radius: key.diameter / 2
            color: key.fill
            scale: tap.pressed ? 0.9 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }
            Icon {
                anchors.centerIn: parent
                name: key.icon
                size: key.diameter * 0.46
                color: key.tint
            }
        }
        Text {
            visible: key.label !== ""
            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
            text: key.label
            textFormat: Text.PlainText
            color: Phone.grey
            font.family: Phone.font
            font.pixelSize: 12
        }
        MouseArea {
            id: tap
            anchors.fill: parent
            enabled: key.can
            preventStealing: true
            onClicked: key.tapped()
        }
    }
    component Line: Text {
        width: parent ? parent.width : 0
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
        color: Phone.white
        font.family: Phone.font
        font.pixelSize: 15
    }

    Component {
        id: musicBody
        Column {
            id: music
            spacing: 6
            readonly property var p: Dyn.player
            Timer {
                interval: 1000
                repeat: true
                running: music.p !== null && music.p.isPlaying
                onTriggered: music.p.positionChanged()
            }
            Item {
                width: parent.width
                height: 60
                Rectangle {
                    id: cover
                    width: 60
                    height: 60
                    // concentric with the card: its 28 radius less the 18 inset
                    radius: 10
                    color: Phone.surface
                    Icon { anchors.centerIn: parent; visible: art.status !== Image.Ready; name: "music"; size: 24; color: Phone.grey }
                    Image {
                        id: art
                        anchors.fill: parent
                        source: root.i && root.i.art ? root.i.art : ""
                        sourceSize: Qt.size(180, 180)
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                    }
                    // the card is pure black: a black ring rounds the art without a shader
                    Rectangle {
                        anchors { fill: parent; margins: -6 }
                        radius: 16
                        color: "transparent"
                        border { width: 6; color: "#000000" }
                    }
                }
                Column {
                    anchors { left: cover.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 2
                    Line {
                        text: root.i ? root.i.title : ""
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }
                    Line {
                        visible: text !== ""
                        text: root.i ? root.i.sub || "" : ""
                        color: Phone.grey
                        font.pixelSize: 14
                    }
                }
            }
            // a long track bar has a tall target: the finger hides what it touches
            Item {
                id: seek
                visible: music.p !== null && music.p.lengthSupported && music.p.length > 0
                width: parent.width
                height: 44
                readonly property real fraction: !visible ? 0 : Math.max(0, Math.min(1, area.pressed ? area.at : music.p.position / music.p.length))
                Rectangle {
                    y: 12
                    width: parent.width
                    height: 4
                    radius: 2
                    color: "#333333"
                    Rectangle { width: parent.width * seek.fraction; height: 4; radius: 2; color: Phone.white }
                }
                Text {
                    y: 22
                    text: music.p ? Dyn.clock(seek.fraction * music.p.length * 1000) : ""
                    color: Phone.grey
                    font.family: Phone.font
                    font.pixelSize: 12
                    font.features: { "tnum": 1 }
                }
                Text {
                    y: 22
                    anchors.right: parent.right
                    text: music.p ? Dyn.clock(music.p.length * 1000) : ""
                    color: Phone.grey
                    font.family: Phone.font
                    font.pixelSize: 12
                    font.features: { "tnum": 1 }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    enabled: music.p !== null && music.p.canSeek
                    preventStealing: true
                    readonly property real at: Math.max(0, Math.min(1, mouseX / width))
                    onReleased: music.p.position = at * music.p.length
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18
                Key { icon: "prev"; can: !!music.p && music.p.canGoPrevious; onTapped: music.p.previous() }
                Key {
                    icon: music.p && music.p.isPlaying ? "pause" : "play"
                    fill: Phone.white
                    tint: Phone.black
                    diameter: 52
                    can: !!music.p && music.p.canTogglePlaying
                    onTapped: music.p.togglePlaying()
                }
                Key { icon: "next"; can: !!music.p && music.p.canGoNext; onTapped: music.p.next() }
            }
            // shortcut: a tap goes to the next output, the panel has the full list; add a list if three or more are common
            Loader {
                id: outputs
                width: parent.width
                active: true
                sourceComponent: Item {
                    width: parent ? parent.width : 0
                    height: model.sinks.length > 1 ? 44 : 0
                    visible: height > 0
                    QuickModel { id: model }
                    Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: "output"; size: 16; color: Phone.grey }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, outputs.width - 40)
                            text: (model.sinks.find(s => s.active) || { name: "" }).name
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Phone.grey
                            font.family: Phone.font
                            font.pixelSize: 13
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        preventStealing: true
                        onClicked: {
                            const all = model.sinks;
                            const at = all.findIndex(s => s.active);
                            model.setSink(all[(at + 1) % all.length].id);
                        }
                    }
                }
            }
        }
    }

    Component {
        id: callBody
        Column {
            spacing: 14
            readonly property bool incoming: root.i && root.i.state === "incoming"
            Column {
                width: parent.width
                spacing: 2
                Line {
                    text: root.i ? root.i.title : ""
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
                Line {
                    visible: text !== ""
                    text: root.i ? root.i.tail || "" : ""
                    color: Phone.grey
                    font.pixelSize: 14
                    font.features: { "tnum": 1 }
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 56
                visible: parent.incoming
                Key { icon: "hangup"; label: "Decline"; fill: "#e5383b"; diameter: 56; onTapped: Dyn.press(root.i, "decline") }
                Key { icon: "phone"; label: "Answer"; fill: "#2fb54a"; diameter: 56; onTapped: Dyn.press(root.i, "answer") }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 30
                visible: !parent.incoming
                Key {
                    icon: root.i && root.i.muted ? "micoff" : "mic"
                    label: "Mute"
                    fill: root.i && root.i.muted ? Phone.white : Phone.surface
                    tint: root.i && root.i.muted ? Phone.black : Phone.white
                    diameter: 56
                    onTapped: Dyn.press(root.i, "mute")
                }
                Key {
                    icon: "speaker"
                    label: "Speaker"
                    fill: root.i && root.i.speaker ? Phone.white : Phone.surface
                    tint: root.i && root.i.speaker ? Phone.black : Phone.white
                    diameter: 56
                    onTapped: Dyn.press(root.i, "speaker")
                }
                Key { icon: "hangup"; label: "End"; fill: "#e5383b"; diameter: 56; onTapped: Dyn.press(root.i, "hangup") }
            }
        }
    }

    Component {
        id: plainBody
        Column {
            spacing: 10
            Row {
                width: parent.width
                spacing: 12
                Icon {
                    id: big
                    anchors.verticalCenter: parent.verticalCenter
                    visible: name !== "" && root.i && root.i.notif === undefined
                    name: root.i && root.i.notif === undefined && /^[a-z]+$/.test(root.i.icon || "") ? root.i.icon : ""
                    size: 28
                    color: root.i && root.i.tone === "red" ? "#ff5c5c" : root.i && root.i.tone === "green" ? "#4cd964" : Phone.white
                }
                Column {
                    width: parent.width - (big.visible ? big.width + 12 : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Line {
                        visible: text !== ""
                        text: root.i ? root.i.title || "" : ""
                        font.pixelSize: root.i && root.i.clock ? 24 : 17
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        visible: text !== ""
                        width: parent.width
                        text: root.i ? root.i.sub || "" : ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        maximumLineCount: 3
                        color: Phone.grey
                        font.family: Phone.font
                        font.pixelSize: 14
                    }
                }
            }
            Rectangle {
                visible: root.i !== null && root.i.progress !== undefined
                width: parent.width
                height: 6
                radius: 3
                color: "#333333"
                Rectangle {
                    width: parent.width * (root.i && root.i.progress !== undefined ? root.i.progress : 0)
                    height: parent.height
                    radius: 3
                    color: root.i && root.i.tone === "green" ? "#4cd964" : root.i && root.i.tone === "red" ? "#ff5c5c" : Phone.white
                }
            }
            Flow {
                visible: root.i !== null && (root.i.buttons || []).length > 0
                width: parent.width
                spacing: 8
                Repeater {
                    model: root.i ? root.i.buttons || [] : []
                    Rectangle {
                        required property var modelData
                        width: Math.max(88, label.implicitWidth + 32)
                        height: 44
                        radius: 22
                        color: modelData.tone === "red" ? "#e5383b" : Phone.surface
                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: parent.modelData.label
                            textFormat: Text.PlainText
                            color: Phone.white
                            font.family: Phone.font
                            font.pixelSize: 15
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            preventStealing: true
                            onClicked: Dyn.press(root.i, parent.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
