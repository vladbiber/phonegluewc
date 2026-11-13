import QtQuick

// list uses the network, so it runs only here, when the page opens or the person asks again
Page {
    id: root
    readonly property bool ready: S.toolsReady && S.has("phonekbd-lang")
    property string source: ""      // online, cached, cancelled, offline, or bad
    property var langs: []
    property string removeError: ""
    property bool opened: false
    readonly property bool blocked: LangJob.busy || remover.running

    function parse(text) {
        const lines = text.split("\n");
        const head = (lines[0] || "").match(/^S (online|cached|cancelled|offline)$/);
        if (!head)
            return { source: "bad", langs: [] };
        const found = [];
        for (const line of lines.slice(1)) {
            const f = line.startsWith("L ") ? line.slice(2).split("\t") : [];
            if (f.length !== 6 || found.length >= 256 || !LangJob.valid(f[0]) || !/^\d{1,15}$/.test(f[3]) || !/^[01]$/.test(f[5]))
                continue;
            // the offline list puts "installed" in the direction field
            if (["both", "toen", "fromen", "none", "installed"].indexOf(f[2]) < 0 || ["available", "installed", "unavailable"].indexOf(f[4]) < 0)
                continue;
            const name = f[1].replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, 40);
            found.push({ code: f[0], name: name || f[0], way: f[2], bytes: Number(f[3]), state: f[4], pack: f[5] === "1" });
        }
        return { source: head[1], langs: found };
    }
    function load() {
        if (ready)
            list.run(["phonekbd-lang", "list"]);
    }
    function ofState(s) { return langs.filter(l => l.state === s); }
    // both can fire as the page opens: list only once
    function open() {
        if (ready && !opened) {
            opened = true;
            load();
        }
    }

    onReadyChanged: open()
    Component.onCompleted: open()
    Connections {
        target: LangJob
        function onInstalled() { root.load(); }
    }
    Cmd {
        id: list
        onDone: code => {
            const r = code === 0 ? root.parse(out) : { source: "bad", langs: [] };
            root.source = r.source;
            root.langs = r.langs;
        }
    }
    Cmd {
        id: remover
        onDone: code => {
            root.removeError = code === 0 ? "" : "That language could not be removed.";
            root.load();
        }
    }

    Note {
        visible: S.toolsReady && !S.has("phonekbd-lang")
        problem: true
        text: "Adding languages needs phonekbd-lang, and it is not installed."
    }
    Note {
        visible: root.ready && root.source === "" && list.running
        text: "Checking which languages are available"
    }
    Note {
        problem: true
        text: !root.ready || list.running ? "" : ({
            offline: "You are offline. Only installed languages are shown. Connect to the internet to add more.",
            cached: "Could not reach the language list, so this is the last one saved. Downloads need a connection.",
            cancelled: "The check for languages was stopped.",
            bad: "The language list could not be read."
        })[root.source] || ""
    }
    Note {
        visible: LangJob.cancelled && !LangJob.busy
        text: "Download cancelled. Nothing was installed."
    }
    Note { problem: true; text: LangJob.busy ? "" : LangJob.error }
    Note { problem: true; text: root.removeError }
    RowItem {
        visible: root.ready && !list.running && root.source !== "online" && root.source !== ""
        label: "Check again"
        onTapped: root.load()
    }

    Section { visible: root.ofState("installed").length > 0; text: "Installed" }
    Repeater {
        model: root.ofState("installed")
        delegate: LangRow {
            required property var modelData
            lang: modelData
            blocked: root.blocked
            onRemove: { root.removeError = ""; remover.run(["phonekbd-lang", "remove", modelData.code]); }
        }
    }
    Section { visible: root.ofState("available").length > 0; text: "Add a language" }
    Repeater {
        model: root.ofState("available")
        delegate: LangRow {
            required property var modelData
            lang: modelData
            blocked: root.blocked
            onDownload: LangJob.install(modelData.code)
        }
    }
    Section { visible: root.ofState("unavailable").length > 0; text: "Not available" }
    Repeater {
        model: root.ofState("unavailable")
        delegate: LangRow {
            required property var modelData
            lang: modelData
            blocked: true
        }
    }
}
