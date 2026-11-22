pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import FsmVis

ApplicationWindow {
    id: win
    visible: true
    x: 120
    y: 80
    width: 1200
    height: 820
    title: "fsm::dfa visualizer"
    color: Theme.windowBg
    flags: Qt.Window | Qt.FramelessWindowHint   // single custom title bar (the header)

    // Drive the Controls palette from the theme so buttons, combo boxes,
    // sliders and the zoom controls follow light/dark (it propagates to every
    // child control). Without this they fall back to the system palette.
    palette.window: Theme.windowBg
    palette.windowText: Theme.textPrimary
    palette.base: Theme.panelBg
    palette.alternateBase: Theme.windowBg
    palette.text: Theme.textPrimary
    palette.button: Theme.button
    palette.buttonText: Theme.textPrimary
    palette.highlight: Theme.accent
    palette.highlightedText: "#ffffff"
    palette.placeholderText: Theme.textMuted
    palette.mid: Theme.panelBorder
    palette.midlight: Theme.panelBorder
    palette.light: Theme.panelBg
    palette.dark: Theme.panelBorder

    // Persist window geometry + theme across runs (auto-saved by QtCore.Settings).
    Settings {
        property alias winX: win.x
        property alias winY: win.y
        property alias winWidth: win.width
        property alias winHeight: win.height
        property alias darkMode: win.darkMode
        property alias lastFile: win.currentFile   // reload the last document on launch
    }
    // Full working state, auto-saved on change and restored on launch (takes
    // precedence over the file, so in-app edits survive a restart).
    Settings {
        id: sessionStore
        category: "session"
        property string data: ""
    }
    // Persist the draggable canvas panes' positions across sessions.
    Settings {
        category: "canvasPanes"
        property alias infoX: graph.infoX
        property alias infoY: graph.infoY
        property alias legendX: graph.legendX
        property alias legendY: graph.legendY
        property alias edgeEditX: graph.edgeEditX
        property alias edgeEditY: graph.edgeEditY
        property alias layoutX: graph.layoutX
        property alias layoutY: graph.layoutY
        property alias zoomX: graph.zoomX
        property alias zoomY: graph.zoomY
        property alias ctrlX: graph.ctrlX
        property alias ctrlY: graph.ctrlY
        property alias animX: graph.animX
        property alias animY: graph.animY
    }
    // Persist the sizes of the three main panels (Definition | Canvas | Information)
    // as serialized SplitView states, so the user's resizing survives a restart.
    Settings {
        id: panelLayout
        category: "panels"
        property var outer   // Definition width  vs  the right column (SplitView state)
        property var right   // Canvas height      vs  Information height
    }

    // ---- Theme (light / dark) ----
    property bool darkMode: false

    // Path (URL string) of the document last saved or loaded; "" if none.
    property string currentFile: ""
    property bool modified: false        // in-app state has diverged from the saved file
    property bool _applying: false       // suppresses change tracking while (re)loading
    property bool _ready: false          // true once startup has fully settled
    // Close-confirmation flow: veto the first close when there are unsaved changes,
    // ask Save / Discard / Cancel, then close for real.
    property bool _forceClose: false     // true once the user has chosen Save or Discard
    property bool _discarding: false     // closing via Discard (drop the autosaved session)
    function currentFileName() {
        return currentFile.length ? decodeURIComponent(currentFile.toString().split('/').pop()) : ""
    }
    // Palette lives in the Theme singleton; feed it the current mode.
    Binding { target: Theme; property: "dark"; value: win.darkMode }

    FsmViewModel { id: ctl }

    function rebuild() {
        // Gate progressive instantiation around the build: renderCount drops to 0
        // before definitionChanged publishes the transitions (so a large machine
        // doesn't create every edge Shape synchronously), then populate() ramps
        // them in across event-loop ticks. Small machines show at once.
        graph.beginLoad()
        ctl.build(symbolsField.text, statesField.text, transitionsArea.text,
                  initialField.text, acceptField.text, actionsArea.text)
        graph.populate()
    }
    // On launch: restore the session (latest in-app edits) if present, else the
    // last file, else the prefilled example.
    Component.onCompleted: {
        var restored = false
        if (sessionStore.data && sessionStore.data.length) {
            try {
                var sd = JSON.parse(sessionStore.data)
                restored = applyDocument(sd)
                if (restored) { win.currentFile = sd.file || ""; win.modified = !!sd.modified }
            } catch (e) { restored = false }
        }
        if (!restored && win.currentFile.length) restored = loadDocument(win.currentFile)
        if (!restored) rebuild()
        // Defer so win.screen is valid, then fit the window to one screen.
        Qt.callLater(function () { win.clampToScreen(); win._ready = true })
    }
    onClosing: function (close) {        // confirm before losing unsaved changes
        if (win.modified && !win._forceClose) {
            close.accepted = false
            // Save -> close; Discard -> wipe the autosaved session so the edits don't
            // resurrect next launch, then close.
            confirmUnsaved(function () { win._forceClose = true; win.close() },
                           function () { sessionStore.data = ""; win._discarding = true; win._forceClose = true; win.close() })
            return
        }
        if (!win._discarding) autosaveSession()   // flush session on exit (not when discarding)
    }

    // ---- Generic "unsaved changes" guard (used by close and Load) ----
    // confirmUnsaved(proceed[, onDiscard]): if the document is clean, run proceed()
    // now; otherwise ask Save / Discard / Cancel and run the matching action.
    property var _saveProceed: null        // run after a successful Save
    property var _discardProceed: null     // run on Discard
    property bool _savePending: false      // a Save was requested as part of a guard
    function confirmUnsaved(proceed, onDiscard) {
        if (!win.modified) { proceed(); return }
        win._saveProceed = proceed
        win._discardProceed = onDiscard || proceed
        unsavedDlg.open()
    }
    function _doSaveProceed() {             // Save button
        win._savePending = true
        if (win.currentFile.length) saveDocument(win.currentFile)   // sync -> saveDocument finishes it
        else dlgs.saveAs()                                          // async -> saveDlg.onAccepted finishes it
    }
    function _finishSaveProceed() {         // called from saveDocument once the save is written
        win._savePending = false
        var p = win._saveProceed; win._saveProceed = null; win._discardProceed = null
        if (p) p()
    }
    function _doDiscardProceed() {          // Discard button
        var p = win._discardProceed; win._saveProceed = null; win._discardProceed = null
        if (p) p()
    }
    function _cancelGuard() { win._saveProceed = null; win._discardProceed = null; win._savePending = false }
    Dialog {
        id: unsavedDlg
        title: "Unsaved changes"
        modal: true
        x: Math.round((win.width - width) / 2)
        y: Math.round((win.height - height) / 2)
        standardButtons: Dialog.Save | Dialog.Discard | Dialog.Cancel
        // Fixed-width wrapper (an Item's implicitWidth is writable, unlike a Label's)
        // so WordWrap wraps within 360 without looping against the Dialog width.
        Item {
            implicitWidth: 360
            implicitHeight: unsavedMsg.implicitHeight
            Label {
                id: unsavedMsg
                anchors { left: parent.left; right: parent.right }
                text: "“" + (win.currentFileName() || "Untitled") + "” has unsaved changes.\nSave them before continuing?"
                color: Theme.textPrimary; wrapMode: Text.WordWrap
            }
        }
        onAccepted: win._doSaveProceed()      // Save
        onDiscarded: win._doDiscardProceed()  // Discard
        onRejected: win._cancelGuard()        // Cancel
    }

    // Track user edits -> session autosave + "modified" flag.
    Connections { target: graph; function onChanged() { win.markModified() } }
    Connections { target: graph; function onRunWordChanged() { win.markModified() } }
    Connections { target: graph3d; function onChanged() { win.markModified() } }   // 3D drags/style/colours
    Connections { target: ctl; function onStepIntervalChanged() { win.markModified() } }
    onDarkModeChanged: markModified()

    // Keep the window within one screen's work area (so restored/oversized
    // geometry can't spill onto another monitor or push the title-bar buttons
    // off-screen).
    function clampToScreen() {
        if (!win.screen) return
        var sw = win.screen.desktopAvailableWidth, sh = win.screen.desktopAvailableHeight
        var sx = win.screen.virtualX, sy = win.screen.virtualY
        if (win.width > sw) win.width = sw
        if (win.height > sh) win.height = sh
        if (win.x < sx) win.x = sx
        if (win.y < sy) win.y = sy
        if (win.x + win.width > sx + sw) win.x = sx + sw - win.width
        if (win.y + win.height > sy + sh) win.y = sy + sh - win.height
    }

    // Maximize/restore. Track state ourselves (frameless windows don't reliably
    // report Window.Maximized); Qt maximizes to the current monitor's work area.
    property bool _maxed: false
    function toggleMaximize() {
        if (win._maxed) { win.showNormal(); win._maxed = false }
        else { win.showMaximized(); win._maxed = true }
    }

    // Full-screen canvas: hide the form + run bar and take the window fullscreen.
    property bool canvasFull: false
    property bool use3D: false   // swap the 2D canvas for the 3D view (toggled from the title bar)
    onCanvasFullChanged: {
        visibility = canvasFull ? Window.FullScreen : Window.Windowed
        graph.fitMode = true     // re-fit the diagram to the new canvas size after switching
    }
    Shortcut { sequence: "Escape"; enabled: win.canvasFull; onActivated: win.canvasFull = false }
    Shortcut { sequences: [ StandardKey.Undo ]; onActivated: win.undo() }
    Shortcut { sequences: [ StandardKey.Redo ]; onActivated: win.redo() }

    // Frameless-window resize handles: thin strips on the side/bottom edges and
    // bottom corners (the top is the draggable title bar). Content-area children
    // (not the window overlay), transparent except the edges.
    Item {
        anchors.fill: parent
        z: 100
        MouseArea { width: 6; anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                    cursorShape: Qt.SizeHorCursor; onPressed: win.startSystemResize(Qt.LeftEdge) }
        MouseArea { width: 6; anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                    cursorShape: Qt.SizeHorCursor; onPressed: win.startSystemResize(Qt.RightEdge) }
        MouseArea { height: 6; anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    cursorShape: Qt.SizeVerCursor; onPressed: win.startSystemResize(Qt.BottomEdge) }
        MouseArea { width: 12; height: 12; anchors { left: parent.left; bottom: parent.bottom }
                    cursorShape: Qt.SizeBDiagCursor; onPressed: win.startSystemResize(Qt.LeftEdge | Qt.BottomEdge) }
        MouseArea { width: 12; height: 12; anchors { right: parent.right; bottom: parent.bottom }
                    cursorShape: Qt.SizeFDiagCursor; onPressed: win.startSystemResize(Qt.RightEdge | Qt.BottomEdge) }
    }

    // All dialogs (colour pickers, save/load, code preview, import/export
    // pickers) live in Dialogs.qml; the window drives them via dlgs.* functions.
    Dialogs { id: dlgs; win: win; ctl: ctl; graph: graph; graph3d: graph3d }

    // The full document (definition + layout + colors + run + theme + window).
    function documentData() {
        return {
            version: 1,
            definition: {
                symbols: symbolsField.text, states: statesField.text,
                transitions: transitionsArea.text, initial: initialField.text, accept: acceptField.text,
                actions: actionsArea.text
            },
            view: graph.exportState(),
            view3d: graph3d.exportState3D(),        // 3D dragged positions + camera
            run: { stepInterval: ctl.stepInterval, word: graph.runWord },
            ui: { dark: win.darkMode, use3D: win.use3D },
            window: { x: win.x, y: win.y, width: win.width, height: win.height }
        }
    }

    // Apply a document object to the UI. Guarded so it doesn't flag "modified".
    function applyDocument(d) {
        if (!d || !d.definition)
            return false
        win._applying = true
        var def = d.definition
        symbolsField.text = def.symbols || ""
        statesField.text = def.states || ""
        transitionsArea.text = def.transitions || ""
        initialField.text = def.initial || ""
        acceptField.text = def.accept || ""
        actionsArea.text = def.actions || ""
        rebuild()                                   // parse + rebuild nodes (ring layout)
        if (d.run && d.run.stepInterval) ctl.stepInterval = d.run.stepInterval
        graph.importState(d.view)                   // restore saved layout/colors/style
        graph3d.importState3D(d.view3d)             // restore 3D positions + camera (after rebuild)
        if (d.run && d.run.word !== undefined) graph.runWord = d.run.word
        if (d.ui && d.ui.dark !== undefined) win.darkMode = d.ui.dark
        if (d.ui && d.ui.use3D !== undefined) win.use3D = d.ui.use3D
        // NB: window geometry is NOT restored from the document (it caused the
        // window to spill across monitors). The window keeps its own size, which
        // is persisted separately via QtCore.Settings.
        // (Edges/curve and Speed/Token controls live in GraphView's on-canvas panes
        // and bind straight to graph.* / ctl.stepInterval, so importState + the
        // stepInterval assignment above update them automatically.)
        win._applying = false
        return true
    }

    function saveDocument(url) {
        ctl.saveToFile(url, documentData())
        win.currentFile = "" + url
        win.modified = false
        autosaveSession()
        if (win._savePending) Qt.callLater(win._finishSaveProceed)   // saved as part of an unsaved-changes guard
    }

    // "Save": write to the current file without prompting; if there is no file
    // yet, fall back to "Save As" (prompt).
    function save() {
        if (win.currentFile.length) saveDocument(win.currentFile)
        else dlgs.saveAs()
    }

    function loadDocument(url) {
        if (!applyDocument(ctl.loadFromFile(url)))
            return false
        win.currentFile = "" + url
        win.modified = false
        autosaveSession()
        return true
    }

    // Import a definition (C++ fsm::dfa or Graphviz DOT) into the form fields,
    // then build. Keeps the current view/layout (only the definition is
    // replaced); flagged modified since it's not the saved file.
    function importDefFromUrl(url, format) {
        var text = ctl.readTextFromFile(url)
        var def = (format === "dot") ? ctl.importDot(text) : ctl.importCpp(text)
        if (!def || def.states === undefined) {
            ctl.logMessage("[import] no " + (format === "dot" ? "DOT graph" : "fsm::dfa definition")
                           + " recognised")
            return false
        }
        symbolsField.text = def.symbols || ""
        statesField.text = def.states || ""
        transitionsArea.text = def.transitions || ""
        initialField.text = def.initial || ""
        acceptField.text = def.accept || ""
        rebuild()
        win.markModified()
        return true
    }

    // Export the diagram as a PNG. Grabs the canvas exactly as shown (use Fit
    // first to capture the whole diagram) at 2x for crispness, capped so a large
    // window doesn't exceed GPU texture limits.
    function exportPng(url) {
        var path = decodeURIComponent(("" + url).replace(/^file:\/\/\/?/, ""))
        var scale = Math.min(2, 4096 / Math.max(1, graph.width, graph.height))
        var ok = graph.grabToImage(function (result) {
            if (result && result.saveToFile(path))
                ctl.logMessage("[export] wrote " + path)
            else
                ctl.logMessage("[export] PNG save failed: " + path)
        }, Qt.size(Math.round(graph.width * scale), Math.round(graph.height * scale)))
        if (!ok) ctl.logMessage("[export] could not grab the diagram")
    }

    // ---- Session autosave (full working state) ----
    function autosaveSession() {
        var d = documentData()
        d.file = win.currentFile
        d.modified = win.modified
        sessionStore.data = JSON.stringify(d)
    }
    function markModified() {
        if (win._applying || !win._ready) return   // ignore startup / restore noise
        win.modified = true
        autosaveTimer.restart()
    }
    Timer {
        id: autosaveTimer; interval: 800
        onTriggered: { win.autosaveSession(); win.pushUndo() }   // one undo step per settled change
    }

    // ---- Undo / redo of the view layout (positions, edge overrides, style, colors) ----
    property var _undo: []        // history; last element is the current view
    property var _redo: []
    readonly property bool canUndo: _undo.length > 1
    readonly property bool canRedo: _redo.length > 0

    function _viewStr() { return JSON.stringify(graph.exportState()) }
    function initUndo() { _undo = [_viewStr()]; _redo = [] }   // reset baseline (on build/load)
    function pushUndo() {
        var s = _viewStr()
        if (_undo.length && _undo[_undo.length - 1] === s) return   // no change -> keep redo
        var u = _undo.slice(); u.push(s); if (u.length > 60) u.shift()
        _undo = u; _redo = []
    }
    function _applyView(s) {
        win._applying = true
        graph.importState(JSON.parse(s))   // Token combo (in GraphView) binds to graph.tokenStyle
        win._applying = false
        win.modified = true
        autosaveSession()
    }
    function undo() {
        if (_undo.length < 2) return
        var u = _undo.slice(); var cur = u.pop()
        var r = _redo.slice(); r.push(cur)
        _undo = u; _redo = r
        _applyView(u[u.length - 1])
    }
    function redo() {
        if (!_redo.length) return
        var r = _redo.slice(); var s = r.pop()
        var u = _undo.slice(); u.push(s)
        _undo = u; _redo = r
        _applyView(s)
    }
    // Reset the undo baseline whenever the definition is (re)built or loaded.
    Connections { target: ctl; function onDefinitionChanged() { Qt.callLater(win.initUndo) } }

    header: TitleBar {
        title: "fsm::dfa visualization   v" + Qt.application.version
        dark: win.darkMode
        use3D: win.use3D
        maximized: win._maxed
        onMoveRequested: win.startSystemMove()
        onMaximizeToggled: win.toggleMaximize()
        onMinimizeRequested: win.showMinimized()
        onCloseRequested: win.close()
        onThemeToggled: (checked) => win.darkMode = checked
        onView3DToggled: (checked) => win.use3D = checked
    }

    SplitView {
        id: outerSplit
        anchors.fill: parent
        anchors.margins: 14
        orientation: Qt.Horizontal
        // Restore / persist the Definition-vs-canvas split size.
        Component.onCompleted: if (panelLayout.outer !== undefined) restoreState(panelLayout.outer)
        onResizingChanged: if (!resizing) panelLayout.outer = saveState()

        // Wide, invisible-until-hovered resize handle (easy to grab).
        handle: Rectangle {
            id: hHandle
            implicitWidth: 14
            implicitHeight: 14
            color: "transparent"
            readonly property bool active: SplitHandle.hovered || SplitHandle.pressed
            readonly property bool held: SplitHandle.pressed
            Rectangle {
                anchors.centerIn: parent
                readonly property bool vertBar: hHandle.height >= hHandle.width
                width: vertBar ? 2 : 30
                height: vertBar ? 30 : 2
                radius: 1
                color: hHandle.held ? "#2563eb" : (hHandle.active ? "#cbd5e1" : "transparent")
            }
        }

        // ===== Definition form (Σ, S, δ, s₀, F) =====
        Frame {
            id: formPane
            SplitView.preferredWidth: 380
            SplitView.minimumWidth: 260
            visible: !win.canvasFull
            background: Rectangle { color: Theme.panelBg; border.color: Theme.panelBorder; radius: 8 }

            ColumnLayout {
                anchors.fill: parent
                spacing: 8

                // Side panel is tabbed: "Definition" (the Σ/S/δ/s₀/F form) and
                // "Control" (the diagram controls that used to float on the canvas;
                // the Control tab follows the 2D/3D switch).
                TabBar {
                    id: sideTabs
                    Layout.fillWidth: true
                    background: Rectangle { color: "transparent" }
                    TabButton { text: "Definition" }
                    TabButton { text: "Control" }
                }

                StackLayout {
                    id: sideStack
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: sideTabs.currentIndex

                // ===== Definition tab =====
                ColumnLayout {
                    spacing: 10

                // Scrollable input area: fills the slack so the action buttons below
                // stay pinned to the bottom of the panel and never get clipped.
                ScrollView {
                    id: defScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: defScroll.availableWidth
                        spacing: 10

                Label { text: "Symbols  (Σ, comma- or newline-separated)"; color: Theme.textMuted; font.pixelSize: 12 }
                Frame {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 96
                    background: Rectangle { color: Theme.panelBg; border.color: Theme.panelBorder; radius: 6 }
                    ScrollView {
                        anchors.fill: parent
                        clip: true
                        TextArea {
                            id: symbolsField
                            color: Theme.textPrimary
                            wrapMode: TextEdit.Wrap
                            text: ctl.savedSymbols
                            placeholderText: "e.g. 0, 1  (or one per line)"
                            onTextChanged: win.markModified()
                        }
                    }
                }

                Label { text: "States  (S, comma- or newline-separated)"; color: Theme.textMuted; font.pixelSize: 12 }
                Frame {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 96
                    background: Rectangle { color: Theme.panelBg; border.color: Theme.panelBorder; radius: 6 }
                    ScrollView {
                        anchors.fill: parent
                        clip: true
                        TextArea {
                            id: statesField
                            color: Theme.textPrimary
                            wrapMode: TextEdit.Wrap
                            text: ctl.savedStates
                            placeholderText: "e.g. even, odd  (or one per line)"
                            onTextChanged: win.markModified()
                        }
                    }
                }

                Label { text: "Transitions  (δ: from, symbol, to — one per line)"; color: Theme.textMuted; font.pixelSize: 12 }
                Frame {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    background: Rectangle { color: Theme.panelBg; border.color: Theme.panelBorder; radius: 6 }
                    ScrollView {
                        anchors.fill: parent
                        clip: true
                        TextArea {
                            id: transitionsArea
                            color: Theme.textPrimary
                            wrapMode: TextEdit.NoWrap
                            text: ctl.savedTransitions
                            onTextChanged: win.markModified()
                        }
                    }
                }

                Label { text: "Initial state  (s₀)"; color: Theme.textMuted; font.pixelSize: 12 }
                Frame {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    background: Rectangle { color: Theme.panelBg; border.color: Theme.panelBorder; radius: 6 }
                    ScrollView {
                        anchors.fill: parent
                        clip: true
                        TextArea {
                            id: initialField
                            color: Theme.textPrimary
                            wrapMode: TextEdit.Wrap
                            text: ctl.savedInitial
                            placeholderText: "e.g. even"
                            onTextChanged: win.markModified()
                        }
                    }
                }

                Label { text: "Final / accept states  (F, comma-separated)"; color: Theme.textMuted; font.pixelSize: 12 }
                Frame {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    background: Rectangle { color: Theme.panelBg; border.color: Theme.panelBorder; radius: 6 }
                    ScrollView {
                        anchors.fill: parent
                        clip: true
                        TextArea {
                            id: acceptField
                            color: Theme.textPrimary
                            wrapMode: TextEdit.Wrap
                            text: ctl.savedAccept
                            placeholderText: "e.g. even  (or one per line)"
                            onTextChanged: win.markModified()
                        }
                    }
                }

                Label { text: "State actions  (state : entry : exit — one per line)"; color: Theme.textMuted; font.pixelSize: 12 }
                Frame {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 90
                    background: Rectangle { color: Theme.panelBg; border.color: Theme.panelBorder; radius: 6 }
                    ScrollView {
                        anchors.fill: parent
                        clip: true
                        TextArea {
                            id: actionsArea
                            color: Theme.textPrimary
                            wrapMode: TextEdit.NoWrap
                            text: ctl.savedActions
                            placeholderText: "e.g. odd : parity = 1 :\n     even :  : reset counter"
                            onTextChanged: win.markModified()
                        }
                    }
                }

                // Fatal validation error (build blocked).
                Frame {
                    Layout.fillWidth: true
                    visible: ctl.error.length > 0
                    background: Rectangle { color: "#fef2f2"; border.color: "#b91c1c"; radius: 6 }
                    Label {
                        anchors.fill: parent
                        text: "✕  " + ctl.error
                        color: "#b91c1c"; font.pixelSize: 12; font.bold: true; wrapMode: Text.WordWrap
                    }
                }

                // Non-fatal warnings (built anyway).
                Frame {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(ctl.warnings.length * 20 + 34, 150)
                    visible: ctl.warnings.length > 0
                    background: Rectangle { color: "#fffbeb"; border.color: "#f59e0b"; radius: 6 }
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 2
                        Label {
                            text: "⚠  " + ctl.warnings.length + " warning(s)"
                            color: "#b45309"; font.pixelSize: 12; font.bold: true
                        }
                        ListView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                            model: ctl.warnings
                            delegate: Label {
                                required property string modelData
                                width: ListView.view.width
                                text: "• " + modelData
                                color: "#92400e"; font.pixelSize: 11; wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
                    }  // end scrollable input ColumnLayout
                }      // end defScroll ScrollView

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Button {
                        text: "Build / Update"
                        Layout.fillWidth: true
                        highlighted: true
                        onClicked: win.rebuild()
                    }
                    Button {
                        text: "Clear"
                        onClicked: {
                            symbolsField.text = ""; statesField.text = ""
                            transitionsArea.text = ""; initialField.text = ""; acceptField.text = ""
                            ctl.clearAll()
                            win.currentFile = ""        // drop the loaded file name from the info pane
                        }
                    }
                }

                // Save (no prompt) / Save As… (prompt) / Load the whole document.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Button { text: "Save"; Layout.fillWidth: true; onClicked: win.save() }
                    Button { text: "Save As…"; Layout.fillWidth: true; onClicked: dlgs.saveAs() }
                    Button { text: "Load…"; Layout.fillWidth: true; onClicked: dlgs.load() }
                }
                // Export / import to other formats.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Button {
                        id: exportBtn
                        Layout.fillWidth: true
                        text: "Export ▾"
                        onClicked: exportMenu.open()
                        Menu {
                            id: exportMenu
                            y: exportBtn.height          // open just below the button
                            MenuItem { text: "C++  (fsm::dfa)…"; onTriggered: dlgs.exportCpp() }
                            MenuItem { text: "DOT  (Graphviz)…"; onTriggered: dlgs.exportDot() }
                            MenuItem { text: "PNG image…";       onTriggered: dlgs.exportPng() }
                            MenuItem { text: "SVG image…";       onTriggered: dlgs.exportSvg() }
                        }
                    }
                    Button {
                        id: importBtn
                        Layout.fillWidth: true
                        text: "Import ▾"
                        onClicked: importMenu.open()
                        Menu {
                            id: importMenu
                            y: importBtn.height
                            MenuItem { text: "C++  (fsm::dfa)…"; onTriggered: dlgs.importCpp() }
                            MenuItem { text: "DOT  (Graphviz)…"; onTriggered: dlgs.importDot() }
                        }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    text: "File:  " + (win.currentFileName() || "(none — not saved)") + (win.modified ? "   •  modified" : "")
                    color: win.modified ? "#f59e0b" : Theme.textMuted
                    font.pixelSize: 11; elide: Text.ElideMiddle
                }
                }  // ===== end Definition tab =====

                    // ===== Control tab (docked diagram controls; follows 2D/3D) =====
                    ScrollView {
                        id: controlScroll
                        clip: true
                        contentWidth: availableWidth
                        ColumnLayout {
                            width: controlScroll.availableWidth
                            Controls2D { Layout.fillWidth: true; visible: !win.use3D; gv: graph; win: win; dlgs: dlgs }
                            Controls3D { Layout.fillWidth: true; visible: win.use3D; view: graph3d; win: win; dlgs: dlgs }
                        }
                    }
                }  // end StackLayout
            }
        }

        // ===== Graph + run controls (resizable vertical split) =====
        SplitView {
            id: rightSplit
            SplitView.fillWidth: true
            orientation: Qt.Vertical
            // Restore / persist the Canvas-vs-Information split size.
            Component.onCompleted: if (panelLayout.right !== undefined) restoreState(panelLayout.right)
            onResizingChanged: if (!resizing) panelLayout.right = saveState()

            handle: Rectangle {
                id: vHandle
                implicitWidth: 14
                implicitHeight: 14
                color: "transparent"
                readonly property bool active: SplitHandle.hovered || SplitHandle.pressed
                readonly property bool held: SplitHandle.pressed
                Rectangle {
                    anchors.centerIn: parent
                    readonly property bool vertBar: vHandle.height >= vHandle.width
                    width: vertBar ? 2 : 30
                    height: vertBar ? 30 : 2
                    radius: 1
                    color: vHandle.held ? "#2563eb" : (vHandle.active ? "#cbd5e1" : "transparent")
                }
            }

            Frame {
                id: graphPane
                SplitView.fillHeight: true
                SplitView.minimumHeight: 160
                clip: true   // nothing in the graph pane may spill past its border on resize
                background: Rectangle { color: Theme.panelBg; border.color: Theme.panelBorder; radius: 8 }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 6

                    // 2D ↔ 3D is toggled from the title bar. Diagram controls live
                    // in draggable on-canvas panes (available in both modes).
                    GraphView {
                        id: graph
                        visible: !win.use3D
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ctl: ctl
                        canvasBg: Theme.panelBg
                        nodeFill: Theme.nodeFill
                        nodeBorder: Theme.nodeBorder
                        nodeText: Theme.nodeText
                        edgeColor: Theme.edge
                        labelBg: Theme.labelBg
                        labelBorder: Theme.labelBorder
                        labelText: Theme.labelText
                        gridMinor: Theme.gridMinor
                        gridMajor: Theme.gridMajor
                        // --- on-canvas control panes (both windowed & full-screen) ---
                        paneBg: Qt.rgba(Theme.panelBg.r, Theme.panelBg.g, Theme.panelBg.b, 0.92)
                        paneBorder: Theme.panelBorder
                        paneText: Theme.textPrimary
                        paneTextMuted: Theme.textMuted
                        canvasFull: win.canvasFull
                        docName: win.currentFileName().replace(/\.json$/i, "")   // hide the .json extension on-canvas
                        canUndo: win.canUndo
                        canRedo: win.canRedo
                        onUndoRequested: win.undo()
                        onRedoRequested: win.redo()
                        onFullScreenToggleRequested: win.canvasFull = !win.canvasFull
                        onColorEditRequested: function (role) { dlgs.openColor(role, graph.colorForRole(role)) }
                    }

                    // The 3D view occupies the same slot when enabled (title-bar toggle).
                    GraphView3D {
                        id: graph3d
                        visible: win.use3D
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ctl: ctl
                        runWord: graph.runWord                 // share the 2D run word
                        onRunWordEdited: function (w) { graph.runWord = w }
                        canvasFull: win.canvasFull
                        onFullScreenToggleRequested: win.canvasFull = !win.canvasFull
                        canUndo: win.canUndo
                        canRedo: win.canRedo
                        onUndoRequested: win.undo()
                        onRedoRequested: win.redo()
                        // Colours: share the user-editable 2D role colours + follow the Theme.
                        colInitial: graph.initialColor
                        colAccept: graph.acceptColor
                        colCurrent: graph.currentColor
                        colToken: graph.tokenColor
                        colNode: Theme.nodeBorder
                        colEdge: Theme.edge
                        colBg: Theme.canvasBg
                        colLabel: Theme.textPrimary
                        colMuted: Theme.textMuted
                        colPaneBg: Qt.rgba(Theme.panelBg.r, Theme.panelBg.g, Theme.panelBg.b, 0.92)
                        colPaneBorder: Theme.panelBorder
                        workingColor: graph.workingColor      // shared paint colour (2D + 3D)
                        onAccentColorRequested: function (role, c) { graph.applyColor(role, c) }
                        onColorEditRequested: function (role) { dlgs.openColor(role, graph3d.colorForRole3D(role)) }
                    }
                }

                // Most diagram controls now live in the side panel's "Control" tab.
                // Only Run + Trace stay on the canvas (defined inside GraphView /
                // GraphView3D), plus this small Full Screen toggle — the Control tab
                // is hidden in full screen, so keep one reachable here (Esc also exits).
                Button {
                    z: 80
                    anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                    padding: 6
                    text: win.canvasFull ? "Exit full screen" : "Full screen"
                    onClicked: win.canvasFull = !win.canvasFull
                    ToolTip.visible: hovered
                    ToolTip.text: win.canvasFull ? "Leave full screen (Esc)" : "Maximise the canvas (Esc to exit)"
                }
            }

            // Run bar.
            Frame {
                id: runPane
                SplitView.preferredHeight: 320
                SplitView.minimumHeight: 120
                visible: !win.canvasFull
                background: Rectangle { color: Theme.panelBg; border.color: Theme.panelBorder; radius: 8 }
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10
                    clip: true   // keep contents inside the pane when it's resized small

                    // Inputs firable from the current state (the live Current /
                    // ACCEPTING status, the trace, and Speed/Token now live in the
                    // on-canvas panes, available in both modes).
                    Label {
                        Layout.fillWidth: true
                        text: "available: " + (ctl.available.length ? ctl.available.join("  ") : "—")
                        color: Theme.textMuted; font.pixelSize: 12
                    }

                    // Step-by-symbol buttons (enabled only when firable now).
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: ctl.symbols
                            delegate: Button {
                                required property string modelData
                                text: modelData
                                enabled: ctl.built && !ctl.running && ctl.available.indexOf(modelData) >= 0
                                onClicked: ctl.step(modelData)
                            }
                        }
                    }

                    // (Run / Stop / Reset + the input word now live in the
                    // on-canvas ControlPane, available in both modes.)

                    // Transition log — flexible so it absorbs/releases space and the
                    // pane never overflows its border on resize.
                    Frame {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 110
                        Layout.minimumHeight: 0
                        background: Rectangle { color: Theme.panelBg; border.color: Theme.panelBorder; radius: 6 }
                        ScrollView {
                            anchors.fill: parent
                            clip: true
                            TextArea {
                                readOnly: true
                                text: ctl.log
                                color: Theme.textPrimary; font.family: "Consolas"; font.pixelSize: 12
                                wrapMode: TextEdit.NoWrap
                                onTextChanged: cursorPosition = length
                            }
                        }
                    }
                }
            }
        }
    }
}
