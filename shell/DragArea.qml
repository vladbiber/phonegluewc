import QtQuick

// tap, hold, or rest then move: a quick move is left to whatever swipe is underneath
MouseArea {
    id: a

    // in reorder mode a move drags at once
    property bool immediate: false
    property Item space: parent
    property int liftMs: 220
    property int holdMs: 650
    property bool lifted: false
    property bool dragging: false
    property bool spent: false
    property real startX: 0
    property real startY: 0
    signal tapped(real x)
    signal held()
    signal dragStarted(point p)
    signal dragMoved(point p)
    signal dragEnded()

    preventStealing: immediate || lifted || dragging

    function end() {
        lift.stop();
        hold.stop();
        lifted = false;
        if (dragging) {
            dragging = false;
            dragEnded();
        }
    }
    Timer { id: lift; interval: a.liftMs; onTriggered: a.lifted = true }
    Timer {
        id: hold
        interval: a.holdMs
        onTriggered: {
            a.spent = true;
            a.held();
        }
    }
    onPressed: m => {
        startX = m.x;
        startY = m.y;
        spent = false;
        lift.restart();
        hold.restart();
    }
    onPositionChanged: m => {
        const p = mapToItem(space, m.x, m.y);
        if (dragging) {
            dragMoved(p);
        } else if (pressed && Math.hypot(m.x - startX, m.y - startY) >= 8) {
            hold.stop();
            spent = true;
            if (immediate || lifted) {
                dragging = true;
                dragStarted(p);
            } else {
                lift.stop();
            }
        }
    }
    onReleased: m => {
        const tap = !spent;
        end();
        if (tap)
            tapped(m.x);
    }
    onCanceled: end()
}
