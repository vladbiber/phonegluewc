// a window with one text field at its very bottom; FIELD_FS asks for fullscreen
import QtQuick
import QtQuick.Window
import Quickshell

ShellRoot {
	Window {
		id: win
		title: "field"
		visible: true
		color: "#808080"
		visibility: Quickshell.env("FIELD_FS") ? Window.FullScreen : Window.Windowed
		Rectangle {
			anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
			height: 60
			color: "#00c000"
			TextInput {
				id: field
				anchors.fill: parent
				focus: true
				Component.onCompleted: forceActiveFocus()
			}
		}
	}
}
