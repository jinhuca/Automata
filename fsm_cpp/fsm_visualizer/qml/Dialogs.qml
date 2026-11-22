pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import FsmVis

// All of the app's dialogs (colour pickers, document save/load, the code
// preview, and the import/export file pickers), kept out of Main.qml. The
// window drives them through the functions below and supplies itself, the
// controller and the graph so handlers don't reach across files for ids.
Item {
    id: dlgs
    required property var win
    required property var ctl
    required property var graph
    required property var graph3d

    // ---- colour pickers (one reusable dialog) ----
    property string _colorRole: ""
    function openColor(role, current) { dlgs._colorRole = role; colorDlg.selectedColor = current; colorDlg.open() }
    ColorDialog {
        id: colorDlg
        onAccepted: {
            var role = dlgs._colorRole
            if (["initial", "accept", "current", "token", "node2d", "edge2d", "label2d", "state2d"].indexOf(role) >= 0)
                dlgs.graph.applyColor(role, selectedColor)              // a 2D role (incl. shared accents + per-state)
            else if (["node3d", "edge3d", "elabel"].indexOf(role) >= 0)
                dlgs.graph3d.applyColor3D(role, selectedColor)          // a 3D override role
            else if (role === "state")   dlgs.graph3d.applySelectedColor(selectedColor)
            else if (role === "edgesel") dlgs.graph3d.applySelectedEdgeColor(selectedColor)
            dlgs.graph.workingColor = selectedColor                     // shared paint colour (2D + 3D chips)
        }
    }

    // ---- document save / load (full JSON) ----
    // Save As: always prompt, prefilled with the current file (so it defaults to
    // the original name). Direct "Save" (no prompt) lives in the window.
    function saveAs() {
        if (dlgs.win.currentFile.length) saveDlg.selectedFile = dlgs.win.currentFile
        saveDlg.open()
    }
    function load() { loadDlg.open() }
    FileDialog {
        id: saveDlg
        fileMode: FileDialog.SaveFile
        nameFilters: ["FSM visualizer (*.json)"]
        defaultSuffix: "json"
        onAccepted: dlgs.win.saveDocument(selectedFile)
        onRejected: dlgs.win._cancelGuard()          // cancelled a Save-As during a guard: disarm
    }
    FileDialog {
        id: loadDlg
        fileMode: FileDialog.OpenFile
        nameFilters: ["FSM visualizer (*.json)"]
        // Confirm Save/Discard/Cancel first if the current document has unsaved edits.
        onAccepted: { var f = selectedFile; dlgs.win.confirmUnsaved(function () { dlgs.win.loadDocument(f) }) }
    }

    // ---- export ----
    function exportCpp() {
        dlgs.win.rebuild()                              // reflect current form text
        codeDialog.title = "Export C++  —  fsm::dfa"
        codeDialog.saveSuffix = "h"
        codeDialog.saveFilters = ["C++ header (*.h)", "C++ source (*.cpp)"]
        codeDialog.codeText = dlgs.ctl.exportCpp()
        codeDialog.open()
    }
    function exportDot() {
        dlgs.win.rebuild()
        codeDialog.title = "Export DOT  —  Graphviz"
        codeDialog.saveSuffix = "dot"
        codeDialog.saveFilters = ["Graphviz DOT (*.dot *.gv)"]
        codeDialog.codeText = dlgs.ctl.exportDot()
        codeDialog.open()
    }
    function exportPng() { exportPngDlg.open() }
    function exportSvg() { exportSvgDlg.open() }
    FileDialog {
        id: exportPngDlg
        fileMode: FileDialog.SaveFile
        nameFilters: ["PNG image (*.png)"]
        defaultSuffix: "png"
        onAccepted: dlgs.win.exportPng(selectedFile)
    }
    FileDialog {
        id: exportSvgDlg
        fileMode: FileDialog.SaveFile
        nameFilters: ["SVG image (*.svg)"]
        defaultSuffix: "svg"
        onAccepted: dlgs.ctl.saveTextToFile(selectedFile, dlgs.graph.exportSvg())
    }
    // Save whatever text the preview dialog holds (C++ or DOT); suffix/filters
    // follow codeDialog so one dialog serves both.
    FileDialog {
        id: saveTextDlg
        fileMode: FileDialog.SaveFile
        nameFilters: codeDialog.saveFilters
        defaultSuffix: codeDialog.saveSuffix
        onAccepted: dlgs.ctl.saveTextToFile(selectedFile, codeDialog.codeText)
    }

    // Read-only preview of generated code (C++ / DOT) with Copy + Save.
    Dialog {
        id: codeDialog
        property alias codeText: codeArea.text
        property string saveSuffix: "h"
        property var saveFilters: ["C++ header (*.h)", "C++ source (*.cpp)"]
        title: "Export"
        modal: true
        width: Math.min(720, dlgs.win.width - 80)
        height: Math.min(560, dlgs.win.height - 80)
        x: (dlgs.win.width - width) / 2
        y: (dlgs.win.height - height) / 2
        contentItem: ColumnLayout {
            spacing: 8
            Frame {
                Layout.fillWidth: true; Layout.fillHeight: true
                background: Rectangle { color: Theme.panelBg; border.color: Theme.panelBorder; radius: 6 }
                ScrollView {
                    anchors.fill: parent
                    clip: true
                    TextArea {
                        id: codeArea
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.NoWrap
                        font.family: "Consolas"; font.pixelSize: 13
                        color: Theme.textPrimary
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button {
                    text: "Copy"
                    onClicked: { codeArea.selectAll(); codeArea.copy(); codeArea.deselect() }
                }
                Button { text: "Save…"; onClicked: saveTextDlg.open() }
                Item { Layout.fillWidth: true }
                Button { text: "Close"; onClicked: codeDialog.close() }
            }
        }
    }

    // ---- import (C++ / DOT) ----
    function importCpp() { importCppDlg.open() }
    function importDot() { importDotDlg.open() }
    FileDialog {
        id: importCppDlg
        fileMode: FileDialog.OpenFile
        nameFilters: ["C++ (*.h *.cpp *.hpp *.cc)", "All files (*)"]
        onAccepted: dlgs.win.importDefFromUrl(selectedFile, "cpp")
    }
    FileDialog {
        id: importDotDlg
        fileMode: FileDialog.OpenFile
        nameFilters: ["Graphviz DOT (*.dot *.gv)", "All files (*)"]
        onAccepted: dlgs.win.importDefFromUrl(selectedFile, "dot")
    }
}
