import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    IpcHandler {
        target: "lock"
        function lock(): void { Phone.lockOpen = true; }
    }
    // tests: the charger animation without a cable, as qs ipc call charge plug 62
    IpcHandler {
        target: "charge"
        function plug(level: int): void { Status.charged(true, level); }
        function unplug(level: int): void { Status.charged(false, level); }
    }
    IpcHandler {
        target: "home"
        function edit(): void { if (!Auth.greeter && !Phone.lockOpen) Screens.openEditor(); }
    }
    LazyLoader {
        active: Phone.lockOpen
        LockScreen {}
    }
    Variants {
        model: Auth.greeter ? Quickshell.screens : []
        Greeter {
            required property var modelData
            screen: modelData
        }
    }
    Variants {
        model: Auth.greeter ? [] : Quickshell.screens

        Scope {
            id: screenScope
            required property var modelData

            LazyLoader {
                active: Phone.wallpaper !== ""
                Wallpaper { screen: screenScope.modelData }
            }
            Home { screen: screenScope.modelData }
            Tray { screen: screenScope.modelData }
            CardLabels { screen: screenScope.modelData }
            StatusBar { screen: screenScope.modelData }
            LazyLoader {
                active: Status.panelLoaded
                QuickPanel { screen: screenScope.modelData }
            }
            // shortcut: the camera is on the first screen only, a phone has one; bind to the panel's output if a dock ever matters
            LazyLoader {
                active: Dyn.windowWanted && screenScope.modelData === Dyn.scr
                DynWindow { screen: screenScope.modelData }
            }
            LazyLoader {
                active: Dyn.open && !Phone.lockOpen && screenScope.modelData === Dyn.scr
                DynScrim { screen: screenScope.modelData }
            }
            LazyLoader {
                active: Status.chargeShowing && !Phone.lockOpen && screenScope.modelData === Dyn.scr
                PanelWindow {
                    screen: screenScope.modelData
                    anchors { top: true; bottom: true; left: true; right: true }
                    color: "transparent"
                    exclusionMode: ExclusionMode.Ignore
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.namespace: "phone-charge"
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    // seen, never touched
                    mask: Region {}
                    ChargeAnim { anchors.fill: parent }
                }
            }
            LazyLoader {
                active: Screens.editing && !Phone.lockOpen
                HomeEditor { screen: screenScope.modelData }
            }
            LazyLoader {
                active: Phone.menuLoaded
                AppMenu { screen: screenScope.modelData }
            }
            LazyLoader {
                active: Phone.pinId !== ""
                PinPopup { screen: screenScope.modelData }
            }
            LazyLoader {
                active: Phone.removeEntry !== null
                UninstallDialog { screen: screenScope.modelData }
            }
            LazyLoader {
                active: Phone.toastText !== "" && !Phone.lockOpen
                PanelWindow {
                    screen: screenScope.modelData
                    anchors { top: true; bottom: true; left: true; right: true }
                    color: "transparent"
                    exclusionMode: ExclusionMode.Ignore
                    mask: Region {}
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.namespace: "phone-toast"
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                    ButtonFeedback { anchors.fill: parent }
                }
            }
            LazyLoader {
                active: Droid.call !== null && !Phone.lockOpen && screenScope.modelData === Dyn.scr
                CallBanner { screen: screenScope.modelData }
            }
            LazyLoader {
                active: Status.rotateOffer !== "" && !Phone.lockOpen && screenScope.modelData === Dyn.scr
                RotateButton { screen: screenScope.modelData }
            }
        }
    }
}
