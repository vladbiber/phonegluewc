import Quickshell
import QtQuick
import "widgets"

// the widgets of one screen, laid out for a full screen; a card scales this down
Item {
    id: root

    property bool lock: false
    property int screenIndex: -1
    property bool live: true
    property bool preview: false
    // near black over a light wallpaper at the top, as on the lock
    property color ink: luma.light ? Qt.rgba(0.08, 0.08, 0.08, 0.9) : Phone.white
    property color dateInk: luma.light ? Qt.rgba(0.08, 0.08, 0.08, 0.7) : Phone.grey
    // the one a finger is moving in the editor
    property int dragIndex: -1
    property real dragX: 0
    property real dragY: 0

    readonly property string kind: lock ? "lock" : "home"
    readonly property var widgets: Screens.screenOf(kind, screenIndex).widgets
    // the lock's widgets sit under its clock, whose height depends on the style; measured from the lock test's captures
    property string clockStyle: Phone.conf.lock_clock || "dot"
    readonly property var clockEnds: ({ dot: 210, thin: 328, bold: 260, small: 196, stacked: 440 })
    // where the lock's room ends, e.g. the PIN pad; a widget that does not fit above it is hidden
    property real room: height
    readonly property int lockRows: 4
    // landscape: portrait-sized cells in bands side by side, a row past the first band's height goes on in the next
    readonly property bool wide: width > height
    readonly property real topY: lock ? clockEnds[clockStyle] || clockEnds.dot : wide ? 40 : Screens.top(kind)
    readonly property int rowsPer: lock ? lockRows : wide ? Math.max(3, Math.floor((height - topY - 16) / Screens.rowH)) : Screens.rows(kind, height)
    readonly property int fitRows: lock ? Math.min(lockRows, Math.floor((room - topY) / Screens.rowH)) : rowsPer
    readonly property real cellW: ((wide ? height : width) - 2 * Screens.pad) / Screens.cols
    readonly property real bandW: Screens.cols * cellW + Screens.pad
    // 72 keeps the side tray clear
    readonly property int bands: wide ? Math.max(1, Math.floor((width - Screens.pad - 72) / bandW)) : 1
    // first row of each band: a band ends early rather than cut a widget in two
    readonly property var starts: {
        const s = [0];
        while (s.length < bands) {
            const a = s[s.length - 1];
            let b = a + rowsPer;
            while (b > a + 1 && widgets.some(w => w.row < b && w.row + w.h > b))
                b--;
            s.push(b);
        }
        return s;
    }
    readonly property int maxRows: starts[bands - 1] + rowsPer

    function bandOf(w) { let b = 0; for (let i = 1; i < starts.length; i++) if (w.row >= starts[i]) b = i; return b; }
    function xOf(w) { return Screens.pad + bandOf(w) * bandW + w.col * cellW; }
    function yOf(w) { return topY + Math.max(0, Math.min(w.row - starts[bandOf(w)], rowsPer - w.h)) * Screens.rowH; }
    // where a widget of w's size lands with its corner at x, y
    function cellAt(x, y, w) {
        const b = Math.max(0, Math.min(bands - 1, Math.floor((x - Screens.pad + cellW / 2) / bandW)));
        return { col: Math.max(0, Math.min(Screens.cols - w.w, Math.round((x - Screens.pad - b * bandW) / cellW))),
            row: starts[b] + Math.max(0, Math.min(rowsPer - w.h, Math.round((y - topY) / Screens.rowH))) };
    }

    SystemClock { id: clock; enabled: root.live; precision: SystemClock.Minutes }
    // shortcut: samples the top quarter, not where the clock widget actually sits; follow its row if clocks move low
    WallLuma { id: luma; wallpaper: Screens.wallpaperOf(root.kind, root.screenIndex < 0 ? Screens.active(root.kind) : root.screenIndex); to: 0.25 }

    Repeater {
        model: root.widgets
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property var w: modelData
            readonly property bool dragged: root.dragIndex === index
            x: dragged ? root.dragX : root.xOf(w)
            y: dragged ? root.dragY : root.yOf(w)
            z: dragged ? 2 : 0
            width: w.w * root.cellW
            height: w.h * Screens.rowH
            // the lock never shows a type it does not allow (the unsaved default has a clock), nor one past its room
            visible: !root.lock || Screens.lockTypes.includes(w.type) && (dragged || w.row + w.h <= root.fitRows)

            Loader {
                anchors.fill: parent
                sourceComponent: cell.w.type === "app" ? appC : !Screens.bare(cell.w) ? widgetC : cell.w.type === "clock" ? clockC : dateC
            }

            Component {
                id: widgetC
                Widget {
                    w: cell.w
                    lock: root.lock
                    preview: root.preview
                    live: root.live
                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.preview && cell.w.type === "note"
                        onClicked: { Screens.noteRequest = cell.index; Screens.openEditor(); }
                    }
                }
            }

            Component {
                id: clockC
                Item {
                    DotClock {
                        readonly property int fit: Math.floor(Math.min(parent.width / 26, parent.height / 7))
                        x: root.lock ? (parent.width - width) / 2 : 0
                        pitch: fit
                        width: implicitWidth
                        height: implicitHeight
                        time: Qt.formatTime(clock.date, "HH:mm")
                        ink: root.ink
                    }
                }
            }
            Component {
                id: dateC
                Text {
                    text: Qt.formatDate(clock.date, cell.w.w >= 4 ? "dddd, d MMMM" : "ddd d MMM")
                    horizontalAlignment: root.lock ? Text.AlignHCenter : Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    color: root.dateInk
                    font.family: Phone.font
                    font.pixelSize: 17
                }
            }
            Component {
                id: appC
                Item {
                    readonly property var entry: Phone.apps.find(e => e.id === cell.w.app) || null
                    visible: entry !== null
                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        AppIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            entry: parent.parent.entry
                            size: 52
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: root.cellW - 4
                            horizontalAlignment: Text.AlignHCenter
                            text: parent.parent.entry ? parent.parent.entry.name : ""
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            color: Phone.white
                            font.family: Phone.font
                            font.pixelSize: 12
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.preview && parent.entry !== null
                        onClicked: Phone.launch(parent.entry)
                        pressAndHoldInterval: 500
                        onPressAndHold: Phone.askPin(parent.entry, mapToItem(null, width / 2, 0).x, Window.height - mapToItem(null, 0, 0).y)
                    }
                }
            }
        }
    }
}
