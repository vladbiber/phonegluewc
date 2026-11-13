import QtQuick

Page {
    id: root
    readonly property bool tool: S.has("mmcli")
    property bool loaded: false
    property string modem: ""
    property var info: ({})
    property string profile: ""
    property bool active: false
    property bool homeOnly: true
    property string error: ""

    function val(k) { const v = info[k]; return v && v !== "--" ? v : ""; }
    readonly property string state: val("modem.generic.state")
    readonly property string unlock: val("modem.generic.unlock-required")
    readonly property bool hasSim: val("modem.generic.sim") !== ""
    readonly property string simText: !hasSim ? "No SIM card"
        : unlock !== "" && unlock !== "none" ? "Locked, needs " + unlock : "Ready"

    function refresh() {
        if (tool)
            list.run(["mmcli", "-L", "-K"]);
        if (S.has("nmcli"))
            cons.run(["nmcli", "-t", "-f", "NAME,TYPE,ACTIVE", "con", "show"]);
    }
    onToolChanged: refresh()
    Component.onCompleted: refresh()
    Timer { running: root.tool; interval: 8000; repeat: true; onTriggered: root.refresh() }
    Cmd {
        id: list
        onDone: code => {
            const m = code === 0 && out.match(/\/Modem\/(\d+)/);
            root.modem = m ? m[1] : "";
            root.loaded = true;
            if (root.modem)
                details.run(["mmcli", "-m", root.modem, "-K"]);
            else
                root.info = ({});
        }
    }
    Cmd {
        id: details
        onDone: code => {
            if (code !== 0)
                return;
            const o = {};
            for (const l of S.lines(out)) {
                const at = l.indexOf(":");
                if (at > 0)
                    o[l.slice(0, at).trim()] = l.slice(at + 1).trim();
            }
            root.info = o;
        }
    }
    Cmd {
        id: cons
        onDone: {
            const p = S.lines(out).map(S.terse).find(f => f[1] === "gsm");
            root.profile = p ? p[0] : "";
            root.active = p ? p[2] === "yes" : false;
            if (root.profile)
                roam.run(["nmcli", "-g", "gsm.home-only", "con", "show", "id", root.profile]);
        }
    }
    Cmd { id: roam; onDone: root.homeOnly = out.trim() === "yes" }
    Cmd {
        id: action
        onDone: code => {
            root.error = code === 0 ? "" : S.firstLine(err, "The mobile network refused that change.");
            root.refresh();
        }
    }

    Note {
        visible: S.toolsReady && !root.tool
        problem: true
        text: "Mobile network is unavailable: the ModemManager tool (mmcli) is not installed."
    }
    Note {
        visible: root.tool && root.loaded && root.modem === ""
        problem: true
        text: "Mobile network is unavailable: no modem was found, or ModemManager is not running."
    }
    Note { text: root.error; problem: true }
    Column {
        visible: root.modem !== ""
        width: parent.width
        Section { text: "SIM" }
        RowItem { label: "SIM card"; sub: root.simText; tappable: false }
        RowItem { label: "Operator"; sub: root.val("modem.3gpp.operator-name") || "Not registered"; tappable: false }
        RowItem {
            label: "Signal"
            sub: root.val("modem.generic.signal-quality.value") ? root.val("modem.generic.signal-quality.value") + "%" : "Unknown"
            tappable: false
        }
        RowItem { label: "Network state"; sub: root.val("modem.3gpp.registration-state") || root.state || "Unknown"; tappable: false }
        Section { text: "Data" }
        RowItem {
            label: "Mobile data"
            sub: root.profile
            visible: root.profile !== ""
            onTapped: action.run(["nmcli", "con", root.active ? "down" : "up", "id", root.profile])
            Toggle { on: root.active }
        }
        RowItem {
            label: "Roaming"
            sub: "Use data on other networks when abroad"
            visible: root.profile !== ""
            onTapped: action.run(["nmcli", "con", "modify", "id", root.profile, "gsm.home-only", root.homeOnly ? "no" : "yes"])
            Toggle { on: !root.homeOnly }
        }
        Note {
            visible: root.profile === ""
            text: S.has("nmcli") ? "No mobile data profile exists yet, so data and roaming cannot be switched here."
                                 : "Mobile data and roaming need NetworkManager (the nmcli tool), and it is not installed."
        }
    }
}
