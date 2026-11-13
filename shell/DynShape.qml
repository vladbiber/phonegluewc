import Quickshell
import QtQuick
import "Icons.js" as Icons

// the one black shape: pill, expanded card and bubble, all from Dyn's springs
Item {
    id: root

    property bool inLock: false
    readonly property alias pillItem: pill
    readonly property alias bubbleItem: bubble
    readonly property var it: Dyn.main || Dyn.lastMain
    readonly property var other: Dyn.bubble || Dyn.lastBubble
    readonly property bool live: !Dyn.idle || Dyn.moving
    property bool bodyOn: false
    Connections {
        target: Dyn
        function onOpenChanged() { root.bodyOn = Dyn.open || Dyn.moving; }
        function onMovingChanged() { root.bodyOn = Dyn.open || Dyn.moving && root.bodyOn; }
    }
    function clamp01(v) { return Math.max(0, Math.min(1, v)); }
    function toneOf(t) { return t === "red" ? "#ff5c5c" : t === "green" ? "#4cd964" : Phone.white; }

    // tap outside on the lock screen; outside it the scrim window does this
    MouseArea {
        anchors.fill: parent
        enabled: root.inLock && Dyn.open
        visible: enabled
        onPressed: Dyn.collapse()
    }

    Item {
        id: all
        anchors.fill: parent
        // the finger stays on the pill after it fades, or the pull is cancelled
        visible: root.live && (opacity > 0 || gesture.pressed)
        // the sheet comes down from under it
        opacity: (1 - root.clamp01(Status.pull * 12)) * Dyn.fullFade

        // the short neck while the bubble leaves or joins the pill: plain black, no shader needed
        Rectangle {
            readonly property real side: Dyn.side === "right" ? -1 : 1
            readonly property real gap: Dyn.side === "right" ? pill.x - (bubble.x + bubble.width) : bubble.x - (pill.x + pill.width)
            visible: bubble.visible && gap > -Dyn.pillH / 2 && gap < 6 && height > 1
            x: Dyn.side === "right" ? bubble.x + bubble.width - Dyn.pillH / 2 : pill.x + pill.width - Dyn.pillH / 2
            y: Dyn.pillT + (Dyn.pillH - height) / 2
            width: Math.max(0, gap + Dyn.pillH)
            height: Dyn.pillH * Math.max(0, 0.72 - Math.max(0, gap) / 9)
            color: Phone.black
        }

        Rectangle {
            id: bubble
            // rests beside the pill, tucked in behind it while there is none
            readonly property real rest: Dyn.side === "right" ? Dyn.pL - 6 - Dyn.pillH : Dyn.pR + 6
            readonly property real tuck: Dyn.side === "right" ? Dyn.pL : Dyn.pR - Dyn.pillH
            x: tuck + (rest - tuck) * Dyn.pG
            y: Dyn.pillT
            width: Dyn.pillH
            height: Dyn.pillH
            radius: Dyn.pillH / 2
            color: Phone.black
            visible: Dyn.pG > 0.01
            opacity: root.clamp01(Dyn.pG * 3)

            Mark {
                anchors.centerIn: parent
                item: root.other
                size: Math.min(16, Dyn.pillH - 8)
                opacity: root.clamp01((Dyn.pG - 0.4) / 0.6)
            }
            MouseArea {
                anchors.fill: parent
                preventStealing: true
                onReleased: Dyn.swap()
            }
        }

        Rectangle {
            id: pill
            x: Dyn.pL
            y: Dyn.pT
            width: Math.max(0, Dyn.pR - Dyn.pL)
            height: Math.max(0, Dyn.shapeH)
            radius: Dyn.radius
            color: Phone.black
            clip: true
            // pure black open on a black screen would have no edge
            border.width: Dyn.openness > 0.01 ? 1 : 0
            border.color: Qt.rgba(1, 1, 1, 0.14 * Dyn.openness)

            MouseArea {
                id: gesture
                anchors.fill: parent
                enabled: root.live
                preventStealing: true
                property real sx: 0
                property real sy: 0
                property real lastY: 0
                property real lastT: 0
                property real vy: 0
                property string mode: ""
                property bool fired: false
                function at(mouse) { return mapToItem(root, mouse.x, mouse.y); }
                function finish() {
                    Dyn.held = false;
                    Dyn.dragUp = 0;
                    Dyn.swipeX = 0;
                    Status.barHeld = false;
                    hold.stop();
                    mode = "";
                }
                Timer {
                    id: hold
                    interval: 450
                    onTriggered: {
                        gesture.fired = true;
                        Dyn.openApp();
                    }
                }
                onPressed: mouse => {
                    const p = at(mouse);
                    sx = p.x;
                    sy = lastY = p.y;
                    lastT = Date.now();
                    vy = 0;
                    fired = false;
                    mode = "";
                    Dyn.held = true;
                    if (!Phone.lockOpen)
                        hold.restart();
                }
                onPositionChanged: mouse => {
                    const p = at(mouse);
                    const dx = p.x - sx, dy = p.y - sy, t = Date.now();
                    if (t > lastT) {
                        vy = (p.y - lastY) * 1000 / (t - lastT);
                        lastY = p.y;
                        lastT = t;
                    }
                    if (mode === "" && Math.hypot(dx, dy) > 10) {
                        const down = Math.abs(dy) >= Math.abs(dx);
                        const notif = Dyn.main && Dyn.main.notif;
                        mode = down ? (dy > 0 ? (Phone.lockOpen ? "still" : "pull") : Dyn.open ? "up" : "still")
                            : Dyn.open ? (notif ? "swipe" : "still") : "swap";
                        hold.stop();
                        if (mode === "pull") {
                            Status.barHeld = true;
                            Status.side = sx < root.width / 2 ? 0 : 1;
                            Dyn.collapse();
                        }
                    }
                    if (mode === "pull") {
                        Status.grab();
                        Status.track(dy);
                        Status.pull = Math.max(0.001, Math.min(1, dy / root.height));
                    } else if (mode === "up") {
                        Dyn.dragUp = Math.min(0, dy);
                    } else if (mode === "swipe") {
                        Dyn.swipeX = dx;
                    }
                }
                onReleased: mouse => {
                    const p = at(mouse);
                    const dx = p.x - sx, dy = p.y - sy, m = mode, fast = vy < -500;
                    finish();
                    if (fired)
                        return;
                    if (m === "pull")
                        Status.releasePull(root.height, 0.3);
                    else if (m === "up" && (dy <= -40 || fast))
                        Dyn.collapse();
                    else if (m === "swipe" && Math.abs(dx) > 80)
                        Dyn.dismissPop();
                    else if (m === "swap" && Math.abs(dx) > 24)
                        Dyn.swap();
                    else if (m === "")
                        Dyn.open ? Dyn.openApp() : Dyn.expand();
                }
                onCanceled: {
                    const m = mode;
                    finish();
                    if (m === "pull")
                        Status.settleTo(0);
                }
            }

            // ---- compact: lead and tail either side of the hole, never over it ----
            Item {
                id: compact
                anchors.fill: parent
                visible: opacity > 0
                // appears as the pill reaches its size, goes first when it closes or opens
                readonly property real wide: Dyn.compactR - Dyn.compactL - Dyn.pillH
                readonly property real grown: wide < 1 ? 1 : root.clamp01(((pill.width - Dyn.pillH) / wide - 0.45) / 0.55)
                opacity: root.clamp01(1 - Dyn.openness * 4) * (Dyn.idle ? root.clamp01(pill.width / Dyn.pillH - 0.8) * grown : grown) * swapIn.value
                readonly property string mainId: Dyn.main ? Dyn.main.id : ""
                onMainIdChanged: if (Dyn.anim && mainId !== "" && !Dyn.idle) swapFade.restart()
                QtObject { id: swapIn; property real value: 1 }
                NumberAnimation { id: swapFade; target: swapIn; property: "value"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }

                readonly property real rowX: Dyn.side === "left" ? Dyn.holeR + Dyn.margin + Dyn.padIn
                    : Dyn.compactL + (Dyn.pillH - leadBox.width) / 2 // at the pill's end: concentric with its cap
                // a time short of room gives up padding before it is cut: down to the lead's inset on both ends
                readonly property real inset: (Dyn.pillH - 18) / 2
                readonly property bool tight: Dyn.side === "center" && tailBox.clock && tailBox.want > Dyn.compactR - Dyn.padEnd - (Dyn.holeR + Dyn.margin + Dyn.padIn)
                readonly property real tailX: Dyn.side === "center" ? Dyn.holeR + Dyn.margin + (tight ? inset : Dyn.padIn) : rowX + leadBox.width + (tailBox.tailKind === "" ? 0 : 6)
                readonly property real tailEnd: Dyn.side === "right" ? Dyn.holeL - Dyn.margin - Dyn.padIn : Dyn.compactR - (tight ? inset : Dyn.padEnd)

                Binding { target: Dyn; property: "leadW"; value: leadBox.width }
                Binding { target: Dyn; property: "tailW"; value: tailBox.want }
                // what a time needs beyond the normal pads once they shrink to the inset
                Binding { target: Dyn; property: "keepW"; value: Dyn.side === "center" && tailBox.clock ? Math.max(0, tailBox.want - (Dyn.padIn - compact.inset) - (Dyn.padEnd - compact.inset)) : 0 }
                Binding { target: Dyn; property: "rowW"; value: leadBox.width + (tailBox.want > 0 ? 6 + tailBox.want : 0) }

                Item {
                    id: leadBox
                    x: compact.rowX - pill.x
                    width: 18
                    height: parent.height
                    Mark {
                        anchors.centerIn: parent
                        item: root.it
                        size: 18
                    }
                }
                Item {
                    id: tailBox
                    readonly property var i: root.it
                    readonly property string tailKind: !i ? "" : i.bars ? "bars" : i.tail || (i.kind === "event" && i.progress === undefined || i.kind === "live" || i.kind === "nav" || i.kind === "transfer") && i.title ? "text" : i.progress !== undefined ? "bar" : ""
                    readonly property string words: !i ? "" : i.tail || i.title || ""
                    readonly property bool clock: tailKind === "text" && /^\d+(:\d\d)+$/.test(words)
                    readonly property real want: tailKind === "bars" ? 18 : tailKind === "bar" ? 46 : tailKind === "text" ? Math.min(150, tailMetrics.advanceWidth + 1) : 0
                    x: compact.tailX - pill.x
                    width: Math.max(0, compact.tailEnd - compact.tailX)
                    height: parent.height
                    visible: width >= 14

                    // its own measure: the text's width depends on the pill, which depends on this
                    // digits measured as zeros: a running time keeps one width
                    TextMetrics { id: tailMetrics; font: tailText.font; text: tailBox.words.replace(/[0-9]/g, "0") }
                    Text {
                        id: tailText
                        visible: tailBox.tailKind === "text"
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        text: tailBox.words
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: tailBox.i ? root.toneOf(tailBox.i.tone) : Phone.white
                        font.family: Phone.font
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                    Bars {
                        visible: tailBox.tailKind === "bars"
                        anchors.verticalCenter: parent.verticalCenter
                        run: Dyn.barsRun && !Dyn.open && compact.opacity > 0
                    }
                    Rectangle {
                        visible: tailBox.tailKind === "bar"
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(parent.width, 46)
                        height: 4
                        radius: 2
                        color: "#333333"
                        Rectangle {
                            width: parent.width * root.clamp01(tailBox.i && tailBox.i.progress !== undefined ? tailBox.i.progress : 0)
                            height: parent.height
                            radius: 2
                            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            color: tailBox.i ? root.toneOf(tailBox.i.tone) : Phone.white
                        }
                    }
                }
            }

            // ---- expanded: loaded when asked for, fades in once the shape has room ----
            Loader {
                id: body
                // not from openness: the body's height feeds back into it
                active: root.bodyOn
                width: Dyn.sw - 16
                x: 8 - pill.x
                y: Dyn.openT - pill.y
                readonly property real shownIn: root.clamp01((Dyn.openness - 0.45) / 0.55)
                opacity: shownIn
                scale: 0.94 + 0.06 * shownIn
                transformOrigin: Item.Top
                source: "DynBody.qml"
                onLoaded: item.owner = root
            }
            Binding { target: Dyn; property: "bodyH"; value: body.item ? body.item.bodyHeight : 120; when: body.status === Loader.Ready }
        }
    }

    // the laptop has no hole: this one stands in for it and shows through everything
    Rectangle {
        visible: Dyn.fake
        x: Dyn.hx
        y: Dyn.hy
        width: Dyn.hd
        height: Dyn.hd
        radius: Dyn.hd / 2
        color: Phone.black
    }

    // an activity's picture: cover art, its own icon, or an app's
    component Mark: Item {
        id: mark
        property var item: null
        property real size: 18
        width: size
        height: size
        readonly property string name: item && item.icon ? item.icon : ""
        readonly property bool drawn: Icons.has(name)
        Image {
            id: art
            anchors.fill: parent
            visible: status === Image.Ready
            source: mark.item && mark.item.art ? mark.item.art : ""
            sourceSize: Qt.size(96, 96)
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            // the pill is pure black: a black ring cuts the art to a circle, concentric with the pill's cap, without a shader
            // 4 covers the square's corners (0.42 of the radius) and stays inside the pill's 4.5 inset
            Rectangle {
                anchors { fill: parent; margins: -4 }
                radius: width / 2
                color: "transparent"
                border { width: 4; color: "#000000" }
            }
        }
        Icon {
            visible: !art.visible && mark.drawn
            anchors.centerIn: parent
            name: mark.drawn ? mark.name : ""
            size: mark.size
            color: mark.item ? root.toneOf(mark.item.tone) : Phone.white
        }
        Loader {
            active: !art.visible && !mark.drawn && mark.name !== ""
            anchors.fill: parent
            sourceComponent: AppIcon {
                size: mark.size
                entry: ({ name: mark.item ? mark.item.head || mark.item.title || "?" : "?", icon: mark.name })
            }
        }
    }
    // four bars of a dot matrix: steps, not a smooth 60 fps redraw
    component Bars: Row {
        id: bars
        property bool run: false
        property int beat: 0
        spacing: 2
        height: 14
        Timer { interval: 125; repeat: true; running: bars.run; onTriggered: bars.beat++ }
        Repeater {
            model: 4
            Rectangle {
                required property int index
                anchors.bottom: parent.bottom
                width: 3
                radius: 1.5
                color: Phone.white
                height: bars.run ? 3 + (Math.abs(Math.sin((bars.beat + 1) * (index * 0.9 + 1.3))) * 11) : 3
            }
        }
    }
}
