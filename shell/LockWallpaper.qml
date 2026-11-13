import QtQuick

// the configured picture, or a field of dots that fades towards the bottom
Item {
    // the lock editor shows a picked one before it is saved
    property string path: Auth.config.wallpaper
    Rectangle { anchors.fill: parent; color: Phone.black }
    Canvas {
        anchors.fill: parent
        visible: parent.path === ""
        onPaint: {
            const ctx = getContext("2d");
            ctx.fillStyle = "#f5f5f5";
            for (let y = 8; y < height; y += 16)
                for (let x = 8; x < width; x += 16) {
                    ctx.globalAlpha = 0.16 * Math.max(0, 1 - y / (height * 0.62));
                    ctx.fillRect(x - 1, y - 1, 2, 2);
                }
        }
    }
    Image {
        anchors.fill: parent
        visible: status === Image.Ready
        source: parent.path ? "file://" + parent.path : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }
}
