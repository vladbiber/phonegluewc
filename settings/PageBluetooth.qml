import QtQuick

Page {
    id: root
    readonly property bool tool: S.has("bluetoothctl")
    property bool loaded: false
    property bool controller: true
    property bool powered: false
    property bool scanning: false
    property var devices: []
    property string expanded: ""
    property string busy: ""
    property string error: ""

    function refresh() {
        show.run(["timeout", "4", "bluetoothctl", "show"]);
        if (powered)
            list.run([S.pset, "bt-list"]);
    }
    function act(mac, argv) {
        busy = mac;
        error = "";
        expanded = "";
        action.run(argv);
    }
    function ctl(verb, mac) { act(mac, ["timeout", "15", "bluetoothctl", verb, mac]); }

    Timer {
        running: root.tool
        interval: root.scanning ? 3000 : 8000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (root.busy === "") root.refresh()
    }
    Cmd {
        id: show
        onDone: code => {
            root.controller = code === 0 && /Controller /.test(out);
            root.powered = /Powered: yes/.test(out);
            root.loaded = true;
            if (root.powered && root.devices.length === 0)
                list.run([S.pset, "bt-list"]);
        }
    }
    Cmd {
        id: list
        onDone: code => {
            if (code !== 0)
                return;
            root.devices = S.lines(out).map(l => l.split("\t")).filter(f => f.length >= 6).map(f => ({
                mac: f[0], paired: f[1] === "yes", connected: f[2] === "yes", icon: f[3], battery: f[4], name: f[5]
            })).sort((a, b) => b.connected - a.connected || b.paired - a.paired);
        }
    }
    Cmd {
        id: action
        onDone: code => {
            if (code !== 0)
                root.error = S.firstLine(err || out, "Bluetooth did not manage that.");
            root.busy = "";
            root.refresh();
        }
    }
    // the timeout ends it anyway if the page has already gone
    Cmd {
        id: scan
        onDone: root.scanning = false
    }

    Note {
        visible: S.toolsReady && !root.tool
        problem: true
        text: "Bluetooth settings need the bluetoothctl tool, and it is not installed."
    }
    Note {
        visible: root.tool && root.loaded && !root.controller
        problem: true
        text: "No Bluetooth adapter was found, or the Bluetooth service is not running."
    }
    Note { text: root.error; problem: true }
    RowItem {
        visible: root.tool && root.controller
        label: "Bluetooth"
        sub: root.powered ? "" : "Off"
        onTapped: {
            root.powered = !root.powered;
            root.act("", [S.pset, "bt-power", root.powered ? "on" : "off"]);
        }
        Toggle { on: root.powered }
    }
    Section {
        visible: root.tool && root.controller && root.powered
        text: root.devices.length > 0 ? "Devices" : root.scanning ? "Looking for devices" : "No devices yet"
    }
    Repeater {
        model: root.tool && root.controller && root.powered ? root.devices : []
        delegate: Column {
            id: devRow
            required property var modelData
            width: parent ? parent.width : 0
            RowItem {
                label: devRow.modelData.name
                sub: root.busy === devRow.modelData.mac ? "Working"
                     : (devRow.modelData.connected ? "Connected" : devRow.modelData.paired ? "Paired" : "Not paired")
                       + (devRow.modelData.battery ? ", battery " + devRow.modelData.battery + "%" : "")
                active: devRow.modelData.connected
                icon: /audio|head/.test(devRow.modelData.icon) ? "headset" : /keyboard/.test(devRow.modelData.icon) ? "keyboard"
                      : /mouse/.test(devRow.modelData.icon) ? "mouse" : /phone/.test(devRow.modelData.icon) ? "phone"
                      : /computer/.test(devRow.modelData.icon) ? "laptop" : "bt"
                onTapped: root.expanded = root.expanded === devRow.modelData.mac ? "" : devRow.modelData.mac
            }
            Flow {
                visible: root.expanded === devRow.modelData.mac
                x: S.margin
                width: parent.width - 2 * S.margin
                height: visible ? implicitHeight + 10 : 0
                spacing: 8
                Btn {
                    visible: !devRow.modelData.paired
                    primary: true
                    text: "Pair"
                    onTapped: root.act(devRow.modelData.mac, [S.pset, "bt-pair", devRow.modelData.mac])
                }
                Btn {
                    visible: devRow.modelData.paired && !devRow.modelData.connected
                    primary: true
                    text: "Connect"
                    onTapped: root.ctl("connect", devRow.modelData.mac)
                }
                Btn {
                    visible: devRow.modelData.connected
                    text: "Disconnect"
                    onTapped: root.ctl("disconnect", devRow.modelData.mac)
                }
                Btn {
                    visible: devRow.modelData.paired
                    text: "Forget"
                    confirm: true
                    onTapped: root.ctl("remove", devRow.modelData.mac)
                }
            }
        }
    }
    Item {
        visible: root.tool && root.controller && root.powered
        width: parent.width
        height: 72
        Btn {
            x: S.margin
            y: 12
            text: root.scanning ? "Looking" : "Scan"
            enabled_: !root.scanning
            onTapped: {
                root.scanning = true;
                scan.run(["timeout", "14", "bluetoothctl", "--timeout", "12", "scan", "on"]);
            }
        }
    }
    Note {
        visible: root.tool && root.controller && root.powered
        text: "Devices that ask you to type a PIN cannot be paired from here yet."
    }
}
