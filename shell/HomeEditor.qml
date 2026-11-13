import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// the editor of the home screens; exists only while open
// it opens out of home: a copy of home shrinks into the current card while the rest rises in
PanelWindow {
    id: win

    // 0 is home, 1 is the editor
    property real t: 0
    property bool leaving: false

    anchors { top: true; bottom: true; left: true; right: true }
    color: Phone.bg
    exclusionMode: ExclusionMode.Ignore
    // closing lets a touch through to home
    mask: Region { width: win.leaving ? 0 : win.width; height: win.leaving ? 0 : win.height }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "phone-screens"
    WlrLayershell.keyboardFocus: win.leaving ? WlrKeyboardFocus.None : WlrKeyboardFocus.OnDemand

    // the compositor's own switches: animations, and animation_duration as the speed
    FileView {
        id: cfg
        path: Phone.configDir + "/config.conf"
        blockLoading: true
        printErrors: false
    }
    readonly property int dur: {
        let d = 200, on = true;
        for (const line of cfg.text().split("\n")) {
            const m = line.match(/^\s*(animations|animation_duration)\s*=\s*(\S+)/);
            if (m && m[1] === "animations")
                on = m[2] === "true" || m[2] === "1";
            else if (m)
                d = parseInt(m[2]) || 0;
        }
        return on && Phone.animationsConf !== "off" ? Math.max(0, Math.round(d * 1.4)) : 0;
    }

    function go(to) {
        grow.stop();
        if (dur <= 0 || t === to) {
            t = to;
            settled();
            return;
        }
        grow.from = t;
        grow.to = to;
        grow.duration = Math.max(1, Math.round(dur * Math.abs(to - t)));
        grow.start();
    }
    function settled() { if (leaving && t === 0) Screens.editing = false; }
    function leave() {
        if (leaving)
            return;
        leaving = true;
        go(0);
    }
    NumberAnimation {
        id: grow
        target: win
        property: "t"
        easing.type: Easing.OutCubic
        onFinished: win.settled()
    }
    Component.onCompleted: go(1)
    Connections {
        target: Screens
        function onReopened() {
            if (win.leaving) {
                win.leaving = false;
                win.go(1);
            }
        }
    }

    ScreenEditor {
        id: ed
        anchors.fill: parent
        color: "transparent"
        opacity: win.t
        transform: Translate { y: (1 - win.t) * 64 }
        onClosed: win.leave()
    }

    // home, drawn as the cards draw it, from full screen to the card's place
    readonly property real s: 1 + (ed.cardScale - 1) * t
    Item {
        id: copy
        visible: win.t < 1
        x: (win.width - ed.cardW) / 2 * win.t
        y: (Status.barHeight + 44) * win.t
        width: win.width
        height: win.height
        scale: win.s
        transformOrigin: Item.TopLeft
        Image {
            anchors.fill: parent
            visible: source != ""
            source: {
                const w = Screens.wallpaperOf("home", Screens.active("home"));
                return w ? "file://" + w : "";
            }
            sourceSize: Qt.size(win.width, win.height)
            fillMode: Image.PreserveAspectCrop
        }
        ScreenWidgets {
            anchors.fill: parent
            preview: true
            screenIndex: Screens.active("home")
        }
    }
    // the corners, as on the cards
    Rectangle {
        visible: copy.visible
        x: copy.x - 13
        y: copy.y - 13
        width: win.width * win.s + 26
        height: win.height * win.s + 26
        radius: 28 * win.t + 13
        color: "transparent"
        border.color: Phone.bg
        border.width: 13
    }
    Rectangle {
        visible: copy.visible
        x: copy.x
        y: copy.y
        width: win.width * win.s
        height: win.height * win.s
        radius: 28 * win.t
        color: "transparent"
        border.color: Phone.accent
        border.width: 2
        opacity: win.t
    }
}
