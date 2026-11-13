import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// asks, and shows the outcome; shell/uninstall.sh decides who owns the app and removes it
PanelWindow {
    id: root

    anchors { top: true; bottom: true; left: true; right: true }
    color: "#b0000000"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "phone-uninstall"
    WlrLayershell.keyboardFocus: step === "password" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    readonly property string appName: Phone.removeEntry ? Phone.removeEntry.name || Phone.removeEntry.id : ""
    readonly property string helper: Quickshell.shellDir + "/uninstall.sh"
    // loading, ask, warn, warn2, password, working, done
    property string step: "loading"
    property var info: ({})
    property string note: ""
    property bool deleteData: false

    onStepChanged: if (step === "password") field.forceActiveFocus()

    function parse(text) {
        const out = {};
        for (const line of text.split("\n")) {
            const at = line.indexOf("=");
            if (at > 0)
                out[line.slice(0, at)] = line.slice(at + 1);
        }
        return out;
    }
    function finish(text) {
        note = text;
        step = "done";
    }
    function start() {
        step = "working";
        const args = ["sh", helper, "remove", Phone.removeEntry.id];
        if (deleteData)
            args.push("data");
        remover.command = args;
        remover.running = true;
    }
    function advance() {
        if (step === "ask")
            step = info.needpw === "1" ? "password" : "go";
        else if (step === "warn")
            step = "warn2";
        else if (step === "warn2")
            step = info.needpw === "1" ? "password" : "go";
        if (step === "go")
            start();
    }

    Process {
        command: ["sh", root.helper, "inspect", Phone.removeEntry ? Phone.removeEntry.id : ""]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const r = root.parse(text);
                root.info = r;
                if (r.error)
                    root.finish(r.error);
                else if (r.owner === "flatpak" || r.owner === "waydroid" || r.owner === "system")
                    root.step = r.essential === "1" ? "warn" : "ask";
                else
                    root.finish("Nothing here says what installed this app, so it stays.");
            }
        }
    }
    Process {
        id: remover
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: {
                const r = root.parse(text);
                if (r.result === "ok") {
                    Phone.forgetApp(Phone.removeEntry.id);
                    Phone.removeEntry = null;
                } else if (r.result === "simulated") {
                    root.finish("Simulated, nothing removed.");
                } else {
                    root.finish(r.error || "The removal failed.");
                }
            }
        }
        // the password goes straight to the password tool and is dropped here
        onStarted: {
            if (field.text !== "")
                write(field.text + "\n");
            field.text = "";
            stdinEnabled = false;
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.step !== "working"
        onClicked: Phone.removeEntry = null
    }
    Rectangle {
        id: box
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 20; rightMargin: 20; topMargin: 96 }
        height: content.height + 40
        radius: 24
        color: Phone.card

        // a tap on the box is not a tap outside it
        MouseArea { anchors.fill: parent }

        Column {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
            spacing: 16

            Text {
                width: parent.width
                wrapMode: Text.Wrap
                color: Phone.fg
                font.family: Phone.font
                font.pixelSize: 20
                text: root.step === "warn2" ? "Are you sure?"
                    : root.step === "working" ? "Uninstalling " + root.appName
                    : root.step === "loading" ? root.appName
                    : root.step === "done" ? root.appName
                    : "Uninstall " + root.appName + "?"
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                color: root.step === "warn" || root.step === "warn2" ? Phone.fg : Phone.dim
                font.family: Phone.font
                font.pixelSize: 15
                visible: text !== ""
                text: {
                    switch (root.step) {
                    case "ask":
                        return root.info.owner === "flatpak" ? "Flatpak app. Your data stays unless you tick the box."
                            : root.info.owner === "waydroid" ? "Android app. Android deletes this app's data with it."
                            : "System package " + root.info.name + ". Your files stay.";
                    case "warn":
                        return "This is part of the phone. Without it the phone may lose its interface or calls.";
                    case "warn2":
                        return root.info.name + " will be removed now. Bringing it back may need a computer.";
                    case "password":
                        return "Type your password to remove " + root.info.name + ".";
                    case "done":
                        return root.note;
                    }
                    return "";
                }
            }
            // only where the owner says for certain where the data is
            Item {
                width: parent.width
                height: 48
                visible: root.step === "ask" && (root.info.data || "") !== ""

                Rectangle {
                    id: tick
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 24
                    radius: 8
                    color: root.deleteData ? Phone.accent : "transparent"
                    border.width: 2
                    border.color: root.deleteData ? Phone.accent : Phone.dim
                }
                Text {
                    anchors { left: tick.right; right: parent.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                    wrapMode: Text.Wrap
                    color: Phone.fg
                    font.family: Phone.font
                    font.pixelSize: 15
                    text: "Also delete its data"
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.deleteData = !root.deleteData
                }
            }
            Rectangle {
                width: parent.width
                height: 52
                radius: 20
                visible: root.step === "password"
                color: Phone.mix("#262626", "#ececec")

                TextInput {
                    id: field
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: Phone.fg
                    selectionColor: Phone.accent
                    echoMode: TextInput.Password
                    passwordMaskDelay: 0
                    font.family: Phone.font
                    font.pixelSize: 17
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhHiddenText | Qt.ImhNoPredictiveText
                    onAccepted: if (text !== "") root.start()
                }
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                visible: root.step !== "working" && root.step !== "loading"

                Repeater {
                    model: root.step === "done" ? ["Close"]
                        : root.step === "warn" ? ["Cancel", "Continue"]
                        : root.step === "warn2" ? ["Keep it", "Uninstall anyway"]
                        : ["Cancel", "Uninstall"]

                    Rectangle {
                        required property string modelData
                        required property int index
                        readonly property bool main: index === 1

                        width: Math.max(96, label.implicitWidth + 32)
                        height: 52
                        radius: 20
                        color: press.pressed ? Phone.mix("#333333", "#dcdcdc") : main ? Phone.accent : Phone.mix("#262626", "#ececec")

                        Text {
                            id: label
                            anchors.centerIn: parent
                            color: parent.main && !press.pressed ? Phone.inkOnAccent : Phone.fg
                            font.family: Phone.font
                            font.pixelSize: 15
                            text: parent.modelData
                        }
                        MouseArea {
                            id: press
                            anchors.fill: parent
                            onClicked: {
                                if (!parent.main)
                                    Phone.removeEntry = null;
                                else if (root.step === "password")
                                    field.accepted();
                                else
                                    root.advance();
                            }
                        }
                    }
                }
            }
        }
    }
}
