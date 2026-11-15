import Quickshell
import Quickshell.Io
import QtQuick

// what the top bar shows: clock, notification icons, radios, battery; drawn by the bar's window and by the lock
Item {
    id: root

    // the app's own top colour behind the bar, as phones do; the compositor samples it into state/topcolor
    // none: no app in front; unknown: its buffer could not be read, so Phone.black
    FileView {
        id: topFile
        path: Phone.stateDir + "/topcolor"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property string topColor: topFile.text().trim()
    // home, lock, menu and overview keep the bar clear over the wallpaper
    readonly property bool onApp: /^#[0-9a-f]{6}$|^unknown$/.test(topColor) && !Phone.overview && !Phone.lockOpen && !Phone.menuOpen
    property color appColor: Phone.black
    onTopColorChanged: if (/^#[0-9a-f]{6}$|^unknown$/.test(topColor)) appColor = topColor === "unknown" ? Phone.black : topColor
    // the app menu sheet starts under the bar, so the bar takes its colour
    readonly property bool overMenu: Phone.menuOpen && !Phone.lockOpen
    // bare home or lock: the top eighth of the wallpaper picks the ink
    WallLuma { id: wall; wallpaper: Screens.wallpaperOf(Phone.lockOpen ? "lock" : "home", Screens.active(Phone.lockOpen ? "lock" : "home")); to: 0.125 }
    readonly property bool light: onApp && 0.299 * appColor.r + 0.587 * appColor.g + 0.114 * appColor.b > 0.6 || overMenu && Phone.light
            || !onApp && !overMenu && !Phone.overview && wall.light
    readonly property color ink: light ? "#141414" : Phone.white
    readonly property int fade: Phone.conf.animations !== "off" ? 150 : 0
    Rectangle {
        anchors.fill: parent
        // over the menu with a wallpaper the menu's sheet runs on under the bar; solid without one
        color: !root.overMenu ? root.appColor : Phone.wallpaper === "" ? Phone.bg : Phone.light ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(0, 0, 0, 0.45)
        opacity: root.onApp || root.overMenu && Phone.wallpaper === "" ? 1 : 0
        Behavior on color { ColorAnimation { duration: root.fade } }
        Behavior on opacity { NumberAnimation { duration: root.fade } }
    }

    readonly property real dpr: QsWindow.window ? QsWindow.window.devicePixelRatio : Screen.devicePixelRatio
    function snap(v) { return Math.round(v * dpr) / dpr; }
    readonly property real gap: snap(6)

    readonly property real clockEnd: leftGroup.x + clock.width
    // the dynamic camera's pill takes its room from the same place the hole does; both meet when it has shrunk back
    readonly property bool pillLeft: Dyn.barActive && Dyn.side === "left"
    readonly property real holeL: Dyn.barActive && Dyn.side !== "left" ? Dyn.pillStart - 8 : Status.holeLeft(width)
    readonly property real holeR: Status.holeRight(width)
    // what is to the right of the clock must stop short of the hole when the hole is out there
    readonly property bool holeAhead: holeL > clockEnd
    readonly property real iconsEnd: Dyn.holeKnown && Dyn.side === "right" ? Math.min(width - Status.cornerPad, holeL) : width - Status.cornerPad
    readonly property real iconsLeft: iconsEnd - rightGroup.width
    // the right group stays: the icons of notifications go first, then the clock
    readonly property bool clockFits: !pillLeft || leftGroup.x + clock.implicitWidth <= iconsLeft - 8
    readonly property real notifRoom: (holeAhead ? Math.min(holeL, iconsLeft) : iconsLeft) - clockEnd - 12
    readonly property int notifSlots: Math.max(0, Math.floor(notifRoom / 22))
    readonly property var notifShown: Status.notifApps.slice(0, Status.notifApps.length > notifSlots ? Math.max(0, notifSlots - 1) : notifSlots)

    readonly property real line: Status.barCenter(width)
    // text is centred by its ink: the digit box measured at device size, where hinting cannot round it
    TextMetrics {
        id: digit
        font.family: Phone.font
        font.weight: Font.Medium
        font.pixelSize: 14 * root.dpr
        text: "0"
    }
    function textY(size, base) {
        const k = size / 14 / dpr;
        return line - digit.tightBoundingRect.height * k / 2 - digit.tightBoundingRect.y * k - base;
    }

    SystemClock { id: time; precision: SystemClock.Minutes }

    Row {
        id: leftGroup
        // the pull down panel draws its own clock and icons here; ours would show through its blur
        opacity: 1 - Math.min(1, Status.pull * 12)
        x: root.snap(Math.max(Status.startFor(clock.width, root.width), root.pillLeft ? Dyn.pillEnd + 8 : 0))
        height: parent.height
        spacing: root.snap(8)

        Label {
            id: clock
            Behavior on color { ColorAnimation { duration: root.fade } }
            text: Qt.formatTime(time.date, "HH:mm")
            opacity: root.clockFits ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
        Row {
            height: parent.height
            spacing: root.snap(4)
            Repeater {
                model: root.notifShown
                delegate: AppIcon {
                    required property var modelData
                    y: root.snap(root.line - height / 2)
                    entry: ({ name: modelData.app || "?", icon: modelData.icon })
                    size: 18
                }
            }
            Label {
                visible: root.notifShown.length < Status.notifApps.length
                text: "+" + (Status.notifApps.length - root.notifShown.length)
                font.pixelSize: 12
            }
        }
    }

    Row {
        id: rightGroup
        opacity: 1 - Math.min(1, Status.pull * 12)
        x: root.snap(root.iconsEnd - width)
        height: parent.height
        spacing: root.gap

        Rectangle {
            visible: Status.recording
            y: root.snap(root.line - height / 2)
            width: 8
            height: 8
            radius: 4
            color: Phone.accent
        }
        // bars, the network type, and whether data flows: one icon, as other phones draw it
        Row {
            visible: Status.hasCell
            height: parent.height
            spacing: root.snap(2)
            Label {
                visible: Status.cellType !== ""
                text: Status.cellType
                color: Status.dataOn ? root.ink : Phone.grey
                font.pixelSize: 10
            }
            BarIcon {
                visible: Status.hasData
                name: Status.dataOn ? "data" : "dataoff"
                color: Status.dataOn ? root.ink : Phone.grey
                size: 9
            }
            BarIcon {
                name: "cell"
                level: Status.cellLevel
            }
        }
        BarIcon {
            visible: Status.hasWifi && Status.wifiOn
            name: "wifi"
            level: Status.wifiLevel
            color: Status.wifiConnected ? root.ink : Phone.grey
        }
        BarIcon {
            visible: Status.hasBt && Status.btOn
            name: "bt"
            color: Status.btConnected > 0 ? root.ink : Phone.grey
        }
        BarIcon {
            visible: Status.hasVolume
            name: Status.ringer === "normal" && Status.muted ? "volx" : Status.ringerIcon
            color: Status.ringer === "silent" || Status.muted ? Phone.accent : root.ink
        }
        BatteryPill {
            visible: Status.hasBattery
            // the rounded pill paints one row past its height, measured at both scales
            y: root.snap(root.line - height / 2) - 1 / root.dpr
            level: Status.battery
            charging: Status.charging
            ink: root.ink
            paper: root.light ? Phone.white : "#141414"
        }
    }

    component BarIcon: Icon {
        color: root.ink
        y: root.snap(root.line - height / 2)
    }
    component Label: Text {
        width: Math.ceil(implicitWidth * root.dpr) / root.dpr
        y: root.textY(font.pixelSize, baselineOffset)
        color: root.ink
        font.family: Phone.font
        font.pixelSize: 14
        font.weight: Font.Medium
        font.features: { "tnum": 1 }
    }
}
