pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FsmVis

// Docked 3D diagram controls for the side panel's "Control" tab. These used to
// float on the 3D canvas (see GraphView3D.qml); they now live here as a tidy
// vertical list. `view` is the GraphView3D instance, `win` the app window,
// `dlgs` the shared dialogs — all supplied by Main.
ColumnLayout {
    id: c
    property var view
    property var win
    property var dlgs
    spacing: 12

    component Section: ColumnLayout {
        id: sec
        property string title: ""
        Layout.fillWidth: true
        spacing: 6
        Label { text: sec.title; color: Theme.textPrimary; font.bold: true; font.pixelSize: 12 }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.panelBorder }
    }

    // Labelled slider row.
    component SliderRow: RowLayout {
        id: sr
        property string label: ""
        property alias from: s.from
        property alias to: s.to
        property alias stepSize: s.stepSize
        property real value: 0
        property bool rounded: false
        signal moved(real v)
        Layout.fillWidth: true; spacing: 8
        Label { text: sr.label; color: Theme.textMuted; font.pixelSize: 12; Layout.preferredWidth: 60 }
        Slider { id: s; Layout.fillWidth: true; value: sr.value
                 onMoved: sr.moved(sr.rounded ? Math.round(value) : value) }
    }

    component Swatch: Column {
        id: sw
        property color swatch: "#000000"
        property string label: ""
        property string role: ""
        property string tip: ""
        spacing: 3
        Timer { id: swT; interval: 250; onTriggered: c.view.paintRole3D(sw.role) }
        Rectangle {
            width: 18; height: 18; radius: 4
            anchors.horizontalCenter: parent.horizontalCenter
            color: sw.swatch; border.color: Theme.panelBorder; border.width: 1
            MouseArea {
                id: swMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: swT.restart()
                onDoubleClicked: { swT.stop(); c.dlgs.openColor(sw.role, c.view.colorForRole3D(sw.role)) }
            }
            ToolTip.visible: sw.tip.length > 0 && swMa.containsMouse; ToolTip.text: sw.tip; ToolTip.delay: 400
        }
        Label { text: sw.label; color: Theme.textMuted; font.pixelSize: 9
                anchors.horizontalCenter: parent.horizontalCenter }
    }

    // Uniform tool button: same height for all, square for icon buttons. (`square`
    // is used rather than `icon` — Button already has a FINAL `icon` group property.)
    component TBtn: Button {
        implicitHeight: 32
        property bool square: false
        implicitWidth: square ? 36 : implicitContentWidth + leftPadding + rightPadding
        font.pixelSize: square ? 16 : 13
    }

    // ---- View & tools ----
    Section {
        title: "View & tools"
        Flow {
            Layout.fillWidth: true; spacing: 6
            TBtn { square: true; text: "↶"; enabled: c.win && c.win.canUndo; onClicked: c.win.undo()
                   ToolTip.visible: hovered; ToolTip.text: "Undo (Ctrl+Z)" }
            TBtn { square: true; text: "↷"; enabled: c.win && c.win.canRedo; onClicked: c.win.redo()
                   ToolTip.visible: hovered; ToolTip.text: "Redo (Ctrl+Y)" }
            TBtn { square: true; text: "−"; onClicked: c.view.zoomBy3D(1.2)
                   ToolTip.visible: hovered; ToolTip.text: "Zoom out" }
            TBtn { square: true; text: "+"; onClicked: c.view.zoomBy3D(1 / 1.2)
                   ToolTip.visible: hovered; ToolTip.text: "Zoom in" }
            TBtn { text: "Fit"; onClicked: c.view.fit() }
            TBtn { text: "Re-layout"; onClicked: c.view.relayoutAll() }
            TBtn { square: true; text: "▦"; checkable: true; checked: c.view && c.view.showGrid3d
                   onToggled: c.view.showGrid3d = checked
                   ToolTip.visible: hovered; ToolTip.text: "Toggle floor grid" }
            TBtn { square: true; text: "⊕"; checkable: true; checked: c.view && c.view.showAxes3d
                   onToggled: c.view.showAxes3d = checked
                   ToolTip.visible: hovered; ToolTip.text: "Toggle X/Y/Z axes" }
            TBtn { square: true; text: "ab"; checkable: true; checked: c.view && c.view.showEdgeLabels3d
                   onToggled: c.view.showEdgeLabels3d = checked
                   ToolTip.visible: hovered; ToolTip.text: "Toggle edge labels (off = faster with many edges)" }
            TBtn { text: (c.win && c.win.canvasFull) ? "Exit full screen" : "Full screen"
                   onClicked: c.win.canvasFull = !c.win.canvasFull
                   ToolTip.visible: hovered; ToolTip.text: "Maximise the canvas (Esc to exit)" }
        }
    }

    // ---- Style ----
    Section {
        title: "Style"
        SliderRow { label: "Size"; from: 0.2; to: 2.0; value: c.view ? c.view.nodeScale : 1
                    onMoved: function (v) { c.view.nodeScale = v } }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Label { text: "Edges"; color: Theme.textMuted; font.pixelSize: 12; Layout.preferredWidth: 60 }
            ComboBox {
                Layout.fillWidth: true; model: ["Straight", "Curved"]
                currentIndex: (c.view && c.view.edge3dStyle === "curved") ? 1 : 0
                onActivated: if (c.view) c.view.edge3dStyle = currentIndex === 1 ? "curved" : "straight"
            }
        }
        SliderRow { label: "Bend"; from: 0; to: 1; value: c.view ? c.view.curvature3d : 0.25
                    enabled: c.view && c.view.edge3dStyle === "curved"
                    onMoved: function (v) { c.view.curvature3d = v } }
        SliderRow { label: "Edge w"; from: 0.1; to: 2.0; value: c.view ? c.view.edgeScale : 1
                    onMoved: function (v) { c.view.edgeScale = v } }
        SliderRow { label: "Arrow"; from: 0.3; to: 2.0; value: c.view ? c.view.arrowScale3d : 1
                    onMoved: function (v) { c.view.arrowScale3d = v } }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Label { text: "Token"; color: Theme.textMuted; font.pixelSize: 12; Layout.preferredWidth: 60 }
            ComboBox {
                Layout.fillWidth: true; model: ["Dot", "Ring", "Comet", "Chevron"]
                currentIndex: c.view ? ["dot", "ring", "comet", "chevron"].indexOf(c.view.tokenStyle3d) : 0
                onActivated: if (c.view) c.view.tokenStyle3d = ["dot", "ring", "comet", "chevron"][currentIndex]
            }
        }
        SliderRow { label: "Token sz"; from: 0.1; to: 2.0; value: c.view ? c.view.tokenScale3d : 1
                    onMoved: function (v) { c.view.tokenScale3d = v } }
        SliderRow { label: "State lbl"; from: 8; to: 40; stepSize: 1; rounded: true
                    value: c.view ? c.view.nodeLabelSize : 24
                    onMoved: function (v) { c.view.nodeLabelSize = v } }
        SliderRow { label: "Edge lbl"; from: 8; to: 36; stepSize: 1; rounded: true
                    value: c.view ? c.view.edgeLabelSize : 18
                    onMoved: function (v) { c.view.edgeLabelSize = v } }
        SliderRow { label: "Along"; from: 0.1; to: 0.9; value: c.view ? c.view.labelAlong : 0.5
                    onMoved: function (v) { c.view.labelAlong = v } }
    }

    // ---- Colours ----
    Section {
        title: "Colours"
        Flow {
            Layout.fillWidth: true; spacing: 12
            Swatch { swatch: c.view ? c.view.colInitial : "#000"; label: "Init"; role: "initial"; tip: "Initial state" }
            Swatch { swatch: c.view ? c.view.colAccept : "#000";  label: "Acc";  role: "accept"; tip: "Accepting states" }
            Swatch { swatch: c.view ? c.view.colCurrent : "#000"; label: "Cur";  role: "current"; tip: "Current state (during a run)" }
            Swatch { swatch: c.view ? c.view.colToken : "#000";   label: "Tok";  role: "token"; tip: "Run token" }
            Swatch { swatch: c.view ? c.view.colNodeEff : "#000"; label: "Node"; role: "node3d"; tip: "Sphere base colour — plain states only\n(initial / accepting / current keep their own colours)" }
            Swatch { swatch: c.view ? c.view.colEdgeEff : "#000"; label: "Edge"; role: "edge3d"; tip: "Transition line & arrowhead" }
            Swatch { swatch: c.view ? c.view.colLabelEff : "#000"; label: "Lbl"; role: "elabel"; tip: "Edge label text" }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Label { text: "paint:"; color: Theme.textMuted; font.pixelSize: 12 }
            Rectangle {
                width: 18; height: 18; radius: 4
                color: c.view ? c.view.workingColor : "#000"; border.color: Theme.textMuted; border.width: 1
                MouseArea { id: wcMa; anchors.fill: parent; hoverEnabled: true }
                ToolTip.visible: wcMa.containsMouse; ToolTip.delay: 400
                ToolTip.text: "Working colour · single-click a swatch to paint it with this; double-click any swatch to change it"
            }
            Item { Layout.fillWidth: true }
            Button { text: "Reset colours"; onClicked: c.view.resetColors3D() }
        }
    }

    // ---- Selection (only while a state or edge is selected) ----
    Section {
        title: "Selection"
        visible: c.view && (c.view.selected !== "" || c.view.selectedEdge !== "")
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            visible: c.view && c.view.selected !== ""
            Label {
                Layout.fillWidth: true; elide: Text.ElideRight
                text: "state: " + (c.view ? c.view.selected : "")
                color: Theme.textPrimary; font.pixelSize: 12; font.bold: true
            }
            Rectangle {
                width: 20; height: 20; radius: 4
                color: (c.view && c.view.stateColors[c.view.selected] !== undefined) ? c.view.stateColors[c.view.selected] : (c.view ? c.view.colNodeEff : "#000")
                border.color: Theme.panelBorder; border.width: 1
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: c.dlgs.openColor("state", c.view.colorForRole3D("state")) }
            }
            Button { text: "Reset"; enabled: c.view && c.view.stateColors[c.view.selected] !== undefined
                     onClicked: c.view.clearSelectedColor() }
        }
        // Precise position of the selected state along the world X/Y/Z axes — easier
        // than dragging in 3D. Colours match the axis gizmo.
        ColumnLayout {
            Layout.fillWidth: true; spacing: 3
            visible: c.view && c.view.selected !== ""
            Label { text: "Position (X/Y/Z)"; color: Theme.textMuted; font.pixelSize: 11 }
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Label { text: "X"; color: "#ef4444"; font.pixelSize: 12; font.bold: true; Layout.preferredWidth: 12 }
                Slider { Layout.fillWidth: true; from: c.view ? -c.view.posRange : -400; to: c.view ? c.view.posRange : 400
                         value: c.view ? (c.view.posRev, c.view.selectedPos().x) : 0
                         onMoved: if (c.view) c.view.setSelectedAxis("x", value) }
                Label { Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight; color: Theme.textMuted; font.pixelSize: 11
                        text: c.view ? Math.round((c.view.posRev, c.view.selectedPos().x)) : "0" }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Label { text: "Y"; color: "#22c55e"; font.pixelSize: 12; font.bold: true; Layout.preferredWidth: 12 }
                Slider { Layout.fillWidth: true; from: c.view ? -c.view.posRange : -400; to: c.view ? c.view.posRange : 400
                         value: c.view ? (c.view.posRev, c.view.selectedPos().y) : 0
                         onMoved: if (c.view) c.view.setSelectedAxis("y", value) }
                Label { Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight; color: Theme.textMuted; font.pixelSize: 11
                        text: c.view ? Math.round((c.view.posRev, c.view.selectedPos().y)) : "0" }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Label { text: "Z"; color: "#3b82f6"; font.pixelSize: 12; font.bold: true; Layout.preferredWidth: 12 }
                Slider { Layout.fillWidth: true; from: c.view ? -c.view.posRange : -400; to: c.view ? c.view.posRange : 400
                         value: c.view ? (c.view.posRev, c.view.selectedPos().z) : 0
                         onMoved: if (c.view) c.view.setSelectedAxis("z", value) }
                Label { Layout.preferredWidth: 38; horizontalAlignment: Text.AlignRight; color: Theme.textMuted; font.pixelSize: 11
                        text: c.view ? Math.round((c.view.posRev, c.view.selectedPos().z)) : "0" }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            visible: c.view && c.view.selectedEdge !== ""
            Label {
                Layout.fillWidth: true; elide: Text.ElideRight
                text: {
                    if (!c.view || c.view.selectedEdge === "") return "";
                    var k = c.view.selectedEdge.split("\u001f");
                    return "edge: " + k[0] + " —" + k[1] + "→ " + k[2];
                }
                color: Theme.textPrimary; font.pixelSize: 12; font.bold: true
            }
            Rectangle {
                width: 20; height: 20; radius: 4
                color: (c.view && c.view.edgeColors[c.view.selectedEdge] !== undefined) ? c.view.edgeColors[c.view.selectedEdge] : (c.view ? c.view.colEdgeEff : "#000")
                border.color: Theme.panelBorder; border.width: 1
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: c.dlgs.openColor("edgesel", c.view.colorForRole3D("edgesel")) }
            }
            Button { text: "Reset"; enabled: c.view && c.view.edgeColors[c.view.selectedEdge] !== undefined
                     onClicked: c.view.clearSelectedEdgeColor() }
        }
        // Curve control point of the selected edge — drag along each world axis to
        // bend it (same as dragging the on-canvas curve handle). Colours = the axes.
        ColumnLayout {
            Layout.fillWidth: true; spacing: 3
            visible: c.view && c.view.selectedEdge !== ""
            Label { text: "Curve (X/Y/Z)"; color: Theme.textMuted; font.pixelSize: 11 }
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Label { text: "X"; color: "#ef4444"; font.pixelSize: 12; font.bold: true; Layout.preferredWidth: 12 }
                Slider { Layout.fillWidth: true; from: c.view ? -c.view.posRange : -400; to: c.view ? c.view.posRange : 400
                         value: c.view ? (c.view.posRev, c.view.selectedEdgeCtrl().x) : 0
                         onMoved: if (c.view) c.view.setSelectedEdgeAxis("x", value) }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Label { text: "Y"; color: "#22c55e"; font.pixelSize: 12; font.bold: true; Layout.preferredWidth: 12 }
                Slider { Layout.fillWidth: true; from: c.view ? -c.view.posRange : -400; to: c.view ? c.view.posRange : 400
                         value: c.view ? (c.view.posRev, c.view.selectedEdgeCtrl().y) : 0
                         onMoved: if (c.view) c.view.setSelectedEdgeAxis("y", value) }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Label { text: "Z"; color: "#3b82f6"; font.pixelSize: 12; font.bold: true; Layout.preferredWidth: 12 }
                Slider { Layout.fillWidth: true; from: c.view ? -c.view.posRange : -400; to: c.view ? c.view.posRange : 400
                         value: c.view ? (c.view.posRev, c.view.selectedEdgeCtrl().z) : 0
                         onMoved: if (c.view) c.view.setSelectedEdgeAxis("z", value) }
            }
        }
    }

    // ---- Help ----
    Label {
        Layout.fillWidth: true; wrapMode: Text.WordWrap
        text: "Click a state to select, drag to move (pins it) · drag empty space to orbit · right-drag (or Ctrl-drag) to pan · wheel or ± to zoom · Re-layout to reset."
        color: Theme.textMuted; font.pixelSize: 11
    }
}
