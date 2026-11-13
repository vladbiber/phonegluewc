import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import QtQuick

// lock screen PIN and fingerprints; both start with the account password
Page {
    id: root

    property bool pinSet: false
    property bool fpDevice: false
    property int fingers: 0
    // "" | password | pin1 | pin2 | enroll
    property string step: ""
    property string goal: ""
    property string problem: ""
    property string firstPin: ""
    property string enrollText: ""
    property bool checking: false
    readonly property string user: Quickshell.env("USER") || ""
    readonly property string mock: Quickshell.env("PHONE_AUTH_MOCK") || ""

    function refresh() { status.run(["phonepin", "status"]); fpList.run(["sh", "-c", 'command -v fprintd-list >/dev/null && exec fprintd-list "$1"', "sh", user]); }
    Component.onCompleted: refresh()

    Cmd {
        id: status
        onDone: root.pinSet = /\bpin=1\b/.test(out)
    }
    Cmd {
        id: fpList
        onDone: {
            root.fpDevice = /Using device/.test(out);
            root.fingers = (out.match(/^\s*- #\d+:/mg) || []).length;
        }
    }
    Cmd {
        id: clear
        onDone: code => { if (code !== 0) root.problem = "The PIN could not be removed."; root.refresh(); }
    }
    Cmd {
        id: fpDelete
        onDone: code => { if (code !== 0) root.problem = "The fingerprints could not be removed."; root.refresh(); }
    }

    function begin(g) {
        problem = "";
        goal = g;
        step = "password";
        field.text = "";
        field.forceActiveFocus();
    }
    function cancel() {
        if (enroll.running)
            enroll.running = false;
        field.text = "";
        firstPin = "";
        field.focus = false;
        step = "";
    }
    function submit() {
        const v = field.text;
        if (step === "password") {
            if (v === "" || checking)
                return;
            field.text = "";
            checking = true;
            if (mock !== "")
                passwordDone(v === mock);
            else {
                pam.pending = v;
                if (!pam.start()) {
                    pam.pending = "";
                    passwordDone(false);
                }
            }
        } else if (step === "pin1") {
            if (!/^[0-9]{4,6}$/.test(v))
                return;
            firstPin = v;
            field.text = "";
            step = "pin2";
        } else if (step === "pin2") {
            field.text = "";
            if (v !== firstPin) {
                firstPin = "";
                problem = "The PINs were not the same. Enter a new PIN.";
                step = "pin1";
                return;
            }
            setPin.pending = v;
            firstPin = "";
            setPin.running = true;
            cancel();
        }
    }
    function passwordDone(ok) {
        checking = false;
        if (!ok) {
            problem = "Wrong password.";
            field.forceActiveFocus();
            return;
        }
        problem = "";
        if (goal === "pin") {
            step = "pin1";
            field.forceActiveFocus();
        } else {
            field.focus = false;
            step = "enroll";
            enrollText = "Put your finger on the sensor.";
            enroll.passed = 0;
            enroll.running = true;
        }
    }

    PamContext {
        id: pam
        property string pending: ""
        onPamMessage: if (responseRequired) { respond(pending); pending = ""; }
        onCompleted: result => { pending = ""; root.passwordDone(result === PamResult.Success); }
        onError: { pending = ""; root.passwordDone(false); }
    }
    // the PIN goes in on stdin, never on the command line
    Process {
        id: setPin
        property string pending: ""
        command: ["phonepin", "set"]
        stdinEnabled: true
        onRunningChanged: if (running) {
            write(pending + "\n");
            pending = "";
            stdinEnabled = false;
        }
        onExited: code => {
            setPin.stdinEnabled = true;
            if (code !== 0)
                root.problem = "The PIN could not be saved.";
            root.refresh();
        }
    }
    Process {
        id: enroll
        property int passed: 0
        property bool completed: false
        command: ["fprintd-enroll"]
        onRunningChanged: if (running) completed = false
        stdout: SplitParser {
            onRead: line => {
                const m = /Enroll result: (\S+)/.exec(line);
                if (!m)
                    return;
                const r = m[1];
                if (r === "enroll-stage-passed")
                    root.enrollText = "Lift and touch again (" + (++enroll.passed) + ").";
                else if (r === "enroll-completed") {
                    enroll.completed = true;
                    root.enrollText = "";
                } else if (r === "enroll-retry-scan" || r === "enroll-swipe-too-short" || r === "enroll-finger-not-centered" || r === "enroll-remove-and-retry")
                    root.enrollText = "Try again, cover the whole sensor.";
                else if (r === "enroll-duplicate")
                    root.enrollText = "This finger is already added.";
            }
        }
        onExited: {
            if (root.step === "enroll") {
                root.problem = enroll.completed ? "" : (root.enrollText === "This finger is already added." ? root.enrollText : "The finger was not added.");
                root.step = "";
            }
            root.refresh();
        }
    }

    Section { text: "Screen lock" }
    Chips {
        options: [{ value: "password", label: "Password" }, { value: "pin", label: "PIN" }]
        current: root.pinSet ? "pin" : "password"
        onPicked: v => {
            if (v === "pin" && !root.pinSet)
                root.begin("pin");
            else if (v === "password" && root.pinSet)
                clear.run(["phonepin", "clear"]);
        }
    }
    RowItem {
        visible: root.pinSet
        label: "Change PIN"
        chevron: true
        onTapped: root.begin("pin")
    }
    Note {
        text: root.pinSet ? "The lock screen asks for the PIN. After a restart it asks for the password once." : "The lock screen asks for the password."
    }
    Section { visible: root.fpDevice; text: "Fingerprint" }
    RowItem {
        visible: root.fpDevice
        label: "Fingerprints"
        sub: root.fingers === 0 ? "None added" : root.fingers === 1 ? "1 finger" : root.fingers + " fingers"
        tappable: false
        Row {
            spacing: 8
            Btn { text: "Add"; onTapped: root.begin("finger") }
            Btn { visible: root.fingers > 0; text: "Remove all"; confirm: true; onTapped: fpDelete.run(["fprintd-delete", root.user]) }
        }
    }
    Note { text: root.step === "" ? root.problem : ""; problem: true }

    overlay: Rectangle {
        anchors.fill: parent
        visible: root.step !== ""
        color: S.black
        MouseArea { anchors.fill: parent }
        Column {
            anchors { top: parent.top; topMargin: 16; left: parent.left; right: parent.right; leftMargin: S.margin; rightMargin: S.margin }
            spacing: 16
            T {
                width: parent.width
                font.pixelSize: 22
                text: root.step === "password" ? "Your password" : root.step === "pin1" ? "New PIN, 4 to 6 digits" : root.step === "pin2" ? "The PIN again" : "Add a fingerprint"
            }
            Rectangle {
                width: parent.width
                height: 52
                radius: 26
                color: S.surface
                visible: root.step !== "enroll"
                TextInput {
                    id: field
                    anchors { fill: parent; leftMargin: 22; rightMargin: 22 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: S.white
                    font.family: S.font
                    font.pixelSize: 17
                    echoMode: TextInput.Password
                    passwordMaskDelay: 0
                    maximumLength: root.step === "password" ? 512 : 6
                    validator: RegularExpressionValidator { regularExpression: root.step === "password" ? /.*/ : /[0-9]{0,6}/ }
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhHiddenText
                        | (root.step === "password" ? 0 : Qt.ImhDigitsOnly)
                    Keys.onReturnPressed: root.submit()
                    Keys.onEnterPressed: root.submit()
                }
            }
            T { width: parent.width; visible: root.step === "enroll"; text: root.enrollText }
            T { width: parent.width; visible: root.problem !== ""; color: S.accent; font.pixelSize: 15; text: root.problem }
            Row {
                spacing: 8
                Btn {
                    visible: root.step !== "enroll"
                    primary: true
                    text: root.step === "password" ? "Next" : root.step === "pin1" ? "Next" : "Save"
                    enabled_: !root.checking && (root.step === "password" ? field.text !== "" : /^[0-9]{4,6}$/.test(field.text))
                    onTapped: root.submit()
                }
                Btn { text: "Cancel"; onTapped: { root.problem = ""; root.cancel(); } }
            }
        }
    }
}
