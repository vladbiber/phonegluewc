// a plain text field that mirrors its text to a file, so a test can read what really arrived
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
	FloatingWindow {
		id: win
		visible: true
		color: "#101010"
		TextEdit {
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.top: parent.top
			height: win.secretOut ? 200 : parent.height
			anchors.margins: 16
			color: "white"
			font.pixelSize: 22
			focus: true
			wrapMode: TextEdit.Wrap
			onTextChanged: out.setText(text + "\n")
		}
		// with KBD_OUT_SECRET a second field below it, marked the way a password field is
		TextEdit {
			visible: win.secretOut
			anchors.left: parent.left
			anchors.right: parent.right
			y: 216
			height: 200
			color: "#c0c0c0"
			font.pixelSize: 22
			inputMethodHints: Qt.ImhSensitiveData | Qt.ImhHiddenText | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
			onTextChanged: out2.setText(text + "\n")
		}
		readonly property bool secretOut: Quickshell.env("KBD_OUT_SECRET") !== null && Quickshell.env("KBD_OUT_SECRET") !== ""
		FileView { id: out; path: Quickshell.env("KBD_OUT") }
		FileView { id: out2; path: Quickshell.env("KBD_OUT_SECRET") || "" }
	}
}
