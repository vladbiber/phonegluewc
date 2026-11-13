import Quickshell
import QtQuick

// the app's own icon, or its first letter when it has none
Item {
    id: root

    required property var entry
    property int size: 52
    readonly property string path: Phone.iconFor(entry)

    implicitWidth: size
    implicitHeight: size

    readonly property bool letter: image.status !== Image.Ready || Phone.faintIcons[path] === true

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Phone.card
        visible: root.letter

        Text {
            anchors.centerIn: parent
            text: root.entry ? root.entry.name.charAt(0).toUpperCase() : ""
            color: Phone.fg
            font.family: Phone.font
            font.pixelSize: Math.max(root.size * 0.42, 14)
        }
    }
    Image {
        id: image
        anchors.fill: parent
        visible: !root.letter
        source: root.path
        sourceSize: Qt.size(root.size * 3, root.size * 3)
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    // once per icon: drawn black on black, or not drawn at all, it would not be seen
    Loader {
        active: root.path !== "" && Phone.faintIcons[root.path] === undefined
        sourceComponent: Canvas {
            width: 16
            height: 16
            opacity: 0
            onAvailableChanged: if (available) loadImage(root.path)
            onImageLoaded: requestPaint()
            onPaint: {
                if (!isImageLoaded(root.path))
                    return;
                const ctx = getContext("2d");
                ctx.drawImage(root.path, 0, 0, width, height);
                const d = ctx.getImageData(0, 0, width, height).data;
                let seen = 0;
                for (let i = 0; i < d.length; i += 4)
                    if (d[i + 3] > 128 && 0.3 * d[i] + 0.6 * d[i + 1] + 0.1 * d[i + 2] >= 60)
                        seen++;
                const next = Object.assign({}, Phone.faintIcons);
                next[root.path] = seen < 16;
                Phone.faintIcons = next;
            }
        }
    }
}
