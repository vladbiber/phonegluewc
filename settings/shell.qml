import Quickshell
import Quickshell.Io
import QtQuick

// a program of its own: nothing here stays in the phone shell, and closing ends it
ShellRoot {
    settings.watchFiles: false

    IpcHandler {
        target: "settings"
        function open(page: string): void { S.open(page); }
        function page(): string { return S.page; }
    }

    FloatingWindow {
        id: win
        title: "Settings"
        color: S.black
        visible: true
        onClosed: S.quit()

        Loader {
            anchors.fill: parent
            focus: true
            source: S.page === "" ? "PageMain.qml" : "Page" + S.page.charAt(0).toUpperCase() + S.page.slice(1) + ".qml"
            Keys.onEscapePressed: S.back()
        }
    }
}
