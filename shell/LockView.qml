import Quickshell
import QtQuick

// the same screen at boot and at lock: no user is named or listed, one password decides
Item {
    id: root

    signal unlocked()
    readonly property bool typing: field.activeFocus
    Binding { target: Phone; property: "lockTyped"; value: field.text !== "" || pad.digits !== "" }
    // the PIN pad shows once the password was used since boot; its link brings the password back
    property bool usePassword: false
    Component.onCompleted: Pin.refresh()
    // the laptop layout of the keyboard is the tallest, plus the bar under it
    readonly property int keyboardRoom: 362

    // a hold edits the lock: the password first, then the lock opens on a swipe up without it
    property bool wantEdit: false
    property bool authed: false
    property bool editing: false
    // every right answer comes here: password, PIN or finger
    function passed() {
        field.keyboard(false);
        if (!wantEdit)
            return root.unlocked();
        wantEdit = false;
        authed = true;
        editing = true;
        field.focus = false;
        root.forceActiveFocus();
    }
    // the opened lock closes again after a minute untouched, or with the screen
    Timer { interval: 60000; running: root.authed && !root.editing; onTriggered: root.authed = false }

    LockWallpaper { anchors.fill: parent }

    MouseArea {
        property real pressY: 0
        anchors.fill: parent
        onPressed: mouse => pressY = mouse.y
        onReleased: mouse => { if (root.authed && pressY - mouse.y > 120) root.unlocked(); }
        onClicked: { root.forceActiveFocus(); picker.open = false; root.wantEdit = false; }
        onPressAndHold: {
            if (Auth.greeter)
                return;
            if (root.authed) {
                root.editing = true;
            } else {
                root.wantEdit = true;
                (pad.visible ? pad : field).forceActiveFocus();
            }
        }
    }

    LockClock { anchors.fill: parent; visible: !root.editing; room: pad.visible ? pad.y : height }
    ScreenWidgets { anchors.fill: parent; lock: true; visible: !root.editing; room: pad.visible ? pad.y : height }

    Text {
        anchors { bottom: box.top; bottomMargin: 10; horizontalCenter: parent.horizontalCenter }
        id: note
        property bool shown: false
        property bool done: false
        text: root.authed ? "Swipe up to open" : done ? "Mock: the session would start now" : (shown ? "Wrong password" : "")
        color: done || root.authed ? Phone.grey : Phone.accent
        visible: !root.editing
        font.family: Phone.font
        font.pixelSize: 15
    }

    Rectangle {
        id: box
        visible: !root.authed && !root.editing && !pad.visible
        readonly property int restY: root.height - 96 - 72
        readonly property int upY: root.height - root.keyboardRoom - 64
        x: 28
        y: root.typing ? upY : restY
        width: parent.width - 56
        height: 56
        radius: 28
        color: Phone.card
        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        SequentialAnimation {
            id: wrong
            NumberAnimation { target: box; property: "x"; to: 40; duration: 50 }
            NumberAnimation { target: box; property: "x"; to: 18; duration: 70 }
            NumberAnimation { target: box; property: "x"; to: 28; duration: 50 }
        }

        TextInput {
            id: field
            anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
            verticalAlignment: TextInput.AlignVCenter
            color: Phone.fg
            selectionColor: Phone.accent
            echoMode: TextInput.Password
            passwordMaskDelay: 0
            font.family: Phone.font
            font.pixelSize: 17
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhHiddenText | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            onTextEdited: note.shown = false
            // shortcut: Qt 6.11 does not always switch text input off or on at the lock, so the field tells this display's phonekbd itself; drop once Qt does
            function keyboard(show) {
                Quickshell.execDetached(["sh", "-c", 'for p in $(pgrep -x phonekbd); do tr "\\0" "\\n" </proc/$p/environ'
                    + ' | grep -qx "WAYLAND_DISPLAY=$WAYLAND_DISPLAY" && kill -' + (show ? "USR1" : "USR2") + ' $p; done']);
            }
            onActiveFocusChanged: keyboard(activeFocus)
            onAccepted: {
                if (Auth.busy)
                    return;
                const password = text;
                text = "";
                if (password !== "")
                    Auth.submit(password);
            }

            // a keyboard hidden by its own button leaves the field focused; a tap asks for it again
            TapHandler { onTapped: field.activeFocus ? field.keyboard(true) : field.forceActiveFocus() }

            Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: field.text === ""
                text: "Password"
                color: Phone.dim
                font: field.font
            }
        }
    }

    Connections {
        target: Auth
        function onAnswered(ok) {
            if (ok) {
                if (Auth.greeter)
                    Auth.launchSession();
                note.done = Auth.greeter && Auth.mock !== "";
                if (!Auth.greeter)
                    Pin.rememberPassword();
                root.passed();
            } else {
                note.shown = true;
                wrong.restart();
                field.forceActiveFocus();
            }
        }
    }

    Item {
        id: bottom
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 28; bottomMargin: 36 }
        height: 56
        visible: !root.typing && !root.editing

        LockShortcut { anchors.left: parent.left; kind: Auth.config.left }
        LockShortcut { anchors.right: parent.right; kind: Auth.config.right }

        Item {
            id: picker
            property bool open: false
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
            width: Math.min(parent.width - 136, label.implicitWidth + 40)
            height: 48

            Text {
                id: label
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width)
                elide: Text.ElideRight
                // shortcut: only a label at the lock, the session cannot change while it runs
                text: !Auth.greeter ? "phonegluewc" : (Auth.session ? Auth.session.name : "No session")
                color: Phone.grey
                font.family: Phone.font
                font.pixelSize: 14
            }
            MouseArea { anchors.fill: parent; enabled: Auth.greeter; onClicked: picker.open = !picker.open }

            Rectangle {
                anchors { bottom: parent.top; bottomMargin: 8; horizontalCenter: parent.horizontalCenter }
                width: 200
                height: list.height + 8
                radius: 16
                color: Phone.card
                visible: picker.open

                Column {
                    id: list
                    anchors.centerIn: parent
                    Repeater {
                        model: Auth.sessions
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: 192
                            height: 48
                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 24
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                                text: parent.modelData.name
                                color: parent.index === Auth.sessionIndex ? Phone.fg : Phone.dim
                                font.family: Phone.font
                                font.pixelSize: 15
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { Auth.sessionIndex = parent.index; picker.open = false; }
                            }
                        }
                    }
                }
            }
        }
    }
    Fingerprint {
        id: finger
        visible: shown && !root.typing && !root.authed && !root.editing
        onMatched: root.passed()
    }
    PinPad {
        id: pad
        anchors { bottom: parent.bottom; bottomMargin: finger.visible ? root.height - finger.y + 16 : 116 }
        visible: Pin.usable && !root.usePassword && !root.authed && !root.editing
        // the hidden password field must not keep the keyboard up over the pad
        onVisibleChanged: if (visible) { root.forceActiveFocus(); field.keyboard(false); }
        Component.onCompleted: if (visible) field.keyboard(false)
        onUnlocked: root.passed()
        onUsePassword: { root.usePassword = true; field.forceActiveFocus(); }
    }
    Loader {
        anchors.fill: parent
        active: Status.chargeShowing
        sourceComponent: ChargeAnim {}
    }
    // above the lock's own touch areas, gone as soon as the password has a keystroke
    Loader {
        anchors.fill: parent
        active: !Auth.greeter && Dyn.on
        sourceComponent: DynShape { inLock: true }
    }
    onTypingChanged: if (typing) Dyn.collapse()
    Loader {
        anchors.fill: parent
        active: root.editing
        sourceComponent: LockEditor { onClosed: root.editing = false }
    }
    ButtonFeedback { anchors.fill: parent }
}
