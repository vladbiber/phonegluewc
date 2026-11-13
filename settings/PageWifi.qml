import Quickshell.Io
import QtQuick

Page {
    id: root
    readonly property bool tool: S.has("nmcli")
    property bool loaded: false
    property bool radio: true
    property var nets: []
    property var profiles: []
    property string iface: ""
    property string expanded: ""
    property string busy: ""
    property string error: ""
    property string asking: ""
    property bool askingWep: false
    property bool wasSaved: false

    function refresh() {
        status.run(["nmcli", "-t", "-f", "WIFI", "g"]);
        list.run(["nmcli", "-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "dev", "wifi", "list"]);
        cons.run(["nmcli", "-t", "-f", "NAME,TYPE", "con", "show"]);
        devs.run(["nmcli", "-t", "-f", "DEVICE,TYPE", "dev"]);
    }
    function isSaved(ssid) { return profiles.includes(ssid); }
    function act(what, argv) {
        busy = what;
        error = "";
        action.run(argv);
    }
    function connect(net) {
        expanded = "";
        if (net.secure && !isSaved(net.ssid))
            ask(net);
        else
            act(net.ssid, ["nmcli", "-w", "30", "dev", "wifi", "connect", net.ssid]);
    }
    function ask(net) {
        asking = net.ssid;
        askingWep = net.wep;
        pw.text = "";
        pw.forceActiveFocus();
    }
    function submit() {
        wasSaved = isSaved(asking);
        busy = asking;
        error = "";
        secret.text_ = pw.text;
        pw.text = "";
        pw.focus = false;
        secret.command = wasSaved ? ["nmcli", "-w", "30", "--ask", "con", "up", "id", asking]
                                  : ["nmcli", "-w", "30", "--ask", "dev", "wifi", "connect", asking];
        secret.ssid = asking;
        asking = "";
        secret.stdinEnabled = true;
        secret.running = true;
    }
    function failure(text) {
        return /secrets|password|psk|802-11-wireless-security/i.test(text) ? "Wrong password, or the network refused it."
             : S.firstLine(text, "The network did not accept the connection.");
    }

    Timer {
        running: root.tool && root.busy === "" && root.asking === ""
        interval: 8000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
    Cmd {
        id: status
        onDone: code => {
            root.radio = out.trim() === "enabled";
            if (code !== 0)
                root.error = S.firstLine(err, "NetworkManager did not answer. Is it running?");
        }
    }
    Cmd {
        id: list
        onDone: code => {
            if (code !== 0)
                return;
            const best = {};
            for (const l of S.lines(out)) {
                const f = S.terse(l);
                const n = { active: f[0] === "*", signal: parseInt(f[1]) || 0, secure: f[2] !== "" && f[2] !== "--", wep: /WEP/.test(f[2]), ssid: f[3] || "" };
                if (n.ssid !== "" && (!best[n.ssid] || n.active || (n.signal > best[n.ssid].signal && !best[n.ssid].active)))
                    best[n.ssid] = n;
            }
            root.nets = Object.values(best).sort((a, b) => b.active - a.active || b.signal - a.signal);
            root.loaded = true;
        }
    }
    Cmd {
        id: cons
        onDone: root.profiles = S.lines(out).map(S.terse).filter(f => f[1] === "802-11-wireless").map(f => f[0])
    }
    Cmd {
        id: devs
        onDone: {
            const d = S.lines(out).map(S.terse).find(f => f[1] === "wifi");
            root.iface = d ? d[0] : "";
        }
    }
    Cmd {
        id: action
        onDone: code => {
            if (code !== 0) {
                root.error = root.failure(err);
                if (/secrets/i.test(err)) {
                    const net = root.nets.find(n => n.ssid === root.busy);
                    if (net)
                        root.ask(net);
                }
            }
            root.busy = "";
            root.refresh();
        }
    }
    // the password goes down stdin, so it is on no command line
    Process {
        id: secret
        property string text_: ""
        property string ssid: ""
        environment: ({ LC_ALL: "C" })
        stderr: StdioCollector { id: secretErr }
        onStarted: {
            write(text_ + "\n");
            text_ = "";
            stdinEnabled = false;
        }
        onExited: code => {
            if (code !== 0) {
                root.error = root.failure(secretErr.text);
                // a refused new network leaves a profile with the wrong password behind
                if (!root.wasSaved)
                    action.run(["nmcli", "con", "delete", "id", ssid]);
            }
            root.busy = "";
            root.refresh();
        }
    }

    Note {
        visible: S.toolsReady && !root.tool
        problem: true
        text: "Wi-Fi settings need NetworkManager (the nmcli tool), and it is not installed."
    }
    Note { text: root.error; problem: true }
    RowItem {
        visible: root.tool
        label: "Wi-Fi"
        sub: root.radio ? "" : "Off"
        onTapped: {
            root.radio = !root.radio;
            root.act("", ["nmcli", "radio", "wifi", root.radio ? "on" : "off"]);
        }
        Toggle { on: root.radio }
    }
    Section {
        visible: root.tool && root.radio
        text: root.loaded ? "Networks" : "Looking for networks"
    }
    Repeater {
        model: root.tool && root.radio ? root.nets : []
        delegate: Column {
            id: netRow
            required property var modelData
            readonly property bool saved: root.isSaved(modelData.ssid)
            width: parent ? parent.width : 0
            RowItem {
                label: netRow.modelData.ssid
                sub: root.busy === netRow.modelData.ssid ? "Connecting"
                     : netRow.modelData.active ? "Connected"
                     : netRow.saved ? "Saved" : netRow.modelData.secure ? "Password needed" : "Open network"
                active: netRow.modelData.active
                icon: netRow.modelData.signal > 66 ? "wifi3" : netRow.modelData.signal > 33 ? "wifi2" : "wifi1"
                onTapped: root.expanded = root.expanded === netRow.modelData.ssid ? "" : netRow.modelData.ssid
            }
            Flow {
                visible: root.expanded === netRow.modelData.ssid
                x: S.margin
                width: parent.width - 2 * S.margin
                height: visible ? implicitHeight + 10 : 0
                spacing: 8
                Btn {
                    visible: !netRow.modelData.active
                    primary: true
                    text: "Connect"
                    enabled_: root.busy === ""
                    onTapped: root.connect(netRow.modelData)
                }
                Btn {
                    visible: netRow.modelData.active && root.iface !== ""
                    text: "Disconnect"
                    onTapped: {
                        root.expanded = "";
                        root.act("", ["nmcli", "dev", "disconnect", root.iface]);
                    }
                }
                Btn {
                    visible: netRow.saved
                    text: "Forget"
                    confirm: true
                    onTapped: {
                        root.expanded = "";
                        root.act("", ["nmcli", "con", "delete", "id", netRow.modelData.ssid]);
                    }
                }
            }
        }
    }
    T {
        visible: root.tool && root.radio && root.loaded && root.nets.length === 0
        x: S.margin
        width: parent.width - 2 * S.margin
        color: S.grey
        text: "No networks found."
    }
    Item {
        visible: root.tool && root.radio
        width: parent.width
        height: 72
        Btn {
            x: S.margin
            y: 12
            text: "Scan again"
            onTapped: root.act("", ["nmcli", "dev", "wifi", "rescan"])
        }
    }

    // on top of the page and high on the screen, so the keyboard does not cover it
    overlay: Rectangle {
        anchors.fill: parent
        visible: root.asking !== ""
        color: S.black
        MouseArea { anchors.fill: parent }
        Column {
            anchors { top: parent.top; topMargin: 16; left: parent.left; right: parent.right; leftMargin: S.margin; rightMargin: S.margin }
            spacing: 16
            T { width: parent.width; color: S.grey; font.pixelSize: 14; text: "Password for" }
            T { width: parent.width; font.pixelSize: 22; text: root.asking }
            Rectangle {
                width: parent.width
                height: 52
                radius: 26
                color: S.surface
                TextInput {
                    id: pw
                    anchors { fill: parent; leftMargin: 22; rightMargin: 22 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: S.white
                    font.family: S.font
                    font.pixelSize: 17
                    echoMode: show.on ? TextInput.Normal : TextInput.Password
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhHiddenText
                    Keys.onReturnPressed: if (join.enabled_) root.submit()
                }
            }
            Row {
                spacing: 12
                Toggle { id: show; anchors.verticalCenter: parent.verticalCenter; MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: show.on = !show.on } }
                T { anchors.verticalCenter: parent.verticalCenter; text: "Show password"; font.pixelSize: 15; wrapMode: Text.NoWrap }
            }
            T {
                width: parent.width
                visible: !root.askingWep && pw.text.length > 0 && pw.text.length < 8
                color: S.grey
                font.pixelSize: 14
                text: "At least 8 characters."
            }
            Row {
                spacing: 8
                Btn {
                    id: join
                    primary: true
                    text: "Connect"
                    enabled_: root.askingWep ? pw.text.length > 0 : pw.text.length >= 8
                    onTapped: root.submit()
                }
                Btn {
                    text: "Cancel"
                    onTapped: {
                        pw.text = "";
                        pw.focus = false;
                        root.asking = "";
                    }
                }
            }
        }
    }
}
