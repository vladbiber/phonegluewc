import QtQuick

// one language; the name came from a registry, and T shows it as plain text
Column {
    id: root
    required property var lang
    property bool blocked: false
    signal download()
    signal remove()
    readonly property bool loading: LangJob.code === lang.code
    readonly property bool unavailable: lang.state === "unavailable"
    width: parent.width

    function size(b) {
        return b >= 1048576 ? Math.round(b / 1048576) + " MB" : Math.max(1, Math.round(b / 1024)) + " KB";
    }
    function brings() {
        const way = { both: "to and from English", toen: "to English only", fromen: "from English only" }[lang.way];
        if (!way)
            return lang.pack ? "Keyboard words only" : "";
        return lang.pack ? "Keyboard words and translation " + way : "Translation only, " + way;
    }
    readonly property string detail: {
        if (loading)
            return LangJob.total > 0 ? "Downloading " + size(LangJob.done) + " of " + size(LangJob.total) : "Starting the download";
        // offline the helper knows only that it is here, not what it brings
        if (lang.state === "installed")
            return lang.way === "installed" ? "Installed" : brings();
        if (unavailable)
            return lang.way === "none" ? "No translation model works on this phone" : brings();
        return brings() + ". " + (lang.bytes > 0 ? size(lang.bytes) + " download" : "Download size not known");
    }

    RowItem {
        label: root.lang.name
        sub: root.detail
        tappable: false
        opacity: root.unavailable ? 0.5 : 1
        Btn {
            visible: !root.unavailable
            text: root.loading ? "Cancel" : root.lang.state === "installed" ? "Remove" : "Download"
            confirm: !root.loading
            enabled_: root.loading || !root.blocked
            onTapped: {
                if (root.loading)
                    LangJob.cancel();
                else if (root.lang.state === "installed")
                    root.remove();
                else
                    root.download();
            }
        }
    }
    Rectangle {
        visible: root.loading
        x: S.margin
        width: parent.width - 2 * S.margin
        height: 4
        radius: 2
        color: S.surface
        Rectangle {
            width: LangJob.total > 0 ? parent.width * Math.min(1, LangJob.done / LangJob.total) : 0
            height: parent.height
            radius: 2
            color: S.accent
        }
    }
}
