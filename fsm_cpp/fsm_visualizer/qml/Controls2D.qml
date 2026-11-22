pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import FsmVis

// Docked 2D diagram controls for the side panel's "Control" tab. These used to
// float on the canvas (see CanvasPanes.qml); they now live here as a tidy
// vertical list. `gv` is the GraphView instance, `win` the app window, `dlgs`
// the shared dialogs — all supplied by Main.
ColumnLayout {
    id: c
    property var gv
    property var win
    property var dlgs
    spacing: 12

    // Titled section with a divider; instance children append below the header.
    component Section: ColumnLayout {
        id: sec
        property string title: ""
        Layout.fillWidth: true
        spacing: 6
        Label { text: sec.title; color: Theme.textPrimary; font.bold: true; font.pixelSize: 12 }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.panelBorder }
    }

    // Uniform tool button: same height for all, square for icon buttons. (`square`
    // is used rather than `icon` — Button already has a FINAL `icon` group property.)
    component TBtn: Button {
        implicitHeight: 32
        property bool square: false
        implicitWidth: square ? 36 : implicitContentWidth + leftPadding + rightPadding
        font.pixelSize: square ? 16 : 13
    }

    // Colour swatch: single-click paints the working colour, double-click opens
    // the picker (a double-click also fires one `clicked`, so a timer arbitrates).
    component Swatch: Column {
        id: sw
        property color swatch: "#000000"
        property bool ring: false
        property string label: ""
        property string role: ""
        property string tip: ""
        spacing: 3
        Timer { id: swT; interval: 250; onTriggered: c.gv.paintRole(sw.role) }
        Rectangle {
            width: 18; height: 18; radius: sw.ring ? 9 : 4
            anchors.horizontalCenter: parent.horizontalCenter
            color: sw.ring ? "transparent" : sw.swatch
            border.color: sw.ring ? sw.swatch : Theme.panelBorder
            border.width: sw.ring ? 2 : 1
            MouseArea {
                id: swMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: swT.restart()
                onDoubleClicked: { swT.stop(); c.dlgs.openColor(sw.role, c.gv.colorForRole(sw.role)) }
            }
            ToolTip.visible: sw.tip.length > 0 && swMa.containsMouse; ToolTip.text: sw.tip; ToolTip.delay: 400
        }
        Label { text: sw.label; color: Theme.textMuted; font.pixelSize: 9
                anchors.horizontalCenter: parent.horizontalCenter }
    }

    // ---- Document ----
    Section {
        title: "Document"
        Label {
            Layout.fillWidth: true; elide: Text.ElideMiddle
            text: (c.gv && c.gv.docName.length) ? c.gv.docName : "(unsaved)"
            color: Theme.textPrimary; font.pixelSize: 13; font.bold: true
        }
        Label {
            Layout.fillWidth: true; wrapMode: Text.WordWrap
            text: (c.gv && c.gv.ctl ? c.gv.ctl.states.length : 0) + " states · "
                  + (c.gv && c.gv.ctl ? c.gv.ctl.symbols.length : 0) + " symbols · "
                  + (c.gv ? c.gv.transList.length : 0) + " transitions"
            color: Theme.textMuted; font.pixelSize: 12
        }
    }

    // ---- Colours ----
    Section {
        title: "Colours"
        Flow {
            Layout.fillWidth: true; spacing: 12
            Swatch { swatch: c.gv ? c.gv.initialColor : "#000"; label: "init";   role: "initial"; tip: "Initial-state marker (entry arrow)" }
            Swatch { ring: true; swatch: c.gv ? c.gv.acceptColor : "#000"; label: "accept"; role: "accept"; tip: "Accepting-state ring" }
            Swatch { swatch: c.gv ? c.gv.currentColor : "#000"; label: "active"; role: "current"; tip: "Active state during a run" }
            Swatch { swatch: c.gv ? c.gv.tokenColor : "#000"; label: "token";    role: "token"; tip: "Run token" }
            Swatch { swatch: c.gv ? c.gv.nodeFillEff : "#000"; label: "state";    role: "node2d"; tip: "State fill colour" }
            Swatch { swatch: c.gv ? c.gv.edgeColorEff : "#000"; label: "edge";    role: "edge2d"; tip: "Transition line & arrowhead" }
            Swatch { swatch: c.gv ? c.gv.labelTextEff : "#000"; label: "label";   role: "label2d"; tip: "Transition (edge) label text" }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Label { text: "paint:"; color: Theme.textMuted; font.pixelSize: 12 }
            Rectangle {
                width: 18; height: 18; radius: 4
                color: c.gv ? c.gv.workingColor : "#000"; border.color: Theme.textMuted; border.width: 1
                MouseArea { id: wcMa; anchors.fill: parent; hoverEnabled: true }
                ToolTip.visible: wcMa.containsMouse; ToolTip.delay: 400
                ToolTip.text: "Working colour · single-click a swatch to paint it with this; double-click any swatch to change it"
            }
            Item { Layout.fillWidth: true }
            TBtn { text: "Reset colours"; onClicked: c.gv.resetColors() }
        }
    }

    // ---- All states (global size + fill) ----
    Section {
        title: "All states"
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Label { text: "Size"; color: Theme.textMuted; font.pixelSize: 12 }
            Slider {
                Layout.fillWidth: true
                from: 0.5; to: 2.0; value: c.gv ? c.gv.allStateScale : 1
                onMoved: if (c.gv) c.gv.allStateScale = value
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Label { text: "Fill"; color: Theme.textMuted; font.pixelSize: 12 }
            Rectangle {   // global state fill — click to set (affects every state)
                width: 20; height: 20; radius: 4
                color: c.gv ? c.gv.nodeFillEff : "#000"
                border.color: Theme.panelBorder; border.width: 1
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: c.dlgs.openColor("node2d", c.gv.nodeFillEff) }
            }
            Item { Layout.fillWidth: true }
            TBtn { text: "Reset all"; onClicked: c.gv.resetAllStates()
                   ToolTip.visible: hovered; ToolTip.text: "Reset size + fill for every state (clears per-state overrides too)" }
        }
    }

    // ---- Selection (only while a state is selected: click a state circle) ----
    Section {
        title: "Selected state"
        visible: c.gv && c.gv.selectedState !== ""
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Label {
                Layout.fillWidth: true; elide: Text.ElideRight
                text: "state: " + (c.gv ? c.gv.selectedState : "")
                color: Theme.textPrimary; font.pixelSize: 12; font.bold: true
            }
            Rectangle {   // per-state fill colour — click to change
                width: 20; height: 20; radius: 4
                color: c.gv ? c.gv.selectedStateColor() : "#000"
                border.color: Theme.panelBorder; border.width: 1
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: c.dlgs.openColor("state2d", c.gv.selectedStateColor()) }
            }
            TBtn { text: "Reset"; onClicked: c.gv.resetSelectedState() }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Label { text: "Size"; color: Theme.textMuted; font.pixelSize: 12 }
            Slider {
                Layout.fillWidth: true
                from: 0.5; to: 2.0; value: c.gv ? (c.gv.rev, c.gv.selectedStateSize()) : 1
                onMoved: if (c.gv) c.gv.setSelectedStateSize(value)
            }
        }
    }

    // ---- Edges ----
    Section {
        title: "Edges"
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            ComboBox {
                Layout.preferredWidth: 120
                model: ["Curved", "Straight"]
                currentIndex: (c.gv && c.gv.edgeStyle === "straight") ? 1 : 0
                onActivated: if (c.gv) c.gv.edgeStyle = (currentIndex === 0 ? "curved" : "straight")
            }
            Label { text: "curve"; color: Theme.textMuted; font.pixelSize: 12
                    opacity: (c.gv && c.gv.edgeStyle === "curved") ? 1 : 0.4 }
            Slider {
                Layout.fillWidth: true
                from: 0; to: 60; value: c.gv ? c.gv.curvature : 0
                enabled: c.gv && c.gv.edgeStyle === "curved"
                onMoved: if (c.gv) c.gv.curvature = value
            }
        }
    }

    // ---- Layout & view ----
    Section {
        title: "Layout & view"
        Flow {
            Layout.fillWidth: true; spacing: 6
            TBtn { square: true; text: "↶"; enabled: c.win && c.win.canUndo; onClicked: c.win.undo()
                   ToolTip.visible: hovered; ToolTip.text: "Undo (Ctrl+Z)" }
            TBtn { square: true; text: "↷"; enabled: c.win && c.win.canRedo; onClicked: c.win.redo()
                   ToolTip.visible: hovered; ToolTip.text: "Redo (Ctrl+Y)" }
            TBtn { text: "Re-layout"; onClicked: c.gv.relayoutAll()
                   ToolTip.visible: hovered; ToolTip.text: "Auto-arrange the states on a grid" }
            TBtn { square: true; text: "▦"; checkable: true; checked: c.gv && c.gv.showGrid
                   onToggled: c.gv.showGrid = checked
                   ToolTip.visible: hovered; ToolTip.text: "Toggle background grid" }
            TBtn { square: true; text: "⏎"; checkable: true; checked: c.gv && c.gv.showActions
                   onToggled: c.gv.showActions = checked
                   ToolTip.visible: hovered; ToolTip.text: "Toggle entry/exit action labels" }
            TBtn { text: (c.win && c.win.canvasFull) ? "Exit full screen" : "Full screen"
                   onClicked: c.win.canvasFull = !c.win.canvasFull
                   ToolTip.visible: hovered; ToolTip.text: "Maximise the canvas (Esc to exit)" }
        }
    }

    // ---- Zoom ----
    Section {
        title: "Zoom"
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            TBtn { square: true; text: "−"; onClicked: c.gv.zoomBy(1 / 1.2)
                   ToolTip.visible: hovered; ToolTip.text: "Zoom out" }
            Label {
                Layout.preferredWidth: 54; horizontalAlignment: Text.AlignHCenter
                text: Math.round((c.gv ? c.gv.zoom : 1) * 100) + "%"; color: Theme.textPrimary; font.pixelSize: 12
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: c.gv.fitView() }
            }
            TBtn { square: true; text: "+"; onClicked: c.gv.zoomBy(1.2)
                   ToolTip.visible: hovered; ToolTip.text: "Zoom in" }
            Item { Layout.fillWidth: true }
            TBtn { text: "Fit"; onClicked: c.gv.fitView()
                   ToolTip.visible: hovered; ToolTip.text: "Fit diagram to view" }
        }
    }

    // ---- Animation ----
    Section {
        title: "Animation"
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Label { text: "Speed"; color: Theme.textMuted; font.pixelSize: 12 }
            Slider {
                Layout.fillWidth: true
                from: 1; to: 10; value: (c.gv && c.gv.ctl) ? 1650 / c.gv.ctl.stepInterval : 2.357
                onMoved: if (c.gv && c.gv.ctl) c.gv.ctl.stepInterval = Math.round(1650 / value)
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Label { text: "Token"; color: Theme.textMuted; font.pixelSize: 12 }
            ComboBox {
                Layout.fillWidth: true
                model: ["Dot", "Ring", "Comet", "Chevron"]
                currentIndex: c.gv ? ["dot", "ring", "comet", "chevron"].indexOf(c.gv.tokenStyle) : 0
                onActivated: if (c.gv) c.gv.tokenStyle = ["dot", "ring", "comet", "chevron"][currentIndex]
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Label { text: "Token size"; color: Theme.textMuted; font.pixelSize: 12 }
            Slider {
                Layout.fillWidth: true
                from: 0.5; to: 2.0; value: c.gv ? c.gv.tokenScale : 1
                onMoved: if (c.gv) c.gv.tokenScale = value
            }
        }
    }
}
