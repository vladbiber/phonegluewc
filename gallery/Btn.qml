import QtQuick

// confirm: the first tap only asks, the second one acts, and asking wears off
Rectangle {
    id: root
    property string text: ""
    property bool primary: false
    property bool confirm: false
    property bool armed: false
    property bool enabled_: true
    signal tapped()
    width: label.implicitWidth + 40
    height: 48
    radius: 24
    color: !enabled_ ? S.surface : (primary || armed) ? S.accent : tap.pressed ? S.press : S.surface
    opacity: enabled_ ? 1 : 0.5
    T {
        id: label
        anchors.centerIn: parent
        text: root.armed ? "Tap again" : root.text
        color: root.enabled_ && (root.primary || root.armed) ? S.inkOnAccent : S.white
        font.pixelSize: 15
        wrapMode: Text.NoWrap
    }
    Timer { running: root.armed; interval: 3000; onTriggered: root.armed = false }
    MouseArea {
        id: tap
        anchors.fill: parent
        enabled: root.enabled_
        onClicked: {
            if (root.confirm && !root.armed) {
                root.armed = true;
                return;
            }
            root.armed = false;
            root.tapped();
        }
    }
}
