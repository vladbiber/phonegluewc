// a page of known text in a real text field, so a test can compare what was read
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
	FloatingWindow {
		visible: true
		color: Quickshell.env("PAGE_BG")
		TextEdit {
			anchors.fill: parent
			anchors.margins: 24
			color: Quickshell.env("PAGE_FG")
			font.pixelSize: 22
			focus: true
			wrapMode: TextEdit.Wrap
			text: page.text()
		}
		FileView { id: page; path: Quickshell.env("PAGE_FILE"); blockLoading: true }
	}
}
