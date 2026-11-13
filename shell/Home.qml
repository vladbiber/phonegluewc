import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// a widget of the home screen: above the wallpaper, and the cards never copy this layer
PanelWindow {
    id: root

    anchors { top: true; left: true; right: true }
    // only as tall as its widgets: a full screen of buffer would cost more than all of them
    implicitHeight: Math.min(screen ? screen.height : 10000, Math.max(240, Screens.top("home") + Screens.lowest("home") * Screens.rowH + 8))
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "phone-home"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // empty space only: a widget is not a way into the editor
    MouseArea {
        anchors.fill: parent
        property real x0: 0
        property real y0: 0
        onPressed: mouse => { x0 = mouse.x; y0 = mouse.y; }
        onPressAndHold: mouse => { if (!widgets.childAt(mouse.x, mouse.y)) Screens.openEditor(); }
        // the same sideways swipe the compositor sees below this window
        onReleased: mouse => {
            const dx = mouse.x - x0;
            if (Math.abs(dx) >= 60 && Math.abs(dx) > 1.5 * Math.abs(mouse.y - y0))
                root.turnPage(dx < 0 ? 1 : -1);
        }
    }

    function turnPage(dx) {
        if (Screens.editing || Phone.lockOpen || Phone.menuOpen || Phone.counts[Phone.ws] > 0 || !Screens.step("home", dx))
            return;
        widgets.x = dx * 48;
        widgets.opacity = 0;
        slideIn.restart();
    }
    ParallelAnimation {
        id: slideIn
        NumberAnimation { target: widgets; property: "x"; to: 0; duration: Phone.animationsConf === "off" ? 0 : 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: widgets; property: "opacity"; to: 1; duration: Phone.animationsConf === "off" ? 0 : 220 }
    }
    component PageSeq: FileView {
        property int dx
        property string seq: ""
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (seq !== "" && seq !== text())
                root.turnPage(dx);
            seq = text();
        }
    }
    PageSeq { path: Phone.stateDir + "/page-prev"; dx: -1 }
    PageSeq { path: Phone.stateDir + "/page-next"; dx: 1 }

    // below this window the compositor sees the hold and counts it here
    property string editSeq: ""
    FileView {
        path: Phone.stateDir + "/edit"
        watchChanges: true
        preload: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (root.editSeq !== "" && root.editSeq !== text() && !Phone.lockOpen)
                Screens.openEditor();
            root.editSeq = text();
        }
    }

    ScreenWidgets {
        id: widgets
        width: root.width
        height: root.screen ? root.screen.height : root.height
        live: !Screens.editing && !Phone.lockOpen && !(Phone.counts[Phone.ws] > 0)
    }
}
