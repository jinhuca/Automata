pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

// Draws the DFA as a node graph: states are circles, transitions are directed
// (slightly curved) arrows labelled with their symbol, self-loops are small
// loops above the node. The initial state gets an incoming marker, accepting
// states a double ring, the current state is highlighted, and the most recently
// fired transition is drawn in amber (the running trace).
//
// Node positions live in `nodeModel`. New states are auto-placed on a ring;
// dragging a node pins it (snap-to-grid), double-click resets it, so the user
// can freely re-lay-out the diagram while edges and labels follow.
Item {
    id: gv
    clip: true                            // keep zoomed content inside the frame
    property var ctl
    readonly property int nr: 24          // node radius
    readonly property int grid: 20        // drag snap-to-grid step
    property int rev: 0                   // bumped on any layout change (edge/label reactivity)

    // Caches to avoid per-frame allocation while the token animation repaints the
    // edge Canvas ~60fps. ctl.transitions converts to a new JS array on every
    // access (NOTIFY definitionChanged, so safe to cache); posOf() otherwise
    // rescanned nodeModel O(V) per call -> O(E*V) per paint.
    // Snapshotted once per definitionChanged (see refreshTransList): a binding to
    // the QVariantList `transitions` property re-invoked the C++ getter on every
    // access by every dependent binding, rebuilding the whole list each time —
    // seconds of freeze on a large machine. A plain property read by the many
    // dependents (shownTrans, edgeTotal, sceneBounds, labelLayout, …) avoids that.
    property var transList: []
    function refreshTransList() { transList = ctl ? ctl.transitionList() : []; }
    // Per-state entry/exit action text, snapshotted into plain maps (same reason as
    // transList: reading a QVariantMap Q_PROPERTY from every node delegate storms
    // the getter). Refreshed on definitionChanged. { stateName: "action text" }.
    property var entryMap: ({})
    property var exitMap: ({})
    function refreshActionMaps() {
        entryMap = ctl ? ctl.entryActions : ({});
        exitMap = ctl ? ctl.exitActions : ({});
    }
    readonly property point offscreenPos: Qt.point(-1000, -1000)
    // name -> position map. A PLAIN property refreshed explicitly (refreshPosCache),
    // NOT a binding on nodeModel.count: as a binding it rebuilt O(V) on every one
    // of the V nodeModel.append() calls during a load, making a big machine load
    // O(V²) and freeze for many seconds. We rebuild it once per structural/position
    // change instead — on rev change (drag/relayout/import/style) and after a
    // rebuild — which is also when the edges that read it re-evaluate.
    property var posCache: ({})
    function refreshPosCache() {
        var m = ({});
        for (var i = 0; i < nodeModel.count; i++) {
            var e = nodeModel.get(i);
            m[e.name] = Qt.point(e.x, e.y);
        }
        posCache = m;
    }
    property string edgeStyle: "curved"   // "curved" | "straight"
    property int curvature: 26            // global bend amount for curved edges
    property var edgeBend: ({})            // per-edge override: edgeKey -> signed bend
    property var edgeSelf: ({})            // self-loop override: edgeKey -> { a: angle, r: size }
    property var startAngle: ({})          // initial-stub direction override: stateName -> angle (rad)
    property var actionAngle: ({})         // entry/exit label placement: stateName -> angle (rad) around the circle
    property real tokenT: 1                // 0..1 progress of the token along the firing edge
    property string tokenStyle: "dot"      // "dot" | "ring" | "comet" | "chevron"
    property real tokenScale: 1.0          // token size multiplier (0.5..2)
    // Visually-current state: lags ctl.current during a step so the highlight
    // stays on the source until the token reaches the destination.
    property string visualCurrent: ""
    // Accepting status shown in the Run pane. Derived from visualCurrent (accepted
    // ⇔ current state ∈ F), so it lags exactly like the highlight: the badge only
    // updates once the token has arrived, not when the step starts.
    readonly property bool visualAccepted: ctl && ctl.built && ctl.acceptStates.indexOf(visualCurrent) >= 0
    // Token travel time tracks the run speed, always finishing before the next step.
    readonly property int stepMs: ctl ? ctl.stepInterval : 700

    // Progressive instantiation: creating hundreds of edge Shapes (and their
    // labels/handles) at once freezes the UI when a large machine is loaded, so
    // we ramp `renderCount` up in batches across event-loop ticks. Normally it is
    // effectively unlimited, so interactive edits appear at once. The edge/label/
    // handle Repeaters slice transList to renderCount; beginLoad()/populate()
    // (called around a build/load from Main.qml) drive the ramp.
    readonly property int unlimited: 1 << 30
    property int renderCount: unlimited
    readonly property int edgeTotal: transList.length
    readonly property bool rendering: renderCount < edgeTotal
    Timer {
        id: ramp
        interval: 16; repeat: false
        onTriggered: {
            gv.renderCount += 60;
            if (gv.renderCount < gv.edgeTotal) restart();
            else gv.renderCount = gv.unlimited;
        }
    }
    // Call BEFORE a (re)build/load so the definitionChanged that publishes the
    // new transitions doesn't instantiate every edge Shape in one synchronous go.
    function beginLoad() { ramp.stop(); renderCount = 0; }
    // Call AFTER a build/load: ramp in when large, else show everything at once.
    function populate() {
        if (edgeTotal > 120) { renderCount = 0; ramp.restart(); }
        else { ramp.stop(); renderCount = unlimited; }
    }
    // The transitions actually instantiated this frame (sliced during a ramp).
    readonly property var shownTrans: renderCount >= transList.length ? transList
                                                                      : transList.slice(0, renderCount)

    // User-tunable accent colors.
    property color initialColor: "#15803d"
    property color acceptColor: "#15803d"
    property color currentColor: "#f59e0b"
    property color tokenColor: "#f59e0b"

    // Canonical defaults for every recolourable role, so a single "reset all"
    // restores a known baseline. The theme-driven roles (state / edge / label)
    // default to "no override" (transparent => follow the light/dark theme).
    readonly property var colorDefaults: ({
        "initial": "#15803d", "accept": "#15803d", "current": "#f59e0b", "token": "#f59e0b",
        "node2d": "transparent", "edge2d": "transparent", "label2d": "transparent"
    })

    // Theme colors (driven by the app's light/dark theme).
    property color nodeFill: "#dbeafe"
    property color nodeBorder: "#2563eb"
    property color nodeText: "#1e3a8a"
    property color edgeColor: "#64748b"
    property color labelBg: "#ffffffee"
    property color labelBorder: "#e2e8f0"
    property color labelText: "#64748b"
    property color canvasBg: "transparent"   // diagram backdrop (also the PNG-export background)

    // User overrides for the theme-driven state-fill / edge / edge-label colours
    // (a==0 => follow the light/dark theme). Persisted with the view state, like
    // the accent colours above; mirrors the 3D view's node/edge/label overrides.
    property color nodeColorOverride: "transparent"
    readonly property color nodeFillEff: nodeColorOverride.a > 0 ? nodeColorOverride : nodeFill
    property color edgeColorOverride: "transparent"
    readonly property color edgeColorEff: edgeColorOverride.a > 0 ? edgeColorOverride : edgeColor
    property color labelColorOverride: "transparent"
    readonly property color labelTextEff: labelColorOverride.a > 0 ? labelColorOverride : labelText

    // Paint-bucket workflow: a single "working colour" is set from the picker
    // (double-click a swatch); single-clicking a swatch paints this colour onto
    // that role. Seeded to the active-state accent so it is useful immediately.
    property color workingColor: "#f59e0b"

    // Current colour shown by a role's swatch (effective colour for the
    // theme-driven roles), used to seed the picker.
    function colorForRole(role) {
        return role === "initial" ? initialColor
             : role === "accept"  ? acceptColor
             : role === "current" ? currentColor
             : role === "token"   ? tokenColor
             : role === "node2d"  ? nodeFillEff
             : role === "edge2d"  ? edgeColorEff
             : role === "state2d" ? selectedStateColor()   // the selected state's fill
             :                      labelTextEff;
    }
    // Apply a colour to a role. The theme-driven roles store it as an override;
    // an invalid/transparent colour clears the override (back to the theme).
    function applyColor(role, c) {
        if (role === "initial")       initialColor = c;
        else if (role === "accept")   acceptColor = c;
        else if (role === "current")  currentColor = c;
        else if (role === "token")    tokenColor = c;
        else if (role === "node2d")   nodeColorOverride = c;
        else if (role === "edge2d")   edgeColorOverride = c;
        else if (role === "label2d")  labelColorOverride = c;
        else if (role === "state2d")  applySelectedStateColor(c);
    }
    // Single-click: paint the working colour onto a role.
    function paintRole(role) { applyColor(role, workingColor); }
    // Reset every role to its canonical default.
    function resetColors() {
        for (var role in colorDefaults) applyColor(role, colorDefaults[role]);
    }

    // Background grid: a world-aligned reference grid (cell = the drag snap step)
    // so the user can read positions and layout. Toggleable via the on-canvas
    // button; persisted with the view state.
    property bool showGrid: true
    property color gridMinor: "#22334155"
    property color gridMajor: "#44334155"

    // Show the per-state entry/exit action labels beneath each node. Toggleable
    // on-canvas (next to the grid toggle); persisted with the view state.
    property bool showActions: true

    // ========================================================================
    // Draggable on-canvas control panes (same pattern as graph_algo). Each pane
    // has a grip and a persisted top-left position; realign() returns them all to
    // the default layout. Window-level values/actions come in as properties and
    // signals wired by Main.qml. The panes show in BOTH windowed and full-screen.
    // ========================================================================
    property bool canvasFull: false        // mirrors the window's full-screen state
    property string docName: ""            // document label shown in InfoPane
    property bool canUndo: false           // view-undo availability (from Main)
    property bool canRedo: false
    property string runWord: ""            // ControlPane input word (session-persisted via Main)
    signal undoRequested()
    signal redoRequested()
    signal fullScreenToggleRequested()
    signal colorEditRequested(string role) // open colour dialog: initial/accept/current/token/node2d/edge2d/label2d

    readonly property int paneH: 40        // uniform pane height
    readonly property int btnH: 28         // uniform button height
    property color paneBg: "#e6111827"     // bound from Main (Theme.panelBg, translucent)
    property color paneBorder: "#334155"   // bound from Main (Theme.panelBorder)
    property color paneText: "#e2e8f0"     // bound from Main (Theme.textPrimary)
    property color paneTextMuted: "#94a3b8"// bound from Main (Theme.textMuted)

    property bool panesVisible: true       // master show/hide for all control panes
    readonly property int paneTop: 8        // margin of the top row of panes
    // Keep Fit / Re-layout clear of the on-canvas elements. The control panes moved
    // to the side panel's "Control" tab, so the top only needs a little padding now
    // (just the small Full Screen button sits up there); the bottom still reserves
    // room for the always-present Run pane + trace.
    readonly property int fitTopInset: 16
    readonly property int fitBotInset: paneH + 24 + 8

    // Persisted pane top-left positions; UNSET (<= -1e6) means "use the default".
    readonly property real paneUnset: -1000000
    property real infoX: paneUnset;     property real infoY: paneUnset
    property real legendX: paneUnset;   property real legendY: paneUnset
    property real edgeEditX: paneUnset; property real edgeEditY: paneUnset
    property real layoutX: paneUnset;   property real layoutY: paneUnset
    property real zoomX: paneUnset;     property real zoomY: paneUnset
    property real ctrlX: paneUnset;     property real ctrlY: paneUnset
    property real animX: paneUnset;     property real animY: paneUnset   // Speed/Token pane
    function paneClamp(v, def, extent) {
        var p = (v <= -999999) ? def : v;
        return Math.max(0, Math.min(Math.max(0, extent), p));
    }
    // Reset every pane to its default position.
    function realign() {
        infoX = paneUnset; infoY = paneUnset;
        legendX = paneUnset; legendY = paneUnset;
        edgeEditX = paneUnset; edgeEditY = paneUnset;
        layoutX = paneUnset; layoutY = paneUnset;
        zoomX = paneUnset; zoomY = paneUnset;
        ctrlX = paneUnset; ctrlY = paneUnset;
        animX = paneUnset; animY = paneUnset;
    }

    // Opaque backdrop behind the diagram so a grabbed PNG has a real background
    // (and the canvas colour is explicit rather than the panel showing through).
    Rectangle { anchors.fill: parent; color: gv.canvasBg; z: -100 }

    // World-aligned background grid. Drawn in viewport space but offset/scaled
    // from pan+zoom so the lines track diagram coordinates (cell = gv.grid, the
    // drag snap step, so nodes snap onto grid lines). A single lightweight Canvas
    // repainted only on pan/zoom/theme/toggle.
    Canvas {
        id: grid
        anchors.fill: parent
        z: -50
        visible: gv.showGrid
        renderStrategy: Canvas.Immediate
        renderTarget: Canvas.Image
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: gv
            function onPanXChanged() { grid.requestPaint(); }
            function onPanYChanged() { grid.requestPaint(); }
            function onZoomChanged() { grid.requestPaint(); }
            function onGridMinorChanged() { grid.requestPaint(); }
            function onGridMajorChanged() { grid.requestPaint(); }
        }
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (!gv.showGrid) return;
            var z = gv.zoom, cell = gv.grid * z;      // gv.grid world px per cell
            if (cell < 6) return;                      // too dense to help
            var cx = width / 2, cy = height / 2;
            var ox = gv.panX + cx * (1 - z);           // screen x of diagram x = 0
            var oy = gv.panY + cy * (1 - z);
            function first(o, s) { var f = o % s; return f > 0 ? f - s : f; }
            function lines(step, col) {
                ctx.beginPath(); ctx.lineWidth = 1; ctx.strokeStyle = col;
                for (var x = first(ox, step); x <= width; x += step) { var rx = Math.round(x) + 0.5; ctx.moveTo(rx, 0); ctx.lineTo(rx, height); }
                for (var y = first(oy, step); y <= height; y += step) { var ry = Math.round(y) + 0.5; ctx.moveTo(0, ry); ctx.lineTo(width, ry); }
                ctx.stroke();
            }
            lines(cell, gv.gridMinor);                 // minor every cell
            lines(cell * 5, gv.gridMajor);             // major every 5 cells (origin included)
        }
    }

    // Per-edge endpoint anchor override: edgeKey -> { fa: angle, ta: angle } (where
    // the arrow attaches on the from/to circle). Lets the user spread crowded
    // arrows. `selectedKey` is the edge whose drag handles are currently shown.
    property var edgeAnchor: ({})
    property string selectedKey: ""
    // Sentinel selectedKey value for the initial-state stub (never a real edge key,
    // which is "from\u001fsymbol\u001fto"), so its handle shares the edge selection.
    readonly property string startKey: "\u0001start"

    // Per-state overrides + selection (click a state circle to select it, then edit
    // its size / colour in the Control tab). Mutually exclusive with edge selection.
    property var stateColors: ({})       // name -> fill colour override
    property var stateSizes: ({})        // name -> size multiplier (0.5..2)
    property real allStateScale: 1.0     // global size multiplier applied to EVERY state
    property string selectedState: ""    // currently selected state ("" = none)
    // Effective node radius = base * global multiplier * this state's own multiplier.
    function nodeRadius(name) { var s = stateSizes[name]; return nr * allStateScale * (s !== undefined ? s : 1); }
    // Reset every state to the default look: clear the global fill + size and all the
    // per-state size/colour overrides (positions are left untouched).
    function resetAllStates() {
        allStateScale = 1;
        nodeColorOverride = "transparent";
        stateSizes = ({}); stateColors = ({});
        rev++; edges.requestPaint();
    }
    function stateFill(name) { return stateColors[name] !== undefined ? stateColors[name] : nodeFillEff; }
    function selectState(name) { selectedState = name; selectedKey = ""; }       // clears edge selection
    function selectedStateSize() { return (selectedState !== "" && stateSizes[selectedState] !== undefined) ? stateSizes[selectedState] : 1; }
    function selectedStateColor() { return selectedState !== "" ? stateFill(selectedState) : nodeFillEff; }
    function setSelectedStateSize(v) {
        if (selectedState === "") return;
        var m = {}; for (var k in stateSizes) m[k] = stateSizes[k];
        m[selectedState] = v; stateSizes = m; rev++; edges.requestPaint();
    }
    function applySelectedStateColor(c) {
        if (selectedState === "") return;
        var m = {}; for (var k in stateColors) m[k] = stateColors[k];
        m[selectedState] = "" + c; stateColors = m; rev++;
    }
    // Reset the selected state's styling — size + fill colour. Position is left as
    // is (resetting it would snap the node to a layout slot, moving it drastically);
    // use double-click on the node to send it back to the auto-layout. The shared
    // "state" fill in the Colours row is global — cleared by "Reset colours".
    function resetSelectedState() {
        if (selectedState === "") return;
        var nm = selectedState;
        var ms = {}; for (var k in stateSizes)  if (k !== nm) ms[k] = stateSizes[k];   stateSizes  = ms;
        var mc = {}; for (var j in stateColors) if (j !== nm) mc[j] = stateColors[j];  stateColors = mc;
        rev++; edges.requestPaint();
    }

    // Text shown in the fixed hover banner (top of the diagram): the full name of
    // the hovered state, or "from —symbol→ to" of the hovered transition. Empty
    // hides the banner. Using one fixed banner instead of per-element tooltips
    // keeps the info from covering the controls below the diagram.
    property string hoverInfo: ""
    property string hoverEntry: ""     // hovered state's entry action (shown with the entry icon)
    property string hoverExit: ""      // hovered state's exit action (shown with the exit icon)

    // Emitted whenever serializable view state changes (layout, overrides, style,
    // accent colors) so the app can session-autosave and flag "modified".
    signal changed()

    // Canvas zoom + pan (content is scaled around its centre and translated).
    property real zoom: 1.0
    property real panX: 0
    property real panY: 0
    property real _panSX: 0   // transient drag anchors
    property real _panSY: 0
    property real _pan0X: 0
    property real _pan0Y: 0
    // "Fit mode" tracks whether the view is auto-fitted to the canvas. While true,
    // the diagram re-fits on resize; once the user zooms or pans it turns off, so a
    // window resize then preserves their chosen zoom/pan instead of snapping to fit.
    property bool fitMode: true
    function zoomBy(f) { zoom = Math.max(0.3, Math.min(3.0, zoom * f)); fitMode = false; }
    function zoomReset() { zoom = 1.0; panX = 0; panY = 0; }  // reset view (100%, centred)

    // Zoom/pan so the whole state diagram is centred and fits the canvas (not
    // necessarily 100%). Used by the reset button.
    function fitView() {
        fitMode = true;   // re-entering fit mode: track the canvas on resize again
        if (nodeModel.count === 0 || width <= 0 || height <= 0) { zoomReset(); return; }
        // Fit the full drawn geometry (nodes AND any dragged-out bends/self-loops),
        // not just the node positions, so the reset button frames everything.
        var b = sceneBounds();
        var bw = Math.max(1, b.width), bh = Math.max(1, b.height);
        var pad = 20;
        // Fit into the pane-free region (inset for the top/bottom control panes).
        var availW = Math.max(1, width - 2 * pad);
        var availH = Math.max(1, height - gv.fitTopInset - gv.fitBotInset - 2 * pad);
        // Floor low enough that even a tiny window can show the whole diagram.
        var z = Math.max(0.05, Math.min(3.0, Math.min(availW / bw, availH / bh)));
        var cx = width / 2, cy = gv.fitTopInset + pad + availH / 2;   // centre of the pane-free region
        var bx = b.x + b.width / 2, by = b.y + b.height / 2;
        zoom = z;
        panX = (cx - bx) * z;
        panY = (cy - height / 2) + (height / 2 - by) * z;
    }

    ListModel { id: nodeModel }           // roles: name, x, y, pinned

    // Animate a token travelling along the just-fired transition.
    NumberAnimation {
        id: tokenAnim
        target: gv; property: "tokenT"
        from: 0; to: 1
        duration: Math.max(120, Math.round(gv.stepMs * 0.75))
        easing.type: Easing.InOutQuad
        onFinished: gv.visualCurrent = gv.ctl ? gv.ctl.current : ""   // hand off on arrival
    }
    // The token is drawn on its own small overlay (tokenLayer) that only moves
    // as tokenT changes — so the big edge Canvas does NOT repaint every frame.

    function edgeKey(t) { return t.from + "\u001f" + t.symbol + "\u001f" + t.to; }

    // Self-loop placement: angle `a` (direction it sticks out from the node) and
    // size `r`. Defaults to a loop above the node.
    function selfParams(t) {
        var o = edgeSelf[edgeKey(t)];
        return o !== undefined ? o : { a: -Math.PI / 2, r: 46 };
    }
    function selfGeom(center, a, r, baseR) {
        var br = (baseR !== undefined) ? baseR : nr;   // node radius (per-state)
        var dx = Math.cos(a), dy = Math.sin(a);     // outward direction
        var px = -Math.sin(a), py = Math.cos(a);    // perpendicular
        var bx = center.x + br * dx, by = center.y + br * dy;          // loop base on the circle
        return {
            sx: bx - px * 9,          sy: by - py * 9,                 // start anchor
            ex: bx + px * 9,          ey: by + py * 9,                 // end anchor
            csx: bx + dx * r - px * 34, csy: by + dy * r - py * 34,    // control 1
            cex: bx + dx * r + px * 34, cey: by + dy * r + py * 34,    // control 2
            lx: bx + dx * (r + 14),   ly: by + dy * (r + 14)          // label
        };
    }
    // The bend to use for a transition: a per-edge override if set, else the
    // global curvature (0 when the style is straight).
    function bendFor(t) {
        var k = edgeKey(t);
        if (edgeBend[k] !== undefined) return edgeBend[k];
        return edgeStyle === "straight" ? 0 : curvature;
    }

    function ringPos(i, n) {
        // Centre the ring in the pane-free region so auto-placed nodes don't land
        // under the top/bottom panes.
        var availH = height - gv.fitTopInset - gv.fitBotInset;
        var cx = width / 2, cy = gv.fitTopInset + availH / 2;
        if (n <= 1) return Qt.point(cx, cy);
        var R = Math.max(40, Math.min(width, availH) / 2 - 80);
        var a = -Math.PI / 2 + i * 2 * Math.PI / n;
        return Qt.point(cx + R * Math.cos(a), cy + R * Math.sin(a));
    }

    function relayout() {
        var n = nodeModel.count;
        var moved = false;
        for (var i = 0; i < n; i++) {
            if (!nodeModel.get(i).pinned) {
                var p = ringPos(i, n), e = nodeModel.get(i);
                if (e.x !== p.x || e.y !== p.y) {
                    nodeModel.setProperty(i, "x", p.x);
                    nodeModel.setProperty(i, "y", p.y);
                    moved = true;
                }
            }
        }
        if (moved) rev++;   // only a real move counts as a change (not a resize no-op)
    }

    // "Re-layout": arrange the states on a clean rectangular grid that fills the
    // pane-free canvas region (rows x cols chosen to match its aspect), then reset
    // zoom/pan so it maps 1:1 — the 2D analogue of the 3D cuboid re-layout.
    function layoutToRegion() {
        var n = nodeModel.count;
        if (n === 0 || width <= 0 || height <= 0) return;
        var L = 50, Rr = width - 50;                         // horizontal padding
        var T = gv.fitTopInset + 24, B = height - gv.fitBotInset - 24;  // clear the panes + padding
        var availW = Math.max(1, Rr - L), availH = Math.max(1, B - T);
        var cols = Math.max(1, Math.round(Math.sqrt(n * availW / availH)));
        var rows = Math.ceil(n / cols);
        var cw = availW / cols, ch = availH / rows;
        for (var i = 0; i < n; i++) {
            var c = i % cols, r = Math.floor(i / cols);
            var inRow = (r === rows - 1) ? (n - r * cols) : cols;   // center a partial last row
            var rowPad = (cols - inRow) * cw / 2;
            nodeModel.setProperty(i, "x", Math.round(L + rowPad + (c + 0.5) * cw));
            nodeModel.setProperty(i, "y", Math.round(T + (r + 0.5) * ch));
            nodeModel.setProperty(i, "pinned", true);
        }
        rev++;
        refreshPosCache();
        zoom = 1; panX = 0; panY = 0; fitMode = false;
    }

    function relayoutAll() {
        edgeBend = ({});    // drop per-edge curvature overrides
        edgeSelf = ({});    // and self-loop placement overrides
        edgeAnchor = ({});  // and endpoint-anchor overrides
        selectedKey = "";
        layoutToRegion();   // spread the states across the available canvas region
        edges.requestPaint();
    }

    function rebuildNodes() {
        if (!ctl) return;
        var states = ctl.states;
        var prev = {};
        for (var i = 0; i < nodeModel.count; i++) {
            var e = nodeModel.get(i);
            prev[e.name] = { x: e.x, y: e.y, pinned: e.pinned };
        }
        nodeModel.clear();
        for (var j = 0; j < states.length; j++) {
            var nm = states[j];
            if (prev[nm] !== undefined)
                nodeModel.append({ name: nm, x: prev[nm].x, y: prev[nm].y, pinned: prev[nm].pinned });
            else
                nodeModel.append({ name: nm, x: 0, y: 0, pinned: false });
        }
        relayout();
        refreshPosCache();   // rebuild the position map once, after the bulk append
        edges.requestPaint();
    }

    // Serialize the view/layout state (node positions + per-edge overrides +
    // style + colors) for saving to file.
    function exportState() {
        var nodes = [];
        for (var i = 0; i < nodeModel.count; i++) {
            var e = nodeModel.get(i);
            nodes.push({ name: e.name, x: e.x, y: e.y, pinned: e.pinned });
        }
        return {
            nodes: nodes,
            edgeBend: edgeBend, edgeSelf: edgeSelf, edgeAnchor: edgeAnchor,
            startAngle: startAngle, actionAngle: actionAngle,
            stateColors: stateColors, stateSizes: stateSizes, allStateScale: allStateScale,
            edgeStyle: edgeStyle, curvature: curvature, tokenStyle: tokenStyle, tokenScale: tokenScale,
            showGrid: showGrid, showActions: showActions,
            initialColor: "" + initialColor, acceptColor: "" + acceptColor,
            currentColor: "" + currentColor, tokenColor: "" + tokenColor,
            nodeColor: nodeColorOverride.a > 0 ? "" + nodeColorOverride : "",
            edgeColorOv: edgeColorOverride.a > 0 ? "" + edgeColorOverride : "",
            labelColor: labelColorOverride.a > 0 ? "" + labelColorOverride : ""
        };
    }

    // Apply a previously-saved view/layout state. Call after the definition has
    // been (re)built so the nodes exist.
    function importState(s) {
        if (!s) return;
        if (s.edgeStyle !== undefined) edgeStyle = s.edgeStyle;
        if (s.curvature !== undefined) curvature = s.curvature;
        if (s.tokenStyle !== undefined) tokenStyle = s.tokenStyle;
        if (s.tokenScale !== undefined) tokenScale = s.tokenScale;
        if (s.showGrid !== undefined) showGrid = s.showGrid;
        if (s.showActions !== undefined) showActions = s.showActions;
        if (s.initialColor) initialColor = s.initialColor;
        if (s.acceptColor) acceptColor = s.acceptColor;
        if (s.currentColor) currentColor = s.currentColor;
        if (s.tokenColor) tokenColor = s.tokenColor;
        if (s.nodeColor !== undefined) nodeColorOverride = s.nodeColor ? s.nodeColor : "transparent";
        if (s.edgeColorOv !== undefined) edgeColorOverride = s.edgeColorOv ? s.edgeColorOv : "transparent";
        if (s.labelColor !== undefined) labelColorOverride = s.labelColor ? s.labelColor : "transparent";
        edgeBend = s.edgeBend || ({});
        edgeSelf = s.edgeSelf || ({});
        edgeAnchor = s.edgeAnchor || ({});
        startAngle = s.startAngle || ({});
        actionAngle = s.actionAngle || ({});
        stateColors = s.stateColors || ({});
        stateSizes = s.stateSizes || ({});
        if (s.allStateScale !== undefined) allStateScale = s.allStateScale;
        if (s.nodes) {
            for (var i = 0; i < s.nodes.length; i++) {
                var n = s.nodes[i];
                for (var j = 0; j < nodeModel.count; j++) {
                    if (nodeModel.get(j).name === n.name) {
                        nodeModel.setProperty(j, "x", n.x);
                        nodeModel.setProperty(j, "y", n.y);
                        nodeModel.setProperty(j, "pinned", n.pinned === undefined ? true : n.pinned);
                        break;
                    }
                }
            }
        }
        rev++;
        edges.requestPaint();
    }

    // Tight bounding box (in content coords) of everything drawn: node discs,
    // edge control points (bends), self-loops and the initial stub — negative
    // coordinates included. The edge canvas is sized AND positioned to this box
    // (so a bend dragged far out, even above the top, is never clipped), and
    // fitView() fits to it (so the reset button frames the real diagram, bends
    // and all). Depends on rev so it recomputes when the layout or any edge
    // override changes. Falls back to the viewport when nothing is drawn.
    function sceneBounds() {
        gv.rev;  // dependency: recompute on layout / override change
        var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        function ext(x, y) {
            if (x < minX) minX = x;
            if (x > maxX) maxX = x;
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
        }
        if (gv.ctl) {
            var trans = gv.transList;
            for (var k = 0; k < trans.length; k++) {
                var t = trans[k];
                var p = posOf(t.from), q = posOf(t.to);
                if (p.x < -900 || q.x < -900) continue;
                if (t.from === t.to) {
                    var sp = selfParams(t), sg = selfGeom(p, sp.a, sp.r, nodeRadius(t.from));
                    ext(sg.sx, sg.sy); ext(sg.ex, sg.ey);
                    ext(sg.csx, sg.csy); ext(sg.cex, sg.cey); ext(sg.lx, sg.ly);
                } else {
                    var g = edgeGeom(t);
                    ext(g.sx, g.sy); ext(g.mx, g.my); ext(g.ex, g.ey);
                }
            }
            var ip = posOf(gv.ctl.initialState);
            if (ip.x > -900) ext(ip.x, ip.y);
        }
        for (var i = 0; i < nodeModel.count; i++) {
            var e = nodeModel.get(i), r = nr + 10;
            ext(e.x - r, e.y - r); ext(e.x + r, e.y + r);
        }
        if (minX === Infinity)  // nothing drawn yet — fall back to the viewport
            return Qt.rect(0, 0, Math.max(1, gv.width), Math.max(1, gv.height));
        var pad = 28;  // arrowheads, stroke width, stub overshoot — tight bounds (fitView uses this)
        return Qt.rect(minX - pad, minY - pad, (maxX - minX) + 2 * pad, (maxY - minY) + 2 * pad);
    }

    function posOf(name) {
        var p = posCache[name];
        return p !== undefined ? p : offscreenPos;
    }

    // Geometry of a non-self edge: trimmed endpoints on each circle (honouring any
    // per-endpoint anchor override), plus a quadratic control point bent off the
    // chord by bendFor(t).
    function edgeGeom(t) {
        var p = posOf(t.from), q = posOf(t.to);
        var ov = edgeAnchor[edgeKey(t)] || {};
        var dx = q.x - p.x, dy = q.y - p.y, len = Math.hypot(dx, dy);
        if (len < 1) len = 1;
        var ux = dx / len, uy = dy / len;
        var rs = nodeRadius(t.from), rt = nodeRadius(t.to);   // per-state radii (trim to each rim)
        var sx, sy, ex, ey;
        if (ov.fa !== undefined) { sx = p.x + rs * Math.cos(ov.fa); sy = p.y + rs * Math.sin(ov.fa); }
        else { sx = p.x + ux * rs; sy = p.y + uy * rs; }
        if (ov.ta !== undefined) { ex = q.x + rt * Math.cos(ov.ta); ey = q.y + rt * Math.sin(ov.ta); }
        else { ex = q.x - ux * rt; ey = q.y - uy * rt; }
        var edx = ex - sx, edy = ey - sy, el = Math.hypot(edx, edy); if (el < 1) el = 1;
        var px = -edy / el, py = edx / el;
        var bend = bendFor(t);
        var mx = (sx + ex) / 2 + px * bend, my = (sy + ey) / 2 + py * bend;
        return { sx: sx, sy: sy, ex: ex, ey: ey, mx: mx, my: my };
    }

    function labelPos(t) {
        if (t.from === t.to) {
            var p = posOf(t.from), sp = selfParams(t), sg = selfGeom(p, sp.a, sp.r, nodeRadius(t.from));
            return Qt.point(sg.lx, sg.ly);
        }
        var g = edgeGeom(t);
        return Qt.point(0.25 * g.sx + 0.5 * g.mx + 0.25 * g.ex,
                        0.25 * g.sy + 0.5 * g.my + 0.25 * g.ey);
    }

    // De-overlapped label positions: start from labelPos() and push overlapping
    // boxes apart so crowded labels (e.g. many edges into one node) stay legible.
    // User-dragged labels (edgeBend/edgeSelf override) are anchored and only push
    // others. Recomputed on every layout change via rev.
    property var labelAdj: labelLayout()
    function labelLayout() {
        gv.rev;  // dependency
        var res = ({});
        if (!ctl) return res;
        var trans = gv.transList, items = [];
        for (var k = 0; k < trans.length; k++) {
            var t = trans[k], p = posOf(t.from), q = posOf(t.to);
            if (p.x < -900 || q.x < -900) continue;
            var key = edgeKey(t), lp = labelPos(t);
            var w = Math.min(("" + t.symbol).length, 9) * 7 + 12;   // approx chip width (symbol capped)
            items.push({ key: key, x: lp.x, y: lp.y, w: w, h: 18,
                         fixed: edgeBend[key] !== undefined || edgeSelf[key] !== undefined });
        }
        for (var iter = 0; iter < 24; iter++) {
            var any = false;
            for (var i = 0; i < items.length; i++) {
                for (var j = i + 1; j < items.length; j++) {
                    var a = items[i], b = items[j];
                    var dx = b.x - a.x, dy = b.y - a.y;
                    var ox = (a.w + b.w) / 2 + 4 - Math.abs(dx);   // overlap incl. 4px gap
                    var oy = (a.h + b.h) / 2 + 3 - Math.abs(dy);
                    if (ox <= 0 || oy <= 0) continue;              // not overlapping
                    any = true;
                    if (oy <= ox) {                                // separate along the smaller axis
                        var sy = (dy >= 0 ? 1 : -1) * (oy / 2 + 0.3);
                        if (a.fixed && b.fixed) continue;
                        if (!a.fixed && !b.fixed) { a.y -= sy; b.y += sy; }
                        else if (!a.fixed) a.y -= 2 * sy;
                        else if (!b.fixed) b.y += 2 * sy;
                    } else {
                        var sx = (dx >= 0 ? 1 : -1) * (ox / 2 + 0.3);
                        if (a.fixed && b.fixed) continue;
                        if (!a.fixed && !b.fixed) { a.x -= sx; b.x += sx; }
                        else if (!a.fixed) a.x -= 2 * sx;
                        else if (!b.fixed) b.x += 2 * sx;
                    }
                }
            }
            if (!any) break;
        }
        for (var m = 0; m < items.length; m++) res[items[m].key] = Qt.point(items[m].x, items[m].y);
        return res;
    }
    // Where a transition's label is actually drawn (de-overlapped, else base).
    function labelDisplayPos(t) {
        var a = labelAdj[edgeKey(t)];
        return a !== undefined ? a : labelPos(t);
    }

    function isHot(t) {
        return ctl && ctl.lastSymbol.length > 0
            && t.from === ctl.lastFrom && t.symbol === ctl.lastSymbol && t.to === ctl.lastTo;
    }

    // Draw the moving token at (x,y) travelling in unit-ish direction (dx,dy),
    // in the selected style.
    function drawToken(ctx, x, y, dx, dy) {
        var l = Math.hypot(dx, dy); if (l < 0.001) l = 1;
        var ux = dx / l, uy = dy / l;
        var col = tokenColor;
        var s = tokenScale;                 // size multiplier (from the Token-size slider)
        if (tokenStyle === "ring") {
            ctx.strokeStyle = col; ctx.lineWidth = 3 * s;
            ctx.beginPath(); ctx.arc(x, y, 7 * s, 0, 2 * Math.PI); ctx.stroke();
        } else if (tokenStyle === "chevron") {
            var px = -uy, py = ux, a = 9 * s, w = 7 * s;
            ctx.fillStyle = col;
            ctx.beginPath();
            ctx.moveTo(x + ux * a, y + uy * a);
            ctx.lineTo(x - ux * a + px * w, y - uy * a + py * w);
            ctx.lineTo(x - ux * a - px * w, y - uy * a - py * w);
            ctx.closePath(); ctx.fill();
        } else if (tokenStyle === "comet") {
            for (var i = 3; i >= 1; i--) {      // fading tail behind the head
                ctx.globalAlpha = 0.18 * i;
                ctx.fillStyle = col;
                ctx.beginPath(); ctx.arc(x - ux * 7 * s * i, y - uy * 7 * s * i, (5 - i) * s, 0, 2 * Math.PI); ctx.fill();
            }
            ctx.globalAlpha = 1;
            ctx.fillStyle = col;
            ctx.beginPath(); ctx.arc(x, y, 6 * s, 0, 2 * Math.PI); ctx.fill();
        } else {  // dot
            ctx.fillStyle = col;
            ctx.beginPath(); ctx.arc(x, y, 6 * s, 0, 2 * Math.PI); ctx.fill();
            ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 2 * s;
            ctx.beginPath(); ctx.arc(x, y, 6 * s, 0, 2 * Math.PI); ctx.stroke();
        }
    }

    // Position + heading (degrees) of the travelling token on the hot edge at
    // the current tokenT, or null when nothing is firing. Drives the small
    // tokenLayer overlay so the big edge Canvas needn't repaint per frame.
    function tokenPos() {
        if (!ctl || tokenT >= 1 || ctl.lastSymbol.length === 0) return null;
        var trans = transList, x, y, dx, dy;
        for (var k = 0; k < trans.length; k++) {
            var t = trans[k];
            if (t.from !== ctl.lastFrom || t.symbol !== ctl.lastSymbol || t.to !== ctl.lastTo) continue;
            if (t.from === t.to) {
                var p = posOf(t.from), sp = selfParams(t), sg = selfGeom(p, sp.a, sp.r, nodeRadius(t.from));
                var ut = tokenT, uu = 1 - ut;
                var b0 = uu * uu * uu, b1 = 3 * uu * uu * ut, b2 = 3 * uu * ut * ut, b3 = ut * ut * ut;
                var e0 = 3 * uu * uu, e1 = 6 * uu * ut, e2 = 3 * ut * ut;
                x = b0 * sg.sx + b1 * sg.csx + b2 * sg.cex + b3 * sg.ex;
                y = b0 * sg.sy + b1 * sg.csy + b2 * sg.cey + b3 * sg.ey;
                dx = e0 * (sg.csx - sg.sx) + e1 * (sg.cex - sg.csx) + e2 * (sg.ex - sg.cex);
                dy = e0 * (sg.csy - sg.sy) + e1 * (sg.cey - sg.csy) + e2 * (sg.ey - sg.cey);
            } else {
                var g = edgeGeom(t), qt = tokenT, qu = 1 - qt;
                x = qu * qu * g.sx + 2 * qu * qt * g.mx + qt * qt * g.ex;
                y = qu * qu * g.sy + 2 * qu * qt * g.my + qt * qt * g.ey;
                dx = 2 * qu * (g.mx - g.sx) + 2 * qt * (g.ex - g.mx);
                dy = 2 * qu * (g.my - g.sy) + 2 * qt * (g.ey - g.my);
            }
            return { x: x, y: y, ang: Math.atan2(dy, dx) * 180 / Math.PI };
        }
        return null;
    }

    function arrowHead(ctx, ex, ey, dirx, diry) {
        var l = Math.hypot(dirx, diry); if (l < 0.001) return;
        dirx /= l; diry /= l;
        var ah = 11, aw = 6;
        var bx = ex - dirx * ah, by = ey - diry * ah;
        var nx = -diry, ny = dirx;
        ctx.beginPath();
        ctx.moveTo(ex, ey);
        ctx.lineTo(bx + nx * aw, by + ny * aw);
        ctx.lineTo(bx - nx * aw, by - ny * aw);
        ctx.closePath();
        ctx.fill();
    }

    // Build a standalone SVG of the diagram's current geometry (same edge/node
    // layout as on screen; static — no run-state highlight). Returns the SVG text.
    function exportSvg() {
        function f(n) { return Math.round(n * 10) / 10; }
        function col(c) { return "rgb(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + ")"; }
        function xml(t) { return ("" + t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
        function arrow(ex, ey, dx, dy, c) {
            var l = Math.hypot(dx, dy); if (l < 0.001) return "";
            dx /= l; dy /= l;
            var ah = 11, aw = 6, bx = ex - dx * ah, by = ey - dy * ah, nx = -dy, ny = dx;
            return '<polygon points="' + f(ex) + ',' + f(ey) + ' ' + f(bx + nx * aw) + ',' + f(by + ny * aw)
                   + ' ' + f(bx - nx * aw) + ',' + f(by - ny * aw) + '" fill="' + c + '"/>';
        }
        var b = sceneBounds();
        var W = Math.max(1, Math.round(b.width)), H = Math.max(1, Math.round(b.height));
        var ec = col(gv.edgeColorEff);
        var out = [];
        out.push('<?xml version="1.0" encoding="UTF-8"?>');
        out.push('<svg xmlns="http://www.w3.org/2000/svg" width="' + W + '" height="' + H
                 + '" viewBox="' + f(b.x) + ' ' + f(b.y) + ' ' + W + ' ' + H + '">');
        out.push('<rect x="' + f(b.x) + '" y="' + f(b.y) + '" width="' + W + '" height="' + H
                 + '" fill="' + col(gv.canvasBg) + '"/>');
        if (gv.ctl) {
            var trans = gv.transList, k, t, p, q;
            for (k = 0; k < trans.length; k++) {
                t = trans[k]; p = posOf(t.from); q = posOf(t.to);
                if (p.x < -900 || q.x < -900) continue;
                if (t.from === t.to) {
                    var sp = selfParams(t), sg = selfGeom(p, sp.a, sp.r, nodeRadius(t.from));
                    out.push('<path d="M ' + f(sg.sx) + ' ' + f(sg.sy) + ' C ' + f(sg.csx) + ' ' + f(sg.csy)
                             + ' ' + f(sg.cex) + ' ' + f(sg.cey) + ' ' + f(sg.ex) + ' ' + f(sg.ey)
                             + '" fill="none" stroke="' + ec + '" stroke-width="2"/>');
                    out.push(arrow(sg.ex, sg.ey, sg.ex - sg.cex, sg.ey - sg.cey, ec));
                } else {
                    var g = edgeGeom(t);
                    out.push('<path d="M ' + f(g.sx) + ' ' + f(g.sy) + ' Q ' + f(g.mx) + ' ' + f(g.my)
                             + ' ' + f(g.ex) + ' ' + f(g.ey) + '" fill="none" stroke="' + ec + '" stroke-width="2"/>');
                    out.push(arrow(g.ex, g.ey, g.ex - g.mx, g.ey - g.my, ec));
                }
            }
            var ip = posOf(gv.ctl.initialState);
            if (ip.x > -900) {
                var ox = ip.x - gv.width / 2, oy = ip.y - gv.height / 2, ol = Math.hypot(ox, oy);
                if (ol < 1) { ox = 0; oy = -1; ol = 1; }
                ox /= ol; oy /= ol;
                var isr = nodeRadius(gv.ctl.initialState);
                var sX = ip.x + ox * (isr + 30), sY = ip.y + oy * (isr + 30);
                var eX = ip.x + ox * (isr + 3), eY = ip.y + oy * (isr + 3);
                var icol = col(gv.initialColor);
                out.push('<line x1="' + f(sX) + '" y1="' + f(sY) + '" x2="' + f(eX) + '" y2="' + f(eY)
                         + '" stroke="' + icol + '" stroke-width="2"/>');
                out.push(arrow(eX, eY, eX - sX, eY - sY, icol));
            }
        }
        var nb = col(gv.nodeBorder), ntc = col(gv.nodeText), ac = col(gv.acceptColor);
        for (var i = 0; i < nodeModel.count; i++) {
            var e = nodeModel.get(i);
            var rr = nodeRadius(e.name), nf = col(gv.stateFill(e.name));   // per-state size + fill
            if (gv.ctl && gv.ctl.acceptStates.indexOf(e.name) >= 0)
                out.push('<circle cx="' + f(e.x) + '" cy="' + f(e.y) + '" r="' + (rr + 5)
                         + '" fill="none" stroke="' + ac + '" stroke-width="2"/>');
            out.push('<circle cx="' + f(e.x) + '" cy="' + f(e.y) + '" r="' + rr + '" fill="' + nf
                     + '" stroke="' + nb + '" stroke-width="2"/>');
            out.push('<text x="' + f(e.x) + '" y="' + f(e.y) + '" fill="' + ntc
                     + '" font-family="sans-serif" font-size="12" font-weight="bold"'
                     + ' text-anchor="middle" dominant-baseline="central">' + xml(e.name) + '</text>');
        }
        if (gv.ctl) {
            var lbg = col(gv.labelBg), lbd = col(gv.labelBorder), ltx = col(gv.labelTextEff);
            var opa = gv.labelBg.a.toFixed(2);
            var tr2 = gv.ctl.transitions;
            for (var j = 0; j < tr2.length; j++) {
                var td = tr2[j], pf = posOf(td.from), pt = posOf(td.to);
                if (pf.x < -900 || pt.x < -900) continue;
                var lp = labelDisplayPos(td), lw = 10 + ("" + td.symbol).length * 7, lh = 17;
                out.push('<rect x="' + f(lp.x - lw / 2) + '" y="' + f(lp.y - lh / 2) + '" width="' + lw
                         + '" height="' + lh + '" rx="3" fill="' + lbg + '" fill-opacity="' + opa
                         + '" stroke="' + lbd + '" stroke-width="1"/>');
                out.push('<text x="' + f(lp.x) + '" y="' + f(lp.y) + '" fill="' + ltx
                         + '" font-family="sans-serif" font-size="11" font-weight="bold"'
                         + ' text-anchor="middle" dominant-baseline="central">' + xml(td.symbol) + '</text>');
            }
        }
        out.push('</svg>');
        return out.join("\n");
    }

    // Zoomable content layer: everything drawn/positioned in diagram coordinates
    // lives here, scaled by gv.zoom around the centre.
    Item {
        id: content
        width: gv.width; height: gv.height
        x: gv.panX
        y: gv.panY
        transform: Scale { origin.x: gv.width / 2; origin.y: gv.height / 2; xScale: gv.zoom; yScale: gv.zoom }

    // Drag empty space to pan; tap empty space to deselect the current edge.
    // Pointer handlers so node/label/handle MouseAreas keep priority on their areas.
    TapHandler { onTapped: { gv.selectedKey = ""; gv.selectedState = "" } }
    DragHandler {
        target: null
        // Never steal the grab from a MouseArea that already has it (node, label
        // or endpoint-handle drag). Only pan when the press landed on empty space.
        grabPermissions: PointerHandler.ApprovesTakeOverByHandlersOfSameType
                         | PointerHandler.ApprovesTakeOverByHandlersOfDifferentType
                         | PointerHandler.ApprovesTakeOverByItems
                         | PointerHandler.ApprovesCancellation
        onActiveChanged: {
            if (active) {
                gv.fitMode = false;   // panning is a manual view change; stop auto-fit on resize
                gv._panSX = centroid.scenePosition.x; gv._panSY = centroid.scenePosition.y;
                gv._pan0X = gv.panX; gv._pan0Y = gv.panY;
            }
        }
        onCentroidChanged: {
            if (!active) return;
            gv.panX = gv._pan0X + (centroid.scenePosition.x - gv._panSX);
            gv.panY = gv._pan0Y + (centroid.scenePosition.y - gv._panSY);
        }
    }

    // Edge layer: retained QtQuick.Shapes geometry (GPU), not a large repainted
    // Canvas image. Each edge is a cubic ShapePath + a filled arrowhead; they
    // bind to node positions (gv.rev) and the hot transition, so they update
    // reactively with no per-frame bitmap. `requestPaint` is a no-op kept so the
    // existing callers stay valid.
    Item {
        id: edges
        anchors.fill: parent        // path coords are content coords
        function requestPaint() {}

        Repeater {
            model: gv.shownTrans          // sliced during a load ramp (see renderCount)
            delegate: Shape {
                id: es
                required property var modelData
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                readonly property bool selfLoop: modelData.from === modelData.to
                readonly property bool hot: gv.isHot(modelData)
                readonly property color col: hot ? gv.currentColor : gv.edgeColorEff
                // Cubic control points in content coords (a quad edge is lifted to
                // an equivalent cubic). Recomputes on move / style / curvature.
                readonly property var c: {
                    gv.rev; gv.edgeStyle; gv.curvature;
                    var pf = gv.posOf(modelData.from), pt = gv.posOf(modelData.to);
                    if (pf.x < -900 || pt.x < -900) return null;
                    if (selfLoop) {
                        var sp = gv.selfParams(modelData), sg = gv.selfGeom(pf, sp.a, sp.r, gv.nodeRadius(modelData.from));
                        return { sx: sg.sx, sy: sg.sy, c1x: sg.csx, c1y: sg.csy,
                                 c2x: sg.cex, c2y: sg.cey, ex: sg.ex, ey: sg.ey };
                    }
                    var g = gv.edgeGeom(modelData);
                    return { sx: g.sx, sy: g.sy,
                             c1x: g.sx + 2 / 3 * (g.mx - g.sx), c1y: g.sy + 2 / 3 * (g.my - g.sy),
                             c2x: g.ex + 2 / 3 * (g.mx - g.ex), c2y: g.ey + 2 / 3 * (g.my - g.ey),
                             ex: g.ex, ey: g.ey };
                }
                readonly property var ah: {        // arrowhead triangle along the end tangent
                    if (!c) return null;
                    var dx = c.ex - c.c2x, dy = c.ey - c.c2y, l = Math.hypot(dx, dy); if (l < 0.001) l = 1;
                    dx /= l; dy /= l;
                    var a = 11, w = 6, bx = c.ex - dx * a, by = c.ey - dy * a, nx = -dy, ny = dx;
                    return { tx: c.ex, ty: c.ey, lx: bx + nx * w, ly: by + ny * w, rx: bx - nx * w, ry: by - ny * w };
                }
                visible: c !== null

                ShapePath {
                    strokeColor: es.col
                    strokeWidth: es.hot ? 3.5 : 2
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: es.c ? es.c.sx : 0
                    startY: es.c ? es.c.sy : 0
                    PathCubic {
                        x: es.c ? es.c.ex : 0; y: es.c ? es.c.ey : 0
                        control1X: es.c ? es.c.c1x : 0; control1Y: es.c ? es.c.c1y : 0
                        control2X: es.c ? es.c.c2x : 0; control2Y: es.c ? es.c.c2y : 0
                    }
                }
                ShapePath {
                    strokeWidth: 0
                    fillColor: es.col
                    startX: es.ah ? es.ah.tx : 0
                    startY: es.ah ? es.ah.ty : 0
                    PathLine { x: es.ah ? es.ah.lx : 0; y: es.ah ? es.ah.ly : 0 }
                    PathLine { x: es.ah ? es.ah.rx : 0; y: es.ah ? es.ah.ry : 0 }
                    PathLine { x: es.ah ? es.ah.tx : 0; y: es.ah ? es.ah.ty : 0 }
                }
            }
        }

        // Initial-state stub arrow.
        Shape {
            id: initialStub
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            readonly property var s: {
                gv.rev;
                if (!gv.ctl) return null;
                var nm = gv.ctl.initialState;
                var ip = gv.posOf(nm);
                if (ip.x < -900) return null;
                var ox, oy;
                var ovr = gv.startAngle[nm];
                if (ovr !== undefined) {
                    // User-set direction: point the stub outward along the saved angle.
                    ox = Math.cos(ovr); oy = Math.sin(ovr);
                } else {
                    // Default: radially away from the canvas centre.
                    ox = ip.x - gv.width / 2; oy = ip.y - gv.height / 2;
                    var ol = Math.hypot(ox, oy);
                    if (ol < 1) { ox = 0; oy = -1; ol = 1; }
                    ox /= ol; oy /= ol;
                }
                var inr = gv.nodeRadius(nm);   // per-state radius of the initial state
                var sX = ip.x + ox * (inr + 30), sY = ip.y + oy * (inr + 30);
                var eX = ip.x + ox * (inr + 3), eY = ip.y + oy * (inr + 3);
                var dx = eX - sX, dy = eY - sY, l = Math.hypot(dx, dy); if (l < 0.001) l = 1;
                dx /= l; dy /= l;
                var a = 11, w = 6, bx = eX - dx * a, by = eY - dy * a, nx = -dy, ny = dx;
                return { sX: sX, sY: sY, eX: eX, eY: eY, lx: bx + nx * w, ly: by + ny * w, rx: bx - nx * w, ry: by - ny * w };
            }
            visible: s !== null
            ShapePath {
                strokeColor: gv.initialColor; strokeWidth: 2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                startX: initialStub.s ? initialStub.s.sX : 0
                startY: initialStub.s ? initialStub.s.sY : 0
                PathLine { x: initialStub.s ? initialStub.s.eX : 0; y: initialStub.s ? initialStub.s.eY : 0 }
            }
            ShapePath {
                strokeWidth: 0; fillColor: gv.initialColor
                startX: initialStub.s ? initialStub.s.eX : 0
                startY: initialStub.s ? initialStub.s.eY : 0
                PathLine { x: initialStub.s ? initialStub.s.lx : 0; y: initialStub.s ? initialStub.s.ly : 0 }
                PathLine { x: initialStub.s ? initialStub.s.rx : 0; y: initialStub.s ? initialStub.s.ry : 0 }
                PathLine { x: initialStub.s ? initialStub.s.eX : 0; y: initialStub.s ? initialStub.s.eY : 0 }
            }
        }
    }

    // Moving token on its own small overlay: only this ~tiny item moves/rotates
    // as tokenT changes, so the large edge Canvas above does not repaint 60fps.
    Item {
        id: tokenLayer
        readonly property var tp: gv.tokenPos()
        visible: tp !== null
        x: tp ? tp.x : 0
        y: tp ? tp.y : 0
        rotation: tp ? tp.ang : 0
        z: 5
        Canvas {
            id: tokenCanvas
            width: 100; height: 100                  // roomy enough for an up-scaled token
            anchors.centerIn: parent
            renderStrategy: Canvas.Immediate
            renderTarget: Canvas.Image
            // Drawn once (and on style/colour/size change) pointing +x; the parent
            // Item positions and rotates it — no per-frame repaint.
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                gv.drawToken(ctx, 50, 50, 1, 0);   // constant shape; parent positions/rotates it
            }
            Connections {
                target: gv
                function onTokenStyleChanged() { tokenCanvas.requestPaint(); }
                function onTokenColorChanged() { tokenCanvas.requestPaint(); }
                function onTokenScaleChanged() { tokenCanvas.requestPaint(); }
            }
            Component.onCompleted: requestPaint()
        }
    }

    // Transition symbol labels (follow the nodes via gv.rev; amber when hot).
    Repeater {
        model: gv.shownTrans
        delegate: Rectangle {
            id: lblBox
            required property var modelData
            property point p: (gv.rev, gv.labelAdj, gv.labelDisplayPos(modelData))
            property bool hot: gv.isHot(modelData)
            property bool selected: gv.selectedKey === gv.edgeKey(modelData)
            x: p.x - width / 2
            y: p.y - height / 2
            width: lbl.width + 8
            height: lbl.implicitHeight + 2
            radius: 3
            color: gv.labelBg
            border.width: lblBox.selected ? 2 : 1
            border.color: lblBox.selected ? gv.currentColor : (lblBox.hot ? gv.currentColor : gv.labelBorder)
            Text {
                id: lbl; anchors.centerIn: parent
                text: lblBox.modelData.symbol
                width: Math.min(implicitWidth, 60)   // cap over-long symbols
                elide: Text.ElideRight
                color: lblBox.hot ? Qt.darker(gv.currentColor, 1.4) : gv.labelTextEff
                font.bold: true; font.pixelSize: 12
            }
            HoverHandler {
                id: lblHover
                onHoveredChanged: {
                    var info = lblBox.modelData.from + "  —" + lblBox.modelData.symbol
                               + "→  " + lblBox.modelData.to
                    if (hovered) { gv.hoverInfo = info; gv.hoverEntry = ""; gv.hoverExit = "" }
                    else if (gv.hoverInfo === info) gv.hoverInfo = ""
                }
            }

            // Drag a transition's label to reshape that arrow — a normal edge
            // bends toward the cursor; a self-loop rotates around its node (and
            // its size follows the drag distance). Double-click resets the edge.
            MouseArea {
                anchors.fill: parent
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.SizeAllCursor
                readonly property bool self: lblBox.modelData.from === lblBox.modelData.to
                // Click selects this edge (reveals endpoint handles for non-self edges).
                onClicked: function(m) { gv.selectedKey = gv.edgeKey(lblBox.modelData); gv.selectedState = ""; }
                onPositionChanged: function(m) {
                    if (!pressed) return;
                    var gpt = mapToItem(content, m.x, m.y);
                    if (self) {
                        var c = gv.posOf(lblBox.modelData.from);
                        var dx = gpt.x - c.x, dy = gpt.y - c.y;
                        var dist = Math.hypot(dx, dy);
                        gv.edgeSelf[gv.edgeKey(lblBox.modelData)] =
                            { a: Math.atan2(dy, dx), r: Math.max(24, Math.min(dist - gv.nr, 140)) };
                    } else {
                        var p = gv.posOf(lblBox.modelData.from), q = gv.posOf(lblBox.modelData.to);
                        var ex = q.x - p.x, ey = q.y - p.y, len = Math.hypot(ex, ey);
                        if (len < 1) len = 1;
                        var px = -ey / len, py = ex / len;          // unit perpendicular
                        var midx = (p.x + q.x) / 2, midy = (p.y + q.y) / 2;
                        var signed = (gpt.x - midx) * px + (gpt.y - midy) * py;
                        gv.edgeBend[gv.edgeKey(lblBox.modelData)] = signed * 2;  // label sits at bend/2
                    }
                    gv.rev++;
                    edges.requestPaint();
                }
                onDoubleClicked: function(m) {
                    if (self) delete gv.edgeSelf[gv.edgeKey(lblBox.modelData)];
                    else delete gv.edgeBend[gv.edgeKey(lblBox.modelData)];
                    gv.rev++;
                    edges.requestPaint();
                }
            }
        }
    }

    // Draggable state nodes.
    Repeater {
        model: nodeModel
        delegate: Item {
            id: nodeItem
            required property int index
            required property var model
            readonly property real r: gv.nodeRadius(nodeItem.model.name)   // per-state size
            x: nodeItem.model.x - r
            y: nodeItem.model.y - r
            width: r * 2
            height: r * 2
            z: 10

            // Expanding ring pulsed when this state is (re)entered during a run.
            Rectangle {
                id: pulse
                anchors.centerIn: parent
                width: nodeItem.r * 2; height: width; radius: width / 2
                color: "transparent"; border.color: gv.currentColor; border.width: 3
                opacity: 0
                z: -1
            }
            ParallelAnimation {
                id: pulseAnim
                property int dur: Math.max(120, Math.round(gv.stepMs * 0.6))
                NumberAnimation { target: pulse; property: "scale"; from: 1.0; to: 2.1; duration: pulseAnim.dur; easing.type: Easing.OutQuad }
                NumberAnimation { target: pulse; property: "opacity"; from: 0.85; to: 0.0; duration: pulseAnim.dur }
            }

            Rectangle {  // selection highlight ring (click a state to select it)
                visible: gv.selectedState === nodeItem.model.name
                anchors.centerIn: parent
                width: nodeItem.r * 2 + 14; height: width; radius: width / 2
                color: "transparent"; border.color: gv.currentColor; border.width: 2
            }
            Rectangle {  // double ring for accepting states
                visible: gv.ctl.acceptStates.indexOf(nodeItem.model.name) >= 0
                anchors.centerIn: parent
                width: nodeItem.r * 2 + 10; height: width; radius: width / 2
                color: "transparent"; border.color: gv.acceptColor; border.width: 2
            }
            Rectangle {
                id: disc
                anchors.fill: parent
                radius: nodeItem.r
                property bool cur: gv.visualCurrent === nodeItem.model.name
                onCurChanged: if (cur) pulseAnim.restart()   // pulse when the token arrives
                color: disc.cur ? gv.currentColor : gv.stateFill(nodeItem.model.name)
                border.color: disc.cur ? Qt.darker(gv.currentColor, 1.5) : gv.nodeBorder
                border.width: disc.cur ? 3 : 2
                Text {
                    id: nodeLabel
                    anchors.centerIn: parent
                    width: nodeItem.r * 2 - 10            // keep long names inside the circle
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: nodeItem.model.name
                    font.bold: true; font.pixelSize: 13
                    color: disc.cur ? "#1c1917" : gv.nodeText
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                // Show the full state name (plus any entry/exit actions) in the
                // fixed hover banner (top of diagram).
                onContainsMouseChanged: {
                    if (containsMouse) {
                        gv.hoverInfo = nodeItem.model.name
                        gv.hoverEntry = gv.entryMap[nodeItem.model.name] || ""
                        gv.hoverExit = gv.exitMap[nodeItem.model.name] || ""
                    } else if (gv.hoverInfo === nodeItem.model.name) {
                        gv.hoverInfo = ""; gv.hoverEntry = ""; gv.hoverExit = ""
                    }
                }
                property real offX: 0
                property real offY: 0
                onPressed: function(m) {
                    gv.selectState(nodeItem.model.name);   // select the state (for size/colour editing)
                    var g = mapToItem(content, m.x, m.y);
                    offX = g.x - nodeItem.model.x;
                    offY = g.y - nodeItem.model.y;
                }
                onPositionChanged: function(m) {
                    if (!pressed) return;  // hover moves must not drag (hoverEnabled is on for tooltips)
                    var g = mapToItem(content, m.x, m.y);
                    var nx = Math.round((g.x - offX) / gv.grid) * gv.grid;  // snap to grid
                    var ny = Math.round((g.y - offY) / gv.grid) * gv.grid;
                    nodeModel.setProperty(nodeItem.index, "x", nx);
                    nodeModel.setProperty(nodeItem.index, "y", ny);
                    nodeModel.setProperty(nodeItem.index, "pinned", true);
                    gv.rev++;
                    edges.requestPaint();
                }
                onDoubleClicked: function(m) {  // reset this node to its ring slot
                    nodeModel.setProperty(nodeItem.index, "pinned", false);
                    gv.relayout();
                    edges.requestPaint();
                }
            }

            // UML-style entry/exit action labels. Default position is beneath the
            // node, but the block is draggable around the circle (angle persisted
            // per state); double-click resets to "below". The last-fired transition
            // tints the entry(to)/exit(from) line to cue the run.
            Item {
                id: actionBlock
                visible: gv.showActions && (actionBlock.entryTxt.length > 0 || actionBlock.exitTxt.length > 0)
                z: 9
                width: actionLayout.implicitWidth
                height: actionLayout.implicitHeight
                property string entryTxt: gv.entryMap[nodeItem.model.name] || ""
                property string exitTxt: gv.exitMap[nodeItem.model.name] || ""
                readonly property color entryColor: (gv.ctl && gv.ctl.lastTo === nodeItem.model.name)
                                                     ? gv.currentColor : gv.paneText
                readonly property color exitColor: (gv.ctl && gv.ctl.lastFrom === nodeItem.model.name)
                                                    ? gv.currentColor : gv.paneTextMuted
                // Angle around the node (default straight down = PI/2 in screen space).
                readonly property real ang: {
                    gv.rev;  // re-evaluate when overrides change (drag/reset/import)
                    var a = gv.actionAngle[nodeItem.model.name];
                    return a === undefined ? Math.PI / 2 : a;
                }
                // Place the block so its nearest edge clears the circle along `ang`.
                readonly property point placed: {
                    var cx = Math.cos(ang), cy = Math.sin(ang);
                    var hw = width / 2, hh = height / 2;
                    var tb = Math.min(Math.abs(cx) < 1e-4 ? 1e9 : hw / Math.abs(cx),
                                      Math.abs(cy) < 1e-4 ? 1e9 : hh / Math.abs(cy));
                    var d = nodeItem.r + 4 + tb;  // node radius + gap + half-extent toward `ang`
                    return Qt.point(nodeItem.r + cx * d - hw, nodeItem.r + cy * d - hh);
                }
                x: placed.x
                y: placed.y
                Column {
                    id: actionLayout
                    anchors.centerIn: parent
                    spacing: 1
                    Row {
                        visible: actionBlock.entryTxt.length > 0
                        anchors.left: parent.left
                        spacing: 3
                        ActionGlyph { isExit: false; color: actionBlock.entryColor
                                      anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, gv.nr * 4)
                            elide: Text.ElideRight
                            text: actionBlock.entryTxt
                            font.pixelSize: 11
                            color: actionBlock.entryColor
                        }
                    }
                    Row {
                        visible: actionBlock.exitTxt.length > 0
                        anchors.left: parent.left
                        spacing: 3
                        ActionGlyph { isExit: true; color: actionBlock.exitColor
                                      anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, gv.nr * 4)
                            elide: Text.ElideRight
                            text: actionBlock.exitTxt
                            font.pixelSize: 11
                            color: actionBlock.exitColor
                        }
                    }
                }
                // Drag the whole block around the node; double-click resets to below.
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    onPositionChanged: function(m) {
                        if (!pressed) return;
                        var gp = mapToItem(content, m.x, m.y);
                        gv.actionAngle[nodeItem.model.name] =
                            Math.atan2(gp.y - nodeItem.model.y, gp.x - nodeItem.model.x);
                        gv.rev++;
                    }
                    onDoubleClicked: function(m) {
                        delete gv.actionAngle[nodeItem.model.name];
                        gv.rev++;
                    }
                }
            }
        }
    }

    // Endpoint drag handles for the selected (non-self) edge: drag either handle
    // around its node to move where the arrow attaches; double-click resets it.
    Repeater {
        model: gv.shownTrans
        delegate: Item {
            id: hs
            required property var modelData
            anchors.fill: parent
            z: 20
            visible: gv.selectedKey === gv.edgeKey(modelData) && modelData.from !== modelData.to
            property var g: (gv.rev, gv.edgeGeom(modelData))

            component Handle: Rectangle {
                property bool fromEnd: true
                width: 15; height: 15; radius: 8
                color: "#ffffff"; border.color: gv.currentColor; border.width: 2
                visible: hs.visible
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    onPositionChanged: function(m) {
                        if (!pressed) return;
                        var gp = mapToItem(content, m.x, m.y);
                        var c = gv.posOf(parent.fromEnd ? hs.modelData.from : hs.modelData.to);
                        var k = gv.edgeKey(hs.modelData);
                        var o = gv.edgeAnchor[k] || {};
                        var ang = Math.atan2(gp.y - c.y, gp.x - c.x);
                        if (parent.fromEnd) o.fa = ang; else o.ta = ang;
                        gv.edgeAnchor[k] = o;
                        gv.rev++; edges.requestPaint();
                    }
                    onDoubleClicked: function(m) {
                        var k = gv.edgeKey(hs.modelData);
                        var o = gv.edgeAnchor[k] || {};
                        if (parent.fromEnd) delete o.fa; else delete o.ta;
                        gv.edgeAnchor[k] = o;
                        gv.rev++; edges.requestPaint();
                    }
                }
            }
            Handle { fromEnd: true;  x: hs.g.sx - width / 2; y: hs.g.sy - height / 2 }
            Handle { fromEnd: false; x: hs.g.ex - width / 2; y: hs.g.ey - height / 2 }
        }
    }

    // Initial-state stub editing: click the green start arrow to select it, then
    // drag the handle to change its direction; double-click the handle resets to
    // automatic. The handle shows only while selected; tapping empty space (the
    // background TapHandler) deselects and hides it.
    Item {
        anchors.fill: parent
        z: 20
        visible: initialStub.s !== null
        // Invisible hit area over the stub — selects it (shares selectedKey).
        MouseArea {
            width: 26; height: 26
            x: (initialStub.s ? (initialStub.s.sX + initialStub.s.eX) / 2 : 0) - width / 2
            y: (initialStub.s ? (initialStub.s.sY + initialStub.s.eY) / 2 : 0) - height / 2
            cursorShape: Qt.PointingHandCursor
            onClicked: { gv.selectedKey = gv.startKey; gv.selectedState = "" }
        }
        // Direction handle — only while the stub is selected.
        Rectangle {
            visible: gv.selectedKey === gv.startKey
            width: 15; height: 15; radius: 8
            color: "#ffffff"; border.color: gv.initialColor; border.width: 2
            x: (initialStub.s ? initialStub.s.sX : 0) - width / 2
            y: (initialStub.s ? initialStub.s.sY : 0) - height / 2
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                onPositionChanged: function(m) {
                    if (!pressed) return;
                    var gp = mapToItem(content, m.x, m.y);
                    var nm = gv.ctl.initialState;
                    var c = gv.posOf(nm);
                    gv.startAngle[nm] = Math.atan2(gp.y - c.y, gp.x - c.x);
                    gv.rev++;
                }
                onDoubleClicked: function(m) {
                    delete gv.startAngle[gv.ctl.initialState];
                    gv.rev++;
                }
            }
        }
    }
    }  // end content

    // Fixed hover banner: viewport-anchored (does not scale/pan with the diagram)
    // at the top-centre, clear of the zoom controls and the run bar below. Shows
    // the hovered state / transition so the info never covers the controls.
    Rectangle {
        id: hoverBanner
        visible: gv.hoverInfo.length > 0
        z: 75                                  // above the panes, so it's never hidden
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: gv.fitTopInset      // sit just below the top row of panes
        height: 30
        width: Math.min(gv.width - 24, bannerRow.implicitWidth + 28)
        radius: 6
        color: gv.labelBg
        border.color: gv.labelBorder
        Row {
            id: bannerRow
            anchors.centerIn: parent
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, gv.width * 0.4)
                text: gv.hoverInfo
                elide: Text.ElideRight
                color: gv.labelText
                font.pixelSize: 12; font.bold: true
            }
            Row {  // entry action — same icon as on the diagram
                visible: gv.hoverEntry.length > 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                ActionGlyph { isExit: false; color: gv.labelText; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, gv.width * 0.3)
                    text: gv.hoverEntry
                    elide: Text.ElideRight
                    color: gv.labelText
                    font.pixelSize: 12; font.bold: true
                }
            }
            Row {  // exit action — same icon as on the diagram
                visible: gv.hoverExit.length > 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                ActionGlyph { isExit: true; color: gv.labelText; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, gv.width * 0.3)
                    text: gv.hoverExit
                    elide: Text.ElideRight
                    color: gv.labelText
                    font.pixelSize: 12; font.bold: true
                }
            }
        }
    }

    // On-canvas control panes (info / legend / edge / layout / zoom / control /
    // animation + run-trace + show/hide toggle), extracted into CanvasPanes.qml.
    // `gv` back-reference wires them to this view; it fills the view and sits
    // above the diagram (below the hover banner).
    CanvasPanes { z: 60; gv: gv }

    // Ctrl + mouse wheel zooms the diagram.
    WheelHandler {
        acceptedModifiers: Qt.ControlModifier
        onWheel: function(e) { gv.zoomBy(e.angleDelta.y > 0 ? 1.1 : 1 / 1.1); }
    }

    Connections {
        target: gv.ctl
        function onDefinitionChanged() { gv.refreshTransList(); gv.refreshActionMaps(); gv.rebuildNodes(); }
        function onRunChanged() {
            edges.requestPaint();
            // Outside a travelling step (reset/build/manual no-op) track the state directly.
            if (!tokenAnim.running) gv.visualCurrent = gv.ctl.current;
        }
        function onStepped() {
            gv.visualCurrent = gv.ctl.lastFrom;   // keep source lit while the token travels
            tokenAnim.restart();
        }
    }
    // Re-fit the diagram to the canvas shortly after a resize so it never ends
    // up spilling past the panel border.
    Timer { id: refitTimer; interval: 150; onTriggered: gv.fitView() }
    onWidthChanged: { relayout(); if (fitMode) refitTimer.restart() }
    onHeightChanged: { relayout(); if (fitMode) refitTimer.restart() }
    onFitModeChanged: if (!fitMode) refitTimer.stop()   // cancel a pending refit on manual zoom/pan
    onRevChanged: { refreshPosCache(); changed(); }   // layout / edge-override edits
    onEdgeStyleChanged: { rev++; edges.requestPaint(); }
    onCurvatureChanged: { rev++; edges.requestPaint(); }
    onTokenStyleChanged: changed()
    onTokenScaleChanged: changed()
    onShowGridChanged: { grid.requestPaint(); changed(); }
    onInitialColorChanged: { edges.requestPaint(); changed(); }
    onAcceptColorChanged: changed()
    onCurrentColorChanged: { edges.requestPaint(); changed(); }
    onTokenColorChanged: { edges.requestPaint(); changed(); }
    onEdgeColorChanged: edges.requestPaint()   // theme-driven, not part of the document
    onNodeColorOverrideChanged: { changed(); edges.requestPaint() }   // user overrides ARE part of the document
    onEdgeColorOverrideChanged: changed()
    onLabelColorOverrideChanged: changed()
    onAllStateScaleChanged: { rev++; edges.requestPaint() }           // global size: resize all states + re-trim edges
    Component.onCompleted: {
        refreshTransList(); rebuildNodes();
        if (ctl) visualCurrent = ctl.current;
    }
}
