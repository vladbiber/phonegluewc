// a plain top bar with a layer-shell exclusive zone, so the frame test does not depend on the real bar
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
	PanelWindow {
		anchors { top: true; left: true; right: true }
		implicitHeight: 34
		exclusiveZone: 34
		color: "#2040c0"
		WlrLayershell.namespace: "frame-bar"
	}
}
