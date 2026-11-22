import QtQuick
import QtQuick.Controls

// The on-canvas control layer for the DFA view. Most controls now live docked in
// the side panel's "Control" tab (see Controls2D.qml); only the always-on Run
// pane and the run-trace line stay on the canvas. `gv` is a back-reference to the
// GraphView root; the panes read its theme/state (gv.paneBg, gv.ctl, …) and write
// its pane-position properties (gv.ctrlX, …) so layout persistence stays owned by
// GraphView.
Item {
    id: root
    property var gv
    anchors.fill: parent

    // Drag grip shared by the panes; emits the clamped new top-left.
    component Grip: MouseArea {
        property var gv
        property Item pane
        signal movedTo(real nx, real ny)
        width: 16; height: gv.btnH
        cursorShape: Qt.SizeAllCursor
        property real ox: 0; property real oy: 0
        onPressed: function (m) { var g = mapToItem(gv, m.x, m.y); ox = g.x - pane.x; oy = g.y - pane.y; }
        onPositionChanged: function (m) {
            if (!pressed) return;
            var g = mapToItem(gv, m.x, m.y);
            movedTo(Math.max(0, Math.min(gv.width - pane.width, g.x - ox)),
                    Math.max(0, Math.min(gv.height - pane.height, g.y - oy)));
        }
        Text { anchors.centerIn: parent; text: "⠿"; color: gv.paneTextMuted; font.pixelSize: 14 }
    }
    // Uniform pane button.
    component PaneBtn: Button { property var gv; implicitHeight: gv.btnH }

    // ControlPane — run status + Run/Stop/Reset. Default: bottom-centre (trace below).
    // The Current label and the ACCEPTING badge are fixed-width so the pane never
    // resizes as the state name / accepting status changes during a run.
    Rectangle {
        id: controlPane
        z: 61; radius: 8; height: gv.paneH          // always visible
        color: gv.paneBg; border.color: gv.paneBorder; border.width: 1
        width: ctrlRow.width + 16
        x: gv.paneClamp(gv.ctrlX, (gv.width - width) / 2, gv.width - width)
        y: gv.paneClamp(gv.ctrlY, gv.height - height - 24, gv.height - height)
        Row {
            id: ctrlRow; anchors.centerIn: parent; spacing: 8
            Grip { gv: root.gv; pane: controlPane; onMovedTo: function (nx, ny) { gv.ctrlX = nx; gv.ctrlY = ny } }
            Text {
                width: 206; elide: Text.ElideRight          // fixed width: no reflow on state change
                anchors.verticalCenter: parent.verticalCenter
                text: (gv.ctl && gv.ctl.built) ? ("Current: " + gv.visualCurrent) : "Not built"
                color: (gv.ctl && gv.ctl.built) ? gv.currentColor : gv.paneTextMuted
                font.bold: true; font.pixelSize: 13
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                radius: 4; opacity: (gv.ctl && gv.ctl.built) ? 1 : 0
                width: 94; height: 22                        // fixed (fits "Not Accepting")
                color: gv.visualAccepted ? "#14532d" : "#4c1d1d"
                Text {
                    anchors.centerIn: parent
                    text: gv.visualAccepted ? "Accepting" : "Not Accepting"
                    color: gv.visualAccepted ? "#86efac" : "#fca5a5"
                    font.pixelSize: 11; font.bold: true
                }
            }
            PaneBtn { gv: root.gv; text: "Run"; enabled: gv.ctl && gv.ctl.built && !gv.ctl.running; onClicked: gv.ctl.runWord(gv.runWord) }
            PaneBtn { gv: root.gv; text: "Stop"; enabled: gv.ctl && gv.ctl.running; onClicked: gv.ctl.stopRun() }
            PaneBtn { gv: root.gv; text: "Reset"; enabled: gv.ctl && gv.ctl.built; onClicked: gv.ctl.reset() }
        }
    }

    // Run trace, below ControlPane (follows it vertically). Left-aligned; the path
    // scrolls FIFO — oldest states drop off the left as new ones arrive (ElideLeft),
    // so the most recent stay visible. The "Trace:" label is a fixed leading element
    // so it isn't elided.
    Row {
        id: traceBar
        visible: gv.ctl && gv.ctl.built && gv.ctl.path.length > 1
        z: 60
        x: 12
        y: controlPane.y + controlPane.height + 9
        width: gv.width - 24
        spacing: 6
        Text {
            id: traceLabel
            anchors.verticalCenter: parent.verticalCenter
            text: "Trace:"; color: gv.paneText; font.pixelSize: 12; font.bold: true; font.family: "Consolas"
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: traceBar.width - traceLabel.width - traceBar.spacing
            elide: Text.ElideLeft                 // FIFO: oldest states scroll off the left
            horizontalAlignment: Text.AlignLeft
            text: gv.ctl ? gv.ctl.path.join("  →  ") : ""
            color: gv.paneText; font.pixelSize: 12; font.bold: true; font.family: "Consolas"
        }
    }
}
