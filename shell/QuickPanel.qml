import Quickshell
import Quickshell.Wayland
import QtQuick

// the pull down sheet, notifications and quick settings side by side; exists only while on screen
PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "phone-panel"
    // like the menu: while a layer wants keys the compositor tells the shell about pill use
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    SystemClock { id: time; precision: SystemClock.Minutes }
    // opened from the overview pill: what runs in the background; from the footer: the open windows
    AppModel { id: apps; background: Phone.runningOpen }
    // the overview's tray apps pill opens the list directly, and leaving it leaves the panel
    property bool appsOpen: Phone.runningOpen
    Component.onDestruction: Phone.runningOpen = false
    QuickModel { id: quick }

    // with no wallpaper, no blur: one black layer between the sheet and whatever is behind
    // with one, nothing outside the sheet: the compositor's blur follows what this layer paints
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: Phone.wallpaper === "" ? 0.6 * Status.pull : 0
    }

    component SwipeUp: Item {
        anchors.fill: parent
        DragHandler {
            target: null
            xAxis.enabled: false
            onActiveChanged: {
                if (active) {
                    Status.grab();
                    Status.track(0);
                } else {
                    Status.releasePull(root.height, 0.75);
                }
            }
            onActiveTranslationChanged: {
                if (!active)
                    return;
                Status.track(activeTranslation.y);
                Status.pull = Math.max(0.001, Math.min(1, 1 + activeTranslation.y / root.height));
            }
        }
    }
    component BottomRow: Item {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 26 }
        height: 40
    }
    component Pill: Rectangle {
        id: pill
        property alias text: pillText.text
        property alias textColor: pillText.color
        signal tapped()
        anchors.verticalCenter: parent.verticalCenter
        width: pillText.implicitWidth + 28
        height: 32
        radius: 16
        color: Phone.frost
        border.color: Phone.frostLine
        Text {
            id: pillText
            anchors.centerIn: parent
            color: Phone.fg
            font.family: Phone.font
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        MouseArea {
            anchors { fill: parent; margins: -8 }
            onClicked: pill.tapped()
        }
    }

    Rectangle {
        id: sheet
        width: parent.width
        height: parent.height
        y: -height * (1 - Status.pull)
        // a tint over the compositor's blur, as the menu's: lighter fails 4.5:1 text on the wrong wallpaper; opaque with none to blur
        color: Phone.wallpaper === "" ? Phone.mix("#0c0c0c", "#f2f2f2") : Phone.light ? Qt.rgba(1, 1, 1, 0.5) : Qt.rgba(0, 0, 0, 0.45)

        // empty space: a real tap closes; clicked also fires after a hold or a small move
        MouseArea {
            anchors.fill: parent
            property real startX: 0
            property real startY: 0
            property bool spent: false
            onPressed: mouse => {
                startX = mouse.x;
                startY = mouse.y;
                spent = false;
            }
            onPositionChanged: mouse => {
                if (Math.hypot(mouse.x - startX, mouse.y - startY) >= 8)
                    spent = true;
            }
            onPressAndHold: spent = true
            onClicked: if (!spent) Status.settleTo(0)
        }

        Item {
            id: notifPane
            width: parent.width
            height: parent.height
            x: -Status.side * width
            visible: x > -width

            Text {
                x: Status.startFor(implicitWidth, root.width)
                height: Status.barHeight
                verticalAlignment: Text.AlignVCenter
                text: Qt.formatDate(time.date, "ddd d MMM")
                color: Phone.fg
                font.family: Phone.font
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            Text {
                anchors.centerIn: parent
                visible: Status.notifs.length === 0
                text: "No notifications"
                color: Phone.glassDim
                font.family: Phone.font
                font.pixelSize: 14
            }
            // shortcut: on a list long enough to scroll, swipe up closes only from outside it; close at the list's end if missed
            SwipeUp {}
            Flickable {
                id: list
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: notifRow.top; topMargin: Status.barHeight + 8; leftMargin: 16; rightMargin: 16 }
                clip: true
                contentHeight: rows.height
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: rows
                    width: list.width
                    spacing: 8
                    Repeater {
                        model: Status.notifGroups
                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            width: rows.width
                            height: cardBody.height + 24
                            radius: 20
                            color: Phone.frost
                            border.color: Phone.frostLine

                            Column {
                                id: cardBody
                                x: 12
                                y: 12
                                width: parent.width - 24
                                spacing: 8
                                Row {
                                    spacing: 8
                                    AppIcon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        entry: ({ name: card.modelData.app || "?", icon: card.modelData.icon })
                                        size: 24
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: cardBody.width - 32
                                        text: card.modelData.app
                                        elide: Text.ElideRight
                                        color: Phone.glassDim
                                        font.family: Phone.font
                                        font.pixelSize: 12
                                    }
                                }
                                Repeater {
                                    model: card.modelData.items
                                    delegate: Column {
                                        id: entry
                                        required property var modelData
                                        width: cardBody.width
                                        spacing: 2
                                        Text {
                                            width: parent.width
                                            text: entry.modelData.summary + "  " + entry.modelData.time
                                            textFormat: Text.PlainText
                                            elide: Text.ElideRight
                                            color: Phone.fg
                                            font.family: Phone.font
                                            font.pixelSize: 15
                                        }
                                        Text {
                                            width: parent.width
                                            visible: entry.modelData.body !== ""
                                            text: entry.modelData.body
                                            textFormat: Text.PlainText
                                            wrapMode: Text.Wrap
                                            maximumLineCount: 3
                                            elide: Text.ElideRight
                                            color: Phone.glassDim
                                            font.family: Phone.font
                                            font.pixelSize: 13
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            BottomRow {
                id: notifRow
                Pill {
                    anchors { right: parent.right; rightMargin: 16 }
                    visible: Status.notifs.length > 0
                    text: "Clear"
                    textColor: Phone.accent
                    onTapped: Status.clearNotifs()
                }
            }
        }

        Item {
            id: settingsPane
            width: parent.width
            height: parent.height
            x: (1 - Status.side) * width
            visible: x < width

            QuickSettings {
                id: quickView
                anchors.fill: parent
                model: quick
                activeApps: apps.count
                onOpenApps: root.appsOpen = true
            }
        }

        // quick settings has its own footer there
        BottomRow {
            visible: Status.side < 0.5
            Rectangle {
                anchors.centerIn: parent
                width: 44
                height: 4
                radius: 2
                color: Phone.glassDim
            }
        }

        // over everything, the same way: a sideways swipe moves between the two views
        Item {
            anchors.fill: parent
            DragHandler {
                target: null
                yAxis.enabled: false
                enabled: !root.appsOpen && !quickView.sinksOpen && !quickView.powerOpen && !quickView.busy
                property real from: 0
                // over the tiles while they have a page that way, otherwise the two views; reorder mode never swaps
                property string route: ""
                onActiveChanged: {
                    if (active) {
                        Status.grab();
                        Status.track(0);
                        from = Status.side;
                        route = "";
                    } else if (route === "side") {
                        Status.releaseSide(root.width);
                    } else {
                        const v = Status.speed();
                        Status.dragging = false;
                        if (route === "grid")
                            quickView.pageEnd(v);
                    }
                }
                onActiveTranslationChanged: {
                    const dx = activeTranslation.x;
                    if (!active || dx === 0)
                        return;
                    if (route === "")
                        route = Status.side === 1 && quickView.wantsPage(centroid.pressPosition, dx) ? "grid" : quickView.editing ? "none" : "side";
                    Status.track(dx);
                    if (route === "grid")
                        quickView.pageDrag(dx);
                    else if (route === "side")
                        Status.side = Math.max(0, Math.min(1, from - dx / root.width));
                }
            }
        }

        Loader {
            anchors.fill: parent
            active: root.appsOpen
            sourceComponent: AppList {
                model: apps
                onBack: {
                    root.appsOpen = false;
                    if (Phone.runningOpen)
                        Status.close();
                }
            }
        }
    }
}
