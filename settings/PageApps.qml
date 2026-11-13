import Quickshell
import QtQuick

Page {
    id: root
    readonly property var apps: DesktopEntries.applications.values.filter(a => !a.noDisplay).sort((a, b) => a.name.localeCompare(b.name))
    readonly property var browsers: apps.filter(a => a.categories.includes("WebBrowser"))
    readonly property var pinned: S.pinned
    function nameOf(id) {
        const a = apps.find(x => x.id === id);
        return a ? a.name : id;
    }
    function move(i, by) {
        const p = pinned.slice();
        const t = p[i];
        p[i] = p[i + by];
        p[i + by] = t;
        S.save(["pinned"].concat(p));
    }

    Section { text: "Default browser" }
    Repeater {
        model: root.browsers
        delegate: RowItem {
            required property var modelData
            label: modelData.name
            active: S.browser === modelData.id
            sub: active ? "Default" : ""
            onTapped: S.save(["browser", modelData.id])
        }
    }
    Note {
        visible: root.browsers.length === 0
        text: "No browser is installed."
    }
    Section { text: "Tray apps, up to 4" }
    Repeater {
        model: root.pinned
        delegate: RowItem {
            id: pinRow
            required property string modelData
            required property int index
            label: root.nameOf(modelData)
            tappable: false
            Row {
                spacing: 4
                Btn { text: "Up"; visible: pinRow.index > 0; onTapped: root.move(pinRow.index, -1) }
                Btn { text: "Remove"; onTapped: S.save(["pinned"].concat(root.pinned.filter(x => x !== pinRow.modelData))) }
            }
        }
    }
    Section { visible: root.pinned.length < 4; text: "Add to the tray" }
    Repeater {
        model: root.pinned.length < 4 ? root.apps.filter(a => !root.pinned.includes(a.id)) : []
        delegate: RowItem {
            required property var modelData
            label: modelData.name
            onTapped: S.save(["pinned"].concat(root.pinned, [modelData.id]))
        }
    }
    Section { text: "Older apps" }
    RowItem {
        label: "X11 apps"
        sub: "Opens apps made for X11 through xwayland-satellite; takes effect after a restart"
        onTapped: S.save(["set", "config", "xwayland", S.config.xwayland === "off" ? "on" : "off"])
        Toggle { on: S.config.xwayland !== "off" }
    }
}
