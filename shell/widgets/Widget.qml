import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import qs
import "look.js" as Look

// one widget in its look, filling the cells it was given; a preview shows the same data and takes no touch
Item {
    id: root

    property var w: ({})
    property bool lock: false
    property bool preview: false
    property bool live: true
    readonly property string look: Screens.styleOf(w)
    // the Apple look turns to glass behind the lock, as iOS draws its lock widgets
    readonly property var pal: Look.of(look, lock && look === "apple")
    readonly property bool dots: pal.dots
    readonly property bool small: w.w === 1
    readonly property bool tall: w.h >= 4

    SystemClock { id: clock; enabled: root.live; precision: SystemClock.Minutes }
    function two(n) { return (n < 10 ? "0" : "") + n; }
    function mmss(ms) {
        const s = Math.max(0, Math.round(ms / 1000));
        return s >= 3600 ? Math.floor(s / 3600) + ":" + two(Math.floor(s / 60) % 60) : two(Math.floor(s / 60)) + ":" + two(s % 60);
    }

    // the shape every widget sits on: a circle for one column, else a rounded card
    component Tile: Rectangle {
        property bool circle: root.small && root.w.h >= 2
        property bool pill: false
        anchors.centerIn: parent
        width: circle ? Math.min(parent.width, parent.height) - 6 : parent.width - 6
        height: circle ? width : parent.height - 6
        radius: circle || pill ? height / 2 : Math.min(width, height) * root.pal.radius
        color: root.pal.tile
    }
    component Label: Text {
        color: root.pal.ink
        font.family: Phone.font
        font.pixelSize: 13
        font.weight: root.dots ? Font.Normal : Font.DemiBold
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }
    // dot numerals in the Nothing looks, heavy digits in the Apple one
    component Num: Item {
        id: num
        property string text: ""
        property real size: 30
        property color ink: root.pal.ink
        property string accentChar: ""
        implicitWidth: root.dots ? d.width : t.implicitWidth
        implicitHeight: root.dots ? d.height : t.implicitHeight * 0.82
        width: implicitWidth
        height: implicitHeight
        DotText {
            id: d
            visible: root.dots
            text: num.text
            pitch: num.size / 7
            ink: num.ink
            accent: root.pal.accent
            accentChar: num.accentChar
        }
        Text {
            id: t
            visible: !root.dots
            anchors.verticalCenter: parent.verticalCenter
            text: num.text
            color: num.ink
            font.family: Phone.font
            font.pixelSize: num.size * 1.12
            font.weight: Font.Bold
            font.features: { "tnum": 1 }
        }
    }
    component Tap: MouseArea {
        anchors.fill: parent
        enabled: !root.preview
    }
    // a progress ring: the track, then the arc from twelve o'clock
    component Ring: Canvas {
        property real value: 0
        property color ink: root.pal.ring || root.pal.accent
        property color track: root.pal.track
        property real line: 6
        onValueChanged: requestPaint()
        onInkChanged: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.reset();
            const r = Math.min(width, height) / 2 - line / 2;
            c.lineWidth = line;
            c.lineCap = "round";
            c.strokeStyle = track;
            c.beginPath(); c.arc(width / 2, height / 2, r, 0, 2 * Math.PI); c.stroke();
            c.strokeStyle = ink;
            c.beginPath(); c.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.max(0, Math.min(1, value))); c.stroke();
        }
    }
    // an on/off control: icon in a circle alone, icon and name in a pill
    component Toggle: Item {
        id: tg
        property string icon: ""
        property string label: ""
        property bool on: false
        property bool avail: true
        signal tapped()
        anchors.fill: parent
        opacity: avail ? 1 : 0.45
        Tile {
            id: tgTile
            pill: true
            color: tg.on ? root.pal.on : root.pal.tile
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                x: tgTile.circle ? (parent.width - width) / 2 : 16
                name: tg.icon
                color: tg.on ? root.pal.onInk : root.pal.ink
                size: tgTile.circle ? 26 : 22
            }
            Column {
                visible: !tgTile.circle
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 48; rightMargin: 12 }
                Label { width: parent.width; text: tg.label; color: tg.on ? root.pal.onInk : root.pal.ink; font.pixelSize: 14 }
                Label { width: parent.width; text: !tg.avail ? "Unavailable" : tg.on ? "On" : "Off"; color: tg.on ? root.pal.onInk : root.pal.dim; opacity: 0.8; font.pixelSize: 11 }
            }
        }
        Tap { enabled: !root.preview && tg.avail; onClicked: tg.tapped() }
    }

    Loader {
        anchors.fill: parent
        sourceComponent: ({ clock: clockC, analog: analogC, date: dateC, world: worldC, battery: batteryC, storage: storageC,
            wifi: wifiC, bluetooth: btC, torch: torchC, airplane: airplaneC, rotate: rotateC, dark: darkC,
            timer: timerC, stopwatch: stopwatchC, music: musicC, weather: weatherC, note: noteC, photo: photoC })[root.w.type] || null
    }

    Component {
        id: clockC
        Tile {
            readonly property string hh: Qt.formatTime(clock.date, "HH")
            readonly property string mm: Qt.formatTime(clock.date, "mm")
            Num {
                visible: !root.tall
                anchors.centerIn: parent
                text: parent.hh + ":" + parent.mm
                accentChar: ":"
                size: Math.min(parent.height * 0.5, parent.width / (root.dots ? 3.9 : 3.2))
            }
            Column {
                visible: root.tall
                anchors.centerIn: parent
                spacing: root.dots ? 10 : 0
                Num { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.hh; size: 52 }
                Num { anchors.horizontalCenter: parent.horizontalCenter; text: parent.parent.mm; size: 52 }
            }
            Rectangle {
                visible: root.tall && root.dots
                anchors { right: parent.right; bottom: parent.bottom; margins: 16 }
                width: 8; height: 8; radius: 4
                color: root.pal.accent
            }
        }
    }

    Component {
        id: analogC
        Tile {
            circle: true
            // the dark Nothing face is the white disc of its clock
            color: root.look === "nothing-dark" ? root.pal.alt : root.pal.tile
            readonly property color hand: root.look === "nothing-dark" ? root.pal.altInk : root.pal.ink
            Canvas {
                id: face
                anchors.fill: parent
                property var t: clock.date
                onTChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d");
                    c.reset();
                    const r = width / 2;
                    c.translate(r, r);
                    if (!root.dots) {
                        for (let i = 0; i < 60; i++) {
                            const a = i * Math.PI / 30, big = i % 5 === 0;
                            c.strokeStyle = big ? parent.hand : root.pal.dim;
                            c.lineWidth = big ? r * 0.035 : r * 0.015;
                            c.beginPath();
                            c.moveTo(Math.sin(a) * r * (big ? 0.78 : 0.84), -Math.cos(a) * r * (big ? 0.78 : 0.84));
                            c.lineTo(Math.sin(a) * r * 0.9, -Math.cos(a) * r * 0.9);
                            c.stroke();
                        }
                    } else {
                        c.fillStyle = root.pal.accent;
                        c.beginPath(); c.arc(0, -r * 0.82, r * 0.05, 0, 2 * Math.PI); c.fill();
                    }
                    const h = t.getHours() % 12 + t.getMinutes() / 60, m = t.getMinutes();
                    c.lineCap = "round";
                    c.strokeStyle = parent.hand;
                    c.lineWidth = r * (root.dots ? 0.07 : 0.08);
                    c.beginPath(); c.moveTo(0, 0); c.lineTo(Math.sin(h * Math.PI / 6) * r * 0.48, -Math.cos(h * Math.PI / 6) * r * 0.48); c.stroke();
                    c.lineWidth = r * (root.dots ? 0.07 : 0.055);
                    c.strokeStyle = root.dots ? root.pal.accent : parent.hand;
                    c.beginPath(); c.moveTo(0, 0); c.lineTo(Math.sin(m * Math.PI / 30) * r * 0.72, -Math.cos(m * Math.PI / 30) * r * 0.72); c.stroke();
                    c.fillStyle = root.dots ? parent.hand : root.pal.accent;
                    c.beginPath(); c.arc(0, 0, r * 0.06, 0, 2 * Math.PI); c.fill();
                }
            }
        }
    }

    Component {
        id: dateC
        Tile {
            Label {
                anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: root.small ? parent.height * 0.22 : 16; leftMargin: 16; rightMargin: 12 }
                horizontalAlignment: root.small ? Text.AlignHCenter : Text.AlignLeft
                text: Qt.formatDate(clock.date, root.small ? "ddd" : "dddd").toUpperCase()
                color: root.dots ? root.pal.ink : root.pal.accent
                font.pixelSize: root.small ? 11 : 14
                font.letterSpacing: 1
            }
            Num {
                x: root.small ? (parent.width - width) / 2 : 16
                anchors { bottom: parent.bottom; bottomMargin: root.small ? parent.height * 0.22 : 16 }
                text: Qt.formatDate(clock.date, "d")
                size: root.small ? 24 : 66
            }
        }
    }

    Component {
        id: worldC
        Tile {
            readonly property int off: root.w.offset | 0
            readonly property date there: new Date(clock.date.getTime() + (clock.date.getTimezoneOffset() + off) * 60000)
            readonly property string gmt: "GMT" + (off < 0 ? "-" : "+") + Math.floor(Math.abs(off) / 60) + (Math.abs(off) % 60 ? ":" + two(Math.abs(off) % 60) : "")
            Label {
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
                visible: root.tall
                text: Qt.formatDate(parent.there, "dddd").toUpperCase()
                font.pixelSize: 14
                font.letterSpacing: 1
            }
            Num {
                x: 16
                anchors.verticalCenter: root.tall ? parent.verticalCenter : parent.verticalCenter
                text: Qt.formatTime(parent.there, "HH:mm")
                accentChar: ":"
                size: root.tall ? 28 : 24
            }
            Num {
                visible: root.tall
                anchors { left: parent.left; bottom: parent.bottom; margins: 16 }
                text: parent.gmt
                size: 16
                ink: root.pal.dim
            }
            Label {
                visible: !root.tall
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                text: parent.gmt
                color: root.pal.dim
                font.pixelSize: 12
            }
        }
    }

    Component {
        id: batteryC
        Tile {
            id: bt
            readonly property int level: Status.hasBattery ? Math.max(0, Math.min(100, Status.battery)) : -1
            readonly property string pct: level < 0 ? "--" : level + "%"
            pill: root.w.h < 2 || (root.dots && !root.small)
            Ring {
                visible: bt.circle
                anchors { fill: parent; margins: 6 }
                value: bt.level / 100
                ink: Status.charging ? "#34c759" : bt.level <= 15 ? root.pal.accent : (root.pal.ring || root.pal.ink)
            }
            Num {
                visible: bt.circle
                anchors.centerIn: parent
                text: bt.pct
                size: root.dots ? 14 : 15
            }
            Icon {
                visible: !bt.circle
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                name: Status.charging ? "charging" : "battery"
                level: Math.max(0, bt.level)
                color: root.pal.ink
                size: 22
            }
            Label {
                visible: !bt.circle && root.w.h >= 2
                anchors { left: parent.left; top: parent.top; leftMargin: 42; topMargin: 14 }
                text: Status.charging ? "Charging" : "Battery"
                color: root.pal.dim
                font.pixelSize: 12
            }
            Num {
                visible: !bt.circle
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter; verticalCenterOffset: root.w.h >= 2 ? 6 : 0 }
                text: bt.pct
                size: root.w.h >= 2 ? 26 : 15
            }
        }
    }

    Component {
        id: storageC
        Tile {
            id: st
            property real used: -1
            property real total: 0
            Process {
                id: df
                running: true
                command: ["sh", "-c", 'df -Pk "$HOME" 2>/dev/null | awk "NR==2 { print \\$2, \\$3 }"']
                stdout: StdioCollector {
                    onStreamFinished: {
                        const p = text.trim().split(/\s+/).map(Number);
                        if (p.length === 2 && p[0] > 0) { st.total = p[0]; st.used = p[1]; }
                    }
                }
            }
            Timer { running: root.live && !root.preview; repeat: true; interval: 300000; onTriggered: df.running = true }
            readonly property string free: used < 0 ? "--" : ((total - used) / 1048576).toFixed((total - used) < 10485760 ? 1 : 0) + " GB"
            Ring {
                visible: st.circle
                anchors { fill: parent; margins: 6 }
                value: st.used < 0 ? 0 : st.used / st.total
                ink: root.pal.ring || root.pal.ink
            }
            Num {
                visible: st.circle
                anchors.centerIn: parent
                text: st.used < 0 ? "--" : Math.round(100 * st.used / st.total) + "%"
                size: root.dots ? 14 : 15
            }
            Column {
                visible: !st.circle
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
                spacing: 6
                Label { text: "Storage"; color: root.pal.dim; font.pixelSize: 12 }
                Label { text: st.free + " free"; font.pixelSize: 16; font.weight: Font.Bold }
                Rectangle {
                    width: parent.width
                    height: 6
                    radius: 3
                    color: root.pal.track
                    Rectangle {
                        width: st.used < 0 ? 0 : parent.width * st.used / st.total
                        height: parent.height
                        radius: 3
                        color: root.dots ? root.pal.ink : (root.pal.ring || root.pal.ink)
                    }
                }
            }
        }
    }

    Component {
        id: wifiC
        Toggle { icon: "wifi"; label: Status.wifiConnected && Status.s.wifiname ? Status.s.wifiname : "Wi-Fi"; avail: Status.hasWifi; on: Status.wifiOn; onTapped: Status.toggleWifi() }
    }
    Component {
        id: btC
        Toggle { icon: "bt"; label: "Bluetooth"; avail: Status.hasBt; on: Status.btOn; onTapped: Status.toggleBt() }
    }
    Component {
        id: torchC
        Toggle { icon: "torch"; label: "Torch"; avail: Status.hasTorch; on: Status.torchOn; onTapped: Status.toggleTorch() }
    }
    Component {
        id: darkC
        Toggle { icon: "dark"; label: "Dark mode"; on: !Phone.light; onTapped: Phone.setTheme(!Phone.light) }
    }
    // the quick panel's rfkill reading, polled here since the panel's model lives only while it is open
    Component {
        id: airplaneC
        Toggle {
            id: air
            property string radio: ""
            icon: "plane"
            label: "Airplane"
            avail: radio !== ""
            on: radio === "1"
            onTapped: { Status.run(["rfkill", on ? "unblock" : "block", "all"]); later.restart(); }
            Process {
                id: rf
                running: true
                command: ["sh", "-c", "command -v rfkill >/dev/null && rfkill -rn -o TYPE,SOFT 2>/dev/null | awk '{ n++; if ($2 == \"blocked\") b++ } END { if (n) print (n == b ? 1 : 0) }'"]
                stdout: StdioCollector { onStreamFinished: air.radio = text.trim() }
            }
            Timer { id: later; interval: 800; onTriggered: rf.running = true }
            Timer { running: root.live && !root.preview; repeat: true; interval: 15000; onTriggered: rf.running = true }
        }
    }
    // the compositor's lock file, read directly: the status poll reports it only while the panel is open
    Component {
        id: rotateC
        Toggle {
            id: rot
            property bool locked: false
            icon: "rotate"
            label: "Auto-rotate"
            avail: Status.hasRotation
            on: !locked
            onTapped: Status.run(["sh", "-c", 'printf %s "$1" > "$2"', "phonestatus", locked ? "0" : "1", Status.rotationFile])
            FileView {
                path: Status.rotationFile
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
                onLoaded: rot.locked = text().trim() === "1"
                onLoadFailed: rot.locked = false
            }
        }
    }

    // timer and stopwatch keep their state in this item only; a restart of the shell forgets them
    Component {
        id: timerC
        Tile {
            id: tm
            pill: !circle
            readonly property int total: Math.max(1, root.w.minutes || 5) * 60000
            property real endAt: 0
            property real remain: total
            property bool running: false
            property real now: Date.now()
            readonly property real shown: running ? Math.max(0, endAt - now) : remain
            Timer {
                running: tm.running
                repeat: true
                interval: 250
                onTriggered: {
                    tm.now = Date.now();
                    if (tm.endAt - tm.now <= 0) {
                        tm.running = false;
                        tm.remain = tm.total;
                        Status.alert();
                    }
                }
            }
            onTotalChanged: if (!running) remain = total
            Icon {
                visible: !tm.circle
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                name: tm.running ? "pause" : "timer"
                color: tm.running ? root.pal.accent : root.pal.ink
                size: 22
            }
            Num {
                anchors.verticalCenter: parent.verticalCenter
                x: tm.circle ? (parent.width - width) / 2 : parent.width - width - 16
                text: root.mmss(tm.shown)
                accentChar: ":"
                size: tm.circle ? 12 : 22
            }
            Tap {
                onClicked: {
                    tm.now = Date.now();
                    if (tm.running) { tm.remain = tm.endAt - tm.now; tm.running = false; }
                    else { tm.endAt = tm.now + tm.remain; tm.running = true; }
                }
                onPressAndHold: { tm.running = false; tm.remain = tm.total; }
            }
        }
    }
    Component {
        id: stopwatchC
        Tile {
            id: sw
            pill: !circle
            property real since: 0
            property real acc: 0
            property bool running: false
            property real now: Date.now()
            readonly property real shown: acc + (running ? now - since : 0)
            Timer { running: sw.running; repeat: true; interval: 250; onTriggered: sw.now = Date.now() }
            Icon {
                visible: !sw.circle
                x: 14
                anchors.verticalCenter: parent.verticalCenter
                name: sw.running ? "pause" : "stopwatch"
                color: sw.running ? root.pal.accent : root.pal.ink
                size: 22
            }
            Num {
                anchors.verticalCenter: parent.verticalCenter
                x: sw.circle ? (parent.width - width) / 2 : parent.width - width - 16
                text: root.mmss(sw.shown)
                accentChar: ":"
                size: sw.circle ? 12 : 22
            }
            Tap {
                onClicked: {
                    sw.now = Date.now();
                    if (sw.running) { sw.acc += sw.now - sw.since; sw.running = false; }
                    else { sw.since = sw.now; sw.running = true; }
                }
                onPressAndHold: { sw.running = false; sw.acc = 0; }
            }
        }
    }

    // the same player MediaCard follows; nothing playing, no title
    Component {
        id: musicC
        Tile {
            id: mu
            readonly property var player: {
                const all = Mpris.players.values;
                return all.find(p => p.isPlaying) || all[0] || null;
            }
            readonly property bool wide: root.w.w >= 4 || root.tall
            Icon {
                visible: mu.player === null || root.tall
                x: 16
                y: root.tall ? 16 : (parent.height - height) / 2
                name: "music"
                color: root.dots ? root.pal.accent : root.pal.ink
                size: 26
            }
            Column {
                // with nothing playing the note icon sits left of the line, with a player the keys sit right of it
                anchors { left: parent.left; right: keys.visible && !root.tall ? keys.left : parent.right; leftMargin: mu.player === null && !root.tall ? 52 : 16; rightMargin: 12 }
                y: root.tall ? parent.height - height - 64 : (parent.height - height) / 2
                Label { width: parent.width; text: mu.player ? (mu.player.trackTitle || mu.player.identity || "") : "Nothing playing"; font.pixelSize: 15; color: mu.player ? root.pal.ink : root.pal.dim }
                Label { width: parent.width; visible: text !== ""; text: mu.player ? (mu.player.trackArtist || "") : ""; color: root.pal.dim; font.pixelSize: 12 }
            }
            Row {
                id: keys
                anchors { right: parent.right; rightMargin: 10 }
                y: root.tall ? parent.height - height - 12 : (parent.height - height) / 2
                visible: mu.player !== null
                Repeater {
                    model: mu.wide ? ["prev", "play", "next"] : ["play"]
                    delegate: Item {
                        required property string modelData
                        width: 40
                        height: 40
                        Rectangle {
                            anchors.fill: parent
                            visible: parent.modelData === "play"
                            radius: 20
                            color: root.dots ? root.pal.accent : root.pal.ink
                        }
                        Icon {
                            anchors.centerIn: parent
                            name: parent.modelData === "play" ? (mu.player && mu.player.isPlaying ? "pause" : "play") : parent.modelData
                            color: parent.modelData === "play" ? (root.dots ? "#ffffff" : root.pal.tile) : root.pal.ink
                            size: 20
                        }
                        Tap {
                            onClicked: {
                                const p = mu.player;
                                if (!p) return;
                                if (parent.modelData === "play") p.togglePlaying();
                                else if (parent.modelData === "next") p.next();
                                else p.previous();
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: weatherC
        Tile {
            id: we
            WeatherData { id: wx; city: root.w.city || ""; fetch: root.live && !root.preview }
            readonly property var d: wx.info
            Label {
                anchors.centerIn: parent
                width: parent.width - 16
                horizontalAlignment: Text.AlignHCenter
                visible: !we.d
                wrapMode: Text.Wrap
                maximumLineCount: 2
                text: !root.w.city ? "Set a city" : wx.failed ? "Offline" : root.w.city
                color: root.pal.dim
                font.pixelSize: 12
            }
            // one column: just the temperature
            Num {
                visible: !!we.d && we.circle
                anchors.centerIn: parent
                text: we.d ? we.d.temp + "°" : ""
                size: 16
            }
            Item {
                visible: !!we.d && !we.circle
                anchors { fill: parent; margins: 14 }
                DotText {
                    id: wicon
                    anchors { right: parent.right; top: parent.top }
                    text: we.d ? wx.icon(we.d.code) : ""
                    pitch: root.tall ? 4 : 3
                    ink: root.pal.ink
                    accent: root.pal.accent
                }
                Label {
                    anchors { left: parent.left; right: wicon.left; top: parent.top; rightMargin: 6 }
                    text: we.d ? we.d.name : ""
                    font.pixelSize: 13
                }
                Num {
                    id: wtemp
                    anchors { left: parent.left; top: parent.top; topMargin: root.w.h >= 4 ? 30 : 22 }
                    text: we.d ? we.d.temp + "°" : ""
                    size: root.tall ? 36 : 22
                }
                Label {
                    visible: root.tall || root.w.w < 4
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    text: we.d ? (root.tall ? wx.words(we.d.code) + "\n" : "") + (we.d.days[0] ? "H " + we.d.days[0].hi + "°  L " + we.d.days[0].lo + "°" : "") : ""
                    color: root.pal.dim
                    font.pixelSize: 12
                    wrapMode: Text.NoWrap
                    elide: Text.ElideNone
                }
                // four columns: the next days along the bottom
                Row {
                    visible: root.w.w >= 4 && !root.tall
                    anchors { right: wicon.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 14
                    Repeater {
                        model: we.d ? we.d.days.slice(1, 5) : []
                        delegate: Column {
                            required property var modelData
                            spacing: 3
                            Label { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.formatDate(new Date(modelData.day + "T12:00:00"), "ddd").toUpperCase(); color: root.pal.dim; font.pixelSize: 10 }
                            DotText { anchors.horizontalCenter: parent.horizontalCenter; text: wx.icon(modelData.code); pitch: 2; ink: root.pal.ink }
                            Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.hi + "°"; font.pixelSize: 11 }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: noteC
        Tile {
            color: root.dots ? root.pal.tile : "#fff7d6"
            Label {
                anchors { fill: parent; margins: 14 }
                text: root.w.text || "Short note"
                wrapMode: Text.Wrap
                color: root.w.text ? (root.dots ? root.pal.ink : "#3a3000") : root.pal.dim
                font.pixelSize: 15
                font.weight: Font.Normal
            }
        }
    }

    // the picture painted once inside the rounded shape, no layer kept per widget
    Component {
        id: photoC
        Tile {
            id: ph
            readonly property string src: root.w.file ? "file://" + root.w.file : ""
            Label {
                anchors.centerIn: parent
                visible: !ph.src
                text: "Pick a photo"
                color: root.pal.dim
            }
            // its size only; the canvas draws it with the tile's rounded corners
            Image {
                id: pic
                visible: false
                source: ph.src
                asynchronous: true
            }
            Canvas {
                id: phc
                anchors.fill: parent
                property string src: ph.src
                onSrcChanged: if (src) loadImage(src)
                Component.onCompleted: if (src) loadImage(src)
                onImageLoaded: requestPaint()
                onWidthChanged: requestPaint()
                Connections { target: pic; function onStatusChanged() { phc.requestPaint(); } }
                onPaint: {
                    const c = getContext("2d");
                    c.reset();
                    const iw = pic.implicitWidth, ih = pic.implicitHeight;
                    if (!src || !isImageLoaded(src) || !iw || !ih)
                        return;
                    const r = ph.radius;
                    c.beginPath();
                    c.roundedRect(0, 0, width, height, r, r);
                    c.clip();
                    const k = Math.max(width / iw, height / ih);
                    c.drawImage(src, (width - iw * k) / 2, (height - ih * k) / 2, iw * k, ih * k);
                }
            }
        }
    }
}
