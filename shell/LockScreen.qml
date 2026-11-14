import Quickshell
import Quickshell.Wayland
import QtQuick

// exists only while locked; if this process dies the compositor stays locked and starts a new one
WlSessionLock {
    id: lock
    locked: true

    WlSessionLockSurface {
        color: Phone.black
        // a new view at every screen-off: nothing typed, held or opened waits for the next wake
        Loader {
            id: view
            anchors.fill: parent
            // a Loader is a focus scope: without this the pad inside gets no hardware keys
            focus: true
            sourceComponent: LockView {
                onUnlocked: {
                    lock.locked = false;
                    Phone.lockOpen = false;
                }
            }
            Connections {
                target: Phone
                function onScreenOffChanged() {
                    if (Phone.screenOff) {
                        view.active = false;
                        view.active = true;
                    }
                }
            }
        }
        Loader {
            anchors.fill: parent
            active: Droid.call !== null
            source: "CallView.qml"
        }
    }
}
