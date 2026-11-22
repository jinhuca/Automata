pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick3D
import QtQuick3D.Helpers

// Phase 1 — read-only 3D rendering of the DFA, drop-in for the canvas region.
// States are spheres on a ring in the XZ plane (coloured by role), transitions
// are tube + cone-arrowhead edges, and names/symbols are billboarded labels that
// face the camera. Orbit to rotate, wheel to zoom, Fit to reframe. Reuses the
// model (ctl) unchanged; no editing yet (that's a later phase).
Item {
    id: root
    property var ctl
    property string runWord: ""          // word to Run; shared with the 2D view
    signal runWordEdited(string w)       // emitted when the 3D field is edited
    property bool canvasFull: false      // mirrors the window full-screen state
    signal fullScreenToggleRequested()   // Full screen button -> Main toggles the window
    property bool canUndo: false         // document undo/redo availability (from Main)
    property bool canRedo: false
    signal undoRequested()
    signal redoRequested()
    property bool showGrid3d: true       // floor grid on/off
    property bool showAxes3d: true       // X/Y/Z reference axes on/off
    property bool showEdgeLabels3d: true // transition (symbol) labels on/off (off = faster at scale)
    // Range for the per-axis position sliders (symmetric about the origin); grows
    // with the layout so a selected state can be moved anywhere it sensibly sits.
    readonly property real posRange: Math.max(400, layoutR * 2)

    // Colours — bound from Main to the app Theme and the shared 2D legend colours
    // (initial/accept/current/token), so 3D follows light/dark and the user's
    // recolouring. Defaults mirror the standalone dark look.
    property color colInitial: "#15803d"
    property color colAccept:  "#0ea5e9"
    property color colCurrent: "#f59e0b"
    property color colToken:   "#67e8f9"
    property color colNode:    "#3b82f6"
    property color colEdge:    "#94a3b8"
    property color colBg:      "#0b1220"   // scene background
    property color colLabel:   "#e2e8f0"   // node/edge/trace text
    property color colMuted:   "#94a3b8"   // hint / inactive text
    property color colPaneBg:  "#e6111827" // run-strip background
    property color colPaneBorder: "#334155"

    // --- style options (user-customizable; persisted in the view3d block) ---
    property real nodeScale: 1.0                 // sphere size multiplier (0.5..2)
    property real edgeScale: 1.0                 // line/arrowhead thickness multiplier (0.5..2)
    property real arrowScale3d: 1.0              // arrowhead length multiplier (0.3..2)
    // Curve tessellation: each segment of a curved edge / self-loop is its own Model,
    // so drop the sample count on large graphs to keep the geometry (and draw calls)
    // in check. Straight edges always use a single segment regardless.
    readonly property int edgeSegs: (ctl && ctl.transitions && ctl.transitions.length > 50) ? 12 : 28
    property string edge3dStyle: "straight"      // "straight" | "curved"
    property real curvature3d: 0.25              // bow amount (0..1) when curved
    property string tokenStyle3d: "dot"          // "dot" | "ring" | "comet" | "chevron"
    property real tokenScale3d: 1.0              // token size multiplier (0.5..2)
    property color nodeColorOverride: "transparent"   // a==0 => use the Theme-bound colNode
    readonly property color colNodeEff: nodeColorOverride.a > 0 ? nodeColorOverride : colNode
    property color edgeColorOverride: "transparent"   // a==0 => use the Theme-bound colEdge
    readonly property color colEdgeEff: edgeColorOverride.a > 0 ? edgeColorOverride : colEdge
    property int nodeLabelSize: 24                     // state-name label font size
    // Transition (symbol) label options.
    property int edgeLabelSize: 18                     // font size
    property real labelAlong: 0.5                      // position along the edge (0=source .. 1=target)
    property color edgeLabelColorOverride: "transparent"
    readonly property color colLabelEff: edgeLabelColorOverride.a > 0 ? edgeLabelColorOverride : colLabel
    property var stateColors: ({})               // per-state colour overrides: name -> color string
    signal colorEditRequested(string role)       // swatch double-clicked -> Main opens the colour dialog
    // Shared accents (initial/accept/current/token) live on the 2D view; ask Main
    // to apply them there so both views stay in sync.
    signal accentColorRequested(string role, color c)

    // Paint-bucket workflow, mirroring the 2D legend. `workingColor` is bound from
    // the 2D view (shared paint colour); single-clicking a swatch paints it onto
    // that role, double-clicking opens the picker (which updates the shared colour).
    property color workingColor: "#f59e0b"
    readonly property var colorDefaults3D: ({
        "initial": "#15803d", "accept": "#15803d", "current": "#f59e0b", "token": "#f59e0b",
        "node3d": "transparent", "edge3d": "transparent", "elabel": "transparent"
    })
    // Apply a colour to one Colours-pane role (accents go up to the 2D view).
    function applyColor3D(role, c) {
        if (role === "node3d")       nodeColorOverride = c;
        else if (role === "edge3d")  edgeColorOverride = c;
        else if (role === "elabel")  edgeLabelColorOverride = c;
        else                         accentColorRequested(role, c);   // initial/accept/current/token
    }
    function paintRole3D(role) { applyColor3D(role, workingColor); }   // single-click
    function resetColors3D() {
        for (var r in colorDefaults3D) applyColor3D(r, colorDefaults3D[r]);
        stateColors = ({});   // drop per-state overrides (coloured via the Selection control)
        edgeColors = ({});    // drop per-edge overrides
        posRev++;             // refresh the colour bindings
    }
    // Current colour shown by a role's swatch, used to seed the picker (symmetric
    // with the 2D view's colorForRole).
    function colorForRole3D(role) {
        return role === "initial" ? colInitial
             : role === "accept"  ? colAccept
             : role === "current" ? colCurrent
             : role === "token"   ? colToken
             : role === "state"   ? selectedBaseColor()
             : role === "edgesel" ? selectedEdgeBaseColor()
             : role === "elabel"  ? colLabelEff
             : role === "edge3d"  ? colEdgeEff
             :                      colNodeEff;
    }

    // Per-state colour: set/clear the override for the currently selected state.
    function applySelectedColor(c) {
        if (selected === "") return;
        var m = {}; for (var k in stateColors) m[k] = stateColors[k];
        m[selected] = "" + c; stateColors = m;
    }
    function clearSelectedColor() {
        if (selected === "" || stateColors[selected] === undefined) return;
        var m = {}; for (var k in stateColors) if (k !== selected) m[k] = stateColors[k];
        stateColors = m;
    }
    // Starting colour for the dialog when recolouring the selected state.
    function selectedBaseColor() {
        return (selected !== "" && stateColors[selected] !== undefined) ? stateColors[selected] : colNodeEff;
    }

    readonly property var states: ctl ? ctl.states : []
    readonly property int nodeR: 30                               // base sphere radius (scale 0.6 of #Sphere/2)
    readonly property real nr: nodeR * nodeScale                  // effective radius (size slider)
    readonly property real layoutR: 120 + 22 * Math.max(1, states.length)

    // Static local ring (XZ plane) for the "ring" token style; placed under the
    // token Node so it inherits the travel-direction rotation.
    readonly property var tokenRingSegs: {
        var r = 11, K = 12, p = [];
        for (var i = 0; i <= K; i++) { var a = 2 * Math.PI * i / K; p.push(Qt.vector3d(r * Math.cos(a), 0, r * Math.sin(a))); }
        var s = [];
        for (var j = 0; j < K; j++) { var p1 = p[j], p2 = p[j + 1], d = p2.minus(p1), L = Math.max(0.001, d.length()); s.push({ mid: p1.plus(p2).times(0.5), quat: quatFromYTo(d.times(1 / L)), len: L }); }
        return s;
    }

    // --- interaction state (Phase 3) ---
    property var posOverride: ({})   // stateName -> vector3d; user-dragged (pinned) positions
    property int posRev: 0           // bump to re-evaluate posOf-based bindings
    property string selected: ""     // picked state (empty = none)
    property string dragName: ""     // state being dragged (empty = not dragging)

    // --- per-edge editing: select one edge, drag its tail / head / curve ---
    property string selectedEdge: ""  // edge key being edited (exclusive with `selected`)
    property string edgeDrag: ""      // "tail" | "head" | "curve" while a handle is dragged
    property var edgeTail: ({})        // key -> unit dir from the source centre
    property var edgeHead: ({})        // key -> unit dir from the target centre
    property var edgeCtrl: ({})        // key -> world control point
    property var edgeColors: ({})      // key -> per-edge colour override
    function edgeKey(t) { return t.from + "\u001f" + t.symbol + "\u001f" + t.to; }

    // Per-edge colour: set/clear the override for the currently selected edge.
    function applySelectedEdgeColor(c) {
        if (selectedEdge === "") return;
        var m = {}; for (var k in edgeColors) m[k] = edgeColors[k];
        m[selectedEdge] = "" + c; edgeColors = m;
    }
    function clearSelectedEdgeColor() {
        if (selectedEdge === "" || edgeColors[selectedEdge] === undefined) return;
        var m = {}; for (var k in edgeColors) if (k !== selectedEdge) m[k] = edgeColors[k];
        edgeColors = m;
    }
    function selectedEdgeBaseColor() {
        return (selectedEdge !== "" && edgeColors[selectedEdge] !== undefined) ? edgeColors[selectedEdge] : colEdgeEff;
    }

    // --- 3D cuboid-grid layout ---
    // simPos holds the auto-computed positions; a user-dragged node (posOverride)
    // pins it and takes precedence (see posOf). computeLayout() arranges the states
    // on a near-cube 3D lattice (dimensions chosen as close to a cube as possible,
    // filling x, then y, then z), centred on the origin. fit() then frames it.
    property var simPos: ({})
    readonly property real cellStep: nodeR * 4.0     // spacing between grid cells (size-slider independent)
    // Grid dimensions (nx·ny·nz ≥ n), as cube-like as possible.
    function gridDims(n) {
        var nx = Math.ceil(Math.cbrt(n));
        var ny = Math.ceil(Math.sqrt(n / nx));
        var nz = Math.ceil(n / Math.max(1, nx * ny));
        return { nx: nx, ny: ny, nz: nz };
    }
    function seedPos(i, n) {   // i-th cell of the centred cuboid lattice
        var d = gridDims(n), step = cellStep;
        var ix = i % d.nx;
        var iy = Math.floor(i / d.nx) % d.ny;
        var iz = Math.floor(i / (d.nx * d.ny));
        return Qt.vector3d((ix - (d.nx - 1) / 2) * step,
                           (iy - (d.ny - 1) / 2) * step,
                           (iz - (d.nz - 1) / 2) * step);
    }
    function computeLayout() {
        var ns = states, n = ns.length;
        if (n === 0) { simPos = ({}); posRev++; return; }
        var p = {};
        for (var i = 0; i < n; i++) p[ns[i]] = seedPos(i, n);
        simPos = p; posRev++;
    }
    // Full Re-layout: drop every manual placement — node pins AND per-edge
    // tail/head/curve overrides — so the whole diagram (nodes and edges) is laid
    // out afresh, then recompute + frame. Per-edge/‑state colours are kept.
    function relayoutAll() {
        posOverride = ({});
        edgeTail = ({}); edgeHead = ({}); edgeCtrl = ({});
        computeLayout();
        fit();
        posRev++;
    }

    // Position: user-dragged override, else the computed layout, else a seed.
    function posOf(name) {
        var o = posOverride[name];
        if (o !== undefined) return o;
        var s = simPos[name];
        if (s !== undefined) return s;
        var i = states.indexOf(name);
        return i < 0 ? Qt.vector3d(0, 0, 0) : seedPos(i, Math.max(1, states.length));
    }
    // Position of the selected state (for the X/Y/Z sliders); pins the state and
    // moves one axis when a slider is dragged.
    function selectedPos() { return selected !== "" ? posOf(selected) : Qt.vector3d(0, 0, 0); }
    function setSelectedAxis(axis, v) {
        if (selected === "") return;
        var p = posOf(selected);
        var np = Qt.vector3d(axis === "x" ? v : p.x, axis === "y" ? v : p.y, axis === "z" ? v : p.z);
        var m = {}; for (var k in posOverride) m[k] = posOverride[k];
        m[selected] = np; posOverride = m; posRev++;
    }
    // Curve control point of the selected edge (for the X/Y/Z sliders): the per-edge
    // override if set, else the current (curved bow / straight midpoint) point.
    function selectedEdgeCtrl() {
        var g = selectedEdgeABC();
        return g ? g.ctrl : Qt.vector3d(0, 0, 0);
    }
    function setSelectedEdgeAxis(axis, v) {
        if (selectedEdge === "") return;
        var cur = selectedEdgeCtrl();
        var np = Qt.vector3d(axis === "x" ? v : cur.x, axis === "y" ? v : cur.y, axis === "z" ? v : cur.z);
        var m = {}; for (var k in edgeCtrl) m[k] = edgeCtrl[k];
        m[selectedEdge] = np; edgeCtrl = m; posRev++;   // overriding the control point bends the edge
    }

    // Quaternion rotating the +Y axis (the default axis of #Cylinder / #Cone)
    // onto direction `dn` (unit vector).
    function quatFromYTo(dn) {
        var y = Qt.vector3d(0, 1, 0);
        var dot = Math.max(-1, Math.min(1, y.dotProduct(dn)));
        var axis = y.crossProduct(dn);
        if (axis.length() < 1e-6)
            return dot > 0 ? Qt.quaternion(1, 0, 0, 0) : Qt.quaternion(0, 1, 0, 0);
        axis = axis.normalized();
        var ang = Math.acos(dot), s = Math.sin(ang / 2);
        return Qt.quaternion(Math.cos(ang / 2), axis.x * s, axis.y * s, axis.z * s);
    }

    // Quaternion rotating +Z onto `dn` (used to aim the camera-facing drag plane).
    function quatFromZTo(dn) {
        var z = Qt.vector3d(0, 0, 1);
        var dot = Math.max(-1, Math.min(1, z.dotProduct(dn)));
        var axis = z.crossProduct(dn);
        if (axis.length() < 1e-6) return dot > 0 ? Qt.quaternion(1, 0, 0, 0) : Qt.quaternion(0, 0, 1, 0);
        axis = axis.normalized();
        var ang = Math.acos(dot), s = Math.sin(ang / 2);
        return Qt.quaternion(Math.cos(ang / 2), axis.x * s, axis.y * s, axis.z * s);
    }

    // Does the reverse transition to->from also exist? (reciprocal pair).
    function reciprocalExists(fromName, toName) {
        var tr = ctl ? ctl.transitions : [];
        for (var i = 0; i < tr.length; i++)
            if (tr[i].from === toName && tr[i].to === fromName) return true;
        return false;
    }

    // Trimmed polyline (rim-to-rim) for an edge: 2 points when straight, a sampled
    // quadratic Bézier when curved (control point bowed perpendicular to the edge;
    // reciprocal pairs bow to opposite sides). null for self/degenerate.
    // Endpoints a,b (on the node rims, honouring per-edge tail/head overrides) and
    // the curve control point (per-edge override, else the global bow, else none).
    function edgeABC(fromName, toName, key) {
        var srcC = posOf(fromName), tgtC = posOf(toName);
        var d = tgtC.minus(srcC), L = d.length();
        if (L < 1) return null;
        var dn = d.times(1 / L);
        var tailDir = (key && edgeTail[key] !== undefined) ? edgeTail[key] : dn;
        var headDir = (key && edgeHead[key] !== undefined) ? edgeHead[key] : dn.times(-1);
        var a = srcC.plus(tailDir.times(nr));
        var b = tgtC.plus(headDir.times(nr));
        var ctrl = (key && edgeCtrl[key] !== undefined) ? edgeCtrl[key] : null;
        var straight = false;
        if (!ctrl) {
            var curved = (edge3dStyle === "curved" && curvature3d > 0.001);
            var recip = reciprocalExists(fromName, toName);
            // Perpendicular used to bow (curved) or offset (straight) the edge. For a
            // reciprocal pair, base it on a canonical name-ordered direction + sign so
            // the two edges go to OPPOSITE sides. (A direction-dependent perp flips with
            // the traversal and would cancel the sign, leaving them coincident — the
            // z-fighting "speckled tube".)
            var base = dn, sgn = 1;
            if (recip) { var lowFirst = fromName < toName; base = lowFirst ? dn : dn.times(-1); sgn = lowFirst ? 1 : -1; }
            var up = Qt.vector3d(0, 1, 0);
            var perp = base.crossProduct(up);
            if (perp.length() < 1e-3) perp = base.crossProduct(Qt.vector3d(1, 0, 0));
            perp = perp.normalized().times(sgn);

            var hasOverride = key && (edgeTail[key] !== undefined || edgeHead[key] !== undefined);
            if (curved) {
                ctrl = a.plus(b).times(0.5).plus(perp.times(curvature3d * L * 0.5));
            } else {
                straight = true;
                // Separate reciprocal straight edges into two parallel tubes.
                if (recip && !hasOverride) {
                    var off = perp.times(Math.max(8, nr * 0.4));
                    a = a.plus(off); b = b.plus(off);
                }
                ctrl = a.plus(b).times(0.5);
            }
        }
        return { a: a, b: b, ctrl: ctrl, straight: straight };
    }

    function edgePath(fromName, toName, key) {
        if (fromName === toName) return null;
        var g = edgeABC(fromName, toName, key);
        if (!g) return null;
        if (g.straight) return [g.a, g.b];
        var K = edgeSegs, pts = [];   // more samples -> smoother curved tube (fewer on big graphs)
        for (var i = 0; i <= K; i++) {
            var t = i / K, it = 1 - t;
            pts.push(g.a.times(it * it).plus(g.ctrl.times(2 * it * t)).plus(g.b.times(t * t)));
        }
        return pts;
    }

    // Endpoints/control of the currently selected edge (for the drag handles).
    // selectedEdge key = "from\u001fsymbol\u001fto".
    function selectedEdgeABC() {
        if (selectedEdge === "") return null;
        var k = selectedEdge.split("\u001f");
        return edgeABC(k[0], k[2], selectedEdge);
    }

    // Segment transforms + arrowhead + label for an edge (straight or curved).
    function edgeXform(fromName, toName, key) {
        var pts = edgePath(fromName, toName, key);
        if (!pts) return null;
        var segs = [];
        for (var i = 0; i < pts.length - 1; i++) {
            var p1 = pts[i], p2 = pts[i + 1], dd = p2.minus(p1), L = Math.max(0.001, dd.length());
            segs.push({ mid: p1.plus(p2).times(0.5), quat: quatFromYTo(dd.times(1 / L)), len: L });
        }
        var last = pts.length - 1;
        var ld = pts[last].minus(pts[last - 1]); ld = ld.times(1 / Math.max(0.001, ld.length()));
        var headLen = 18 * arrowScale3d;   // cone length (matches the arrowhead's height scale below)
        return {
            segs: segs,
            headPos: pts[last].minus(ld.times(headLen / 2)),
            headQuat: quatFromYTo(ld),
            path: pts
        };
    }

    // Sample a polyline (uniform parameter) for the travelling token.
    function samplePath(pts, t) {
        if (!pts || pts.length < 2) return Qt.vector3d(0, 0, 0);
        var f = Math.max(0, Math.min(1, t)) * (pts.length - 1);
        var i = Math.min(pts.length - 2, Math.floor(f)), frac = f - i;
        return pts[i].times(1 - frac).plus(pts[i + 1].times(frac));
    }
    function sampleDir(pts, t) {
        if (!pts || pts.length < 2) return Qt.vector3d(1, 0, 0);
        var f = Math.max(0, Math.min(1, t)) * (pts.length - 1);
        var i = Math.min(pts.length - 2, Math.floor(f));
        var d = pts[i + 1].minus(pts[i]); return d.times(1 / Math.max(0.001, d.length()));
    }

    // Geometry for a self-loop (from === to). Mirrors the 2D view: a cubic-Bézier
    // loop that LEAVES the node surface, bulges out and RETURNS to a nearby point,
    // with the arrowhead at the return anchor pointing INTO the node along the
    // incoming tangent (a circle tangent to the sphere has no natural "into node"
    // direction — hence the earlier odd arrow). Successive self-loops on one state
    // fan out so they don't overlap.
    function selfLoopGeom(name, idx) {
        var c = posOf(name);
        var trans = ctl ? ctl.transitions : [];
        var rank = 0;
        for (var t = 0; t < idx && t < trans.length; t++)
            if (trans[t].from === name && trans[t].to === name) rank++;
        // Loop lives in the X–Y plane; `out` is the bulge direction (up by default),
        // rotated per rank so multiple self-loops splay around the node top.
        var ang = Math.PI / 2 + ((rank % 2 === 0 ? 1 : -1) * Math.ceil(rank / 2)) * (42 * Math.PI / 180);
        var out = Qt.vector3d(Math.cos(ang), Math.sin(ang), 0);
        var perp = Qt.vector3d(-Math.sin(ang), Math.cos(ang), 0);
        var reach = nr * 1.7, half = nr * 1.1, anchor = nr * 0.33;
        var b = c.plus(out.times(nr));                 // loop base on the node surface
        var s = b.minus(perp.times(anchor));           // start anchor (leaves the node)
        var e = b.plus(perp.times(anchor));            // end anchor (returns to the node)
        var c1 = b.plus(out.times(reach)).minus(perp.times(half));   // control 1
        var c2 = b.plus(out.times(reach)).plus(perp.times(half));    // control 2
        var K = edgeSegs, pts = [];
        for (var i = 0; i <= K; i++) {
            var u = i / K, iu = 1 - u;
            var w0 = iu * iu * iu, w1 = 3 * iu * iu * u, w2 = 3 * iu * u * u, w3 = u * u * u;
            pts.push(s.times(w0).plus(c1.times(w1)).plus(c2.times(w2)).plus(e.times(w3)));
        }
        var segs = [];
        for (var j = 0; j < K; j++) {
            var p1 = pts[j], p2 = pts[j + 1], d = p2.minus(p1), L = Math.max(0.001, d.length());
            segs.push({ mid: p1.plus(p2).times(0.5), quat: quatFromYTo(d.times(1 / L)), len: L });
        }
        var last = pts.length - 1;
        var td = pts[last].minus(pts[last - 1]), tl = Math.max(0.001, td.length());
        var dirIn = td.times(1 / tl);                  // incoming tangent at the return anchor
        var headH = 17 * arrowScale3d;
        return {
            segs: segs,
            headPos: pts[last].minus(dirIn.times(headH / 2)),   // tip reaches the anchor; points into the node
            headQuat: quatFromYTo(dirIn),
            labelPos: b.plus(out.times(reach + 16))
        };
    }

    // Yaw (deg) that turns a label to face the camera around Y (keeps it upright).
    function faceYaw(wx, wz) {
        return Math.atan2(camera.scenePosition.x - wx, camera.scenePosition.z - wz) * 180 / Math.PI;
    }
    // Distance from the camera to a world point, and the matching label scale so a
    // label keeps a constant on-screen size (font size then reads the same whether
    // the label is near or far — otherwise near labels saturate and barely respond).
    readonly property real labelRef: 760
    function camDist(wp) { return camera.scenePosition.minus(wp).length(); }
    function labelScale(wp) { var s = camDist(wp) / labelRef; return Qt.vector3d(s, s, s); }

    // --- movable 2D overlay panes (grip-drag + reset), like the 2D CanvasPanes ---
    property var panePos: ({})   // paneName -> {x,y}; empty => default (anchored) spot
    function paneX(name, def) { var p = panePos[name]; return (p && p.x !== undefined) ? p.x : def; }
    function paneY(name, def) { var p = panePos[name]; return (p && p.y !== undefined) ? p.y : def; }
    function resetPanes() { panePos = ({}); }
    // Drag handle shared by the overlay panes; moves `pane` and records its spot.
    property bool paneDragging: false   // true while a pane grip is held (disables orbit)
    component PaneGrip: MouseArea {
        property Item pane
        property string name
        implicitWidth: 16; implicitHeight: 20
        cursorShape: Qt.SizeAllCursor
        // Hold the grab so the orbit controller's DragHandler can't steal the drag.
        preventStealing: true
        property real ox: 0; property real oy: 0
        onPressed: function (m) {
            root.paneDragging = true;
            var g = mapToItem(root, m.x, m.y); ox = g.x - pane.x; oy = g.y - pane.y;
        }
        onPositionChanged: function (m) {
            if (!pressed) return;
            var g = mapToItem(root, m.x, m.y);
            var nx = Math.max(0, Math.min(root.width - pane.width, g.x - ox));
            var ny = Math.max(0, Math.min(root.height - pane.height, g.y - oy));
            var pp = {}; for (var k in root.panePos) pp[k] = root.panePos[k];
            pp[name] = { x: nx, y: ny }; root.panePos = pp;
        }
        onReleased: root.paneDragging = false
        Text { anchors.centerIn: parent; text: "⠿"; color: root.colMuted; font.pixelSize: 13 }
    }

    // Frame the whole diagram so the layout (cuboid) FILLS the visible scene: pivot
    // the orbit at the node centroid and back the camera off just enough that the
    // node bounding BOX fits both the vertical and horizontal FOV. Framing the box
    // (not the loose bounding sphere) means the cuboid fills the view instead of
    // sitting small inside a sphere's worth of empty space.
    function fit() {
        var ns = states, n = ns.length;
        var center = Qt.vector3d(0, 0, 0);
        if (n > 0) {
            for (var i = 0; i < n; i++) center = center.plus(posOf(ns[i]));
            center = center.times(1 / n);
        }
        var hx = nr, hy = nr, hz = nr;                  // box half-extents (+ node radius)
        for (var j = 0; j < n; j++) {
            var p = posOf(ns[j]).minus(center);
            hx = Math.max(hx, Math.abs(p.x) + nr);
            hy = Math.max(hy, Math.abs(p.y) + nr);
            hz = Math.max(hz, Math.abs(p.z) + nr);
        }
        var aDeg = 22, a = aDeg * Math.PI / 180;        // look down 22deg
        var fov = (camera.fieldOfView > 0 ? camera.fieldOfView : 60) * Math.PI / 180;
        var tanV = Math.tan(fov / 2);
        var aspect = (view.width > 0 && view.height > 0) ? view.width / view.height : 1.6;
        var lblHead = 34;                               // headroom for the billboarded labels
        // On-screen half-extents under the downward tilt: X maps to horizontal; Y and
        // (foreshortened) Z map to vertical.
        var vHalf = hy * Math.cos(a) + hz * Math.sin(a) + lblHead;
        var hHalf = hx + lblHead * 0.4;
        var dist = Math.max(vHalf / tanV, hHalf / (tanV * aspect)) * 1.12;
        dist = Math.max(dist, 60);
        originNode.position = center;                   // orbit pivots at the diagram centre
        camera.position = Qt.vector3d(0, dist * Math.sin(a), dist * Math.cos(a));  // local to originNode
        camera.eulerRotation = Qt.vector3d(-aDeg, 0, 0);
    }
    // Zoom by dollying the camera toward / away from the orbit pivot (f<1 zooms in,
    // f>1 zooms out). Mirrors the wheel zoom; clamped so it can't cross the pivot.
    function zoomBy3D(f) {
        var p = camera.position, len = p.length();
        if (len < 1e-3) return;
        var nl = Math.max(40, Math.min(200000, len * f));
        camera.position = p.times(nl / len);
    }
    Component.onCompleted: {
        computeLayout(); fit();
        if (ctl) visualCurrent = ctl.current;
    }
    onLayoutRChanged: fit()
    onCanvasFullChanged: fit()   // reframe when entering/leaving full screen

    // Emitted whenever persisted 3D state changes (node drags, pane moves, style,
    // colours, per-edge/per-state overrides). Main wires this to markModified() so
    // the close-confirm dialog knows the document diverged. Startup/restore noise is
    // filtered by markModified()'s _applying / _ready guard.
    signal changed()
    onPosOverrideChanged: changed()
    onPanePosChanged: changed()
    onNodeScaleChanged: changed()
    onEdgeScaleChanged: changed()
    onArrowScale3dChanged: changed()
    onShowAxes3dChanged: changed()
    onShowEdgeLabels3dChanged: changed()
    onEdge3dStyleChanged: changed()
    onCurvature3dChanged: changed()
    onTokenStyle3dChanged: changed()
    onTokenScale3dChanged: changed()
    onNodeLabelSizeChanged: changed()
    onEdgeLabelSizeChanged: changed()
    onLabelAlongChanged: changed()
    onNodeColorOverrideChanged: changed()
    onEdgeColorOverrideChanged: changed()
    onEdgeLabelColorOverrideChanged: changed()
    onShowGrid3dChanged: changed()
    onStateColorsChanged: changed()
    onEdgeColorsChanged: changed()
    onEdgeTailChanged: changed()
    onEdgeHeadChanged: changed()
    onEdgeCtrlChanged: changed()
    // Re-layout when the machine changes (states/transitions).
    Connections {
        target: root.ctl
        enabled: root.ctl !== null
        function onDefinitionChanged() { root.computeLayout(); root.fit(); }
    }

    // --- persistence: dragged node positions + camera, saved in the document ---
    // (importState3D runs after the definition rebuild in Main, so a restored
    // camera wins over the ring-change auto-fit.)
    function exportState3D() {
        var po = {};
        for (var k in posOverride) {
            var v = posOverride[k];
            po[k] = [v.x, v.y, v.z];
        }
        return {
            positions: po,
            camPos: [camera.position.x, camera.position.y, camera.position.z],
            camRot: [camera.eulerRotation.x, camera.eulerRotation.y, camera.eulerRotation.z],
            camOrigin: [originNode.position.x, originNode.position.y, originNode.position.z],
            nodeScale: nodeScale, edgeScale: edgeScale, arrowScale: arrowScale3d, edgeStyle: edge3dStyle, curvature: curvature3d,
            tokenStyle: tokenStyle3d, tokenScale: tokenScale3d,
            nodeColor: nodeColorOverride.a > 0 ? "" + nodeColorOverride : "",
            edgeColor: edgeColorOverride.a > 0 ? "" + edgeColorOverride : "",
            showGrid: showGrid3d, showAxes: showAxes3d, showEdgeLabels: showEdgeLabels3d,
            nodeLabelSize: nodeLabelSize, edgeLabelSize: edgeLabelSize, labelAlong: labelAlong,
            edgeLabelColor: edgeLabelColorOverride.a > 0 ? "" + edgeLabelColorOverride : "",
            stateColors: (function () { var m = {}; for (var k in stateColors) m[k] = stateColors[k]; return m; })(),
            edgeTail: (function () { var m = {}; for (var k in edgeTail) { var v = edgeTail[k]; m[k] = [v.x, v.y, v.z]; } return m; })(),
            edgeHead: (function () { var m = {}; for (var k in edgeHead) { var v = edgeHead[k]; m[k] = [v.x, v.y, v.z]; } return m; })(),
            edgeCtrl: (function () { var m = {}; for (var k in edgeCtrl) { var v = edgeCtrl[k]; m[k] = [v.x, v.y, v.z]; } return m; })(),
            edgeColors: (function () { var m = {}; for (var k in edgeColors) m[k] = edgeColors[k]; return m; })(),
            panePos: (function () { var m = {}; for (var k in panePos) m[k] = { x: panePos[k].x, y: panePos[k].y }; return m; })()
        };
    }
    function importState3D(s) {
        if (!s) return;
        if (s.showGrid !== undefined) showGrid3d = s.showGrid;
        if (s.showAxes !== undefined) showAxes3d = s.showAxes;
        if (s.showEdgeLabels !== undefined) showEdgeLabels3d = s.showEdgeLabels;
        if (s.nodeScale !== undefined) nodeScale = s.nodeScale;
        if (s.edgeScale !== undefined) edgeScale = s.edgeScale;
        if (s.arrowScale !== undefined) arrowScale3d = s.arrowScale;
        if (s.edgeStyle !== undefined) edge3dStyle = s.edgeStyle;
        if (s.curvature !== undefined) curvature3d = s.curvature;
        if (s.tokenStyle !== undefined) tokenStyle3d = s.tokenStyle;
        if (s.tokenScale !== undefined) tokenScale3d = s.tokenScale;
        if (s.nodeColor !== undefined) nodeColorOverride = s.nodeColor ? s.nodeColor : "transparent";
        if (s.edgeColor !== undefined) edgeColorOverride = s.edgeColor ? s.edgeColor : "transparent";
        if (s.nodeLabelSize !== undefined) nodeLabelSize = s.nodeLabelSize;
        if (s.edgeLabelSize !== undefined) edgeLabelSize = s.edgeLabelSize;
        if (s.labelAlong !== undefined) labelAlong = s.labelAlong;
        if (s.edgeLabelColor !== undefined) edgeLabelColorOverride = s.edgeLabelColor ? s.edgeLabelColor : "transparent";
        if (s.stateColors !== undefined) { var m = {}; for (var k in s.stateColors) m[k] = s.stateColors[k]; stateColors = m; }
        if (s.edgeTail !== undefined) { var et = {}; for (var k in s.edgeTail) { var a = s.edgeTail[k]; et[k] = Qt.vector3d(a[0], a[1], a[2]); } edgeTail = et; }
        if (s.edgeHead !== undefined) { var eh = {}; for (var k in s.edgeHead) { var a = s.edgeHead[k]; eh[k] = Qt.vector3d(a[0], a[1], a[2]); } edgeHead = eh; }
        if (s.edgeCtrl !== undefined) { var ec = {}; for (var k in s.edgeCtrl) { var a = s.edgeCtrl[k]; ec[k] = Qt.vector3d(a[0], a[1], a[2]); } edgeCtrl = ec; }
        if (s.edgeColors !== undefined) { var eco = {}; for (var k in s.edgeColors) eco[k] = s.edgeColors[k]; edgeColors = eco; }
        if (s.panePos !== undefined) { var pp = {}; for (var k in s.panePos) pp[k] = { x: s.panePos[k].x, y: s.panePos[k].y }; panePos = pp; }
        if (s.positions) {
            var m = {};
            for (var k in s.positions) {
                var a = s.positions[k];
                m[k] = Qt.vector3d(a[0], a[1], a[2]);
            }
            posOverride = m;
            computeLayout();   // relax the free nodes around the restored pins
        }
        if (s.camOrigin) originNode.position = Qt.vector3d(s.camOrigin[0], s.camOrigin[1], s.camOrigin[2]);
        if (s.camPos && s.camRot) {
            camera.position = Qt.vector3d(s.camPos[0], s.camPos[1], s.camPos[2]);
            camera.eulerRotation = Qt.vector3d(s.camRot[0], s.camRot[1], s.camRot[2]);
        }
    }

    // --- run animation (Phase 2): a token glides the firing edge on each step ---
    property real tokenT: 0
    property var tokenPath: []        // polyline the token glides along (follows curved edges)
    // Visually-current state lags ctl.current during a step so the highlight and the
    // Run-pane badge only update once the token has arrived (the animation has
    // completed), not when the step starts. Mirrors the 2D view. Accepting status is
    // derived from it (accepted ⇔ current state ∈ F), so it lags the same way.
    property string visualCurrent: ""
    readonly property bool visualAccepted: ctl && ctl.built && ctl.acceptStates.indexOf(visualCurrent) >= 0
    NumberAnimation {
        id: tokenAnim
        target: root; property: "tokenT"; from: 0; to: 1; easing.type: Easing.InOutQuad
        onFinished: if (root.ctl) root.visualCurrent = root.ctl.current   // hand off on arrival
    }
    Connections {
        target: root.ctl
        enabled: root.ctl !== null
        function onStepped() {
            root.visualCurrent = root.ctl.lastFrom;   // keep source lit while the token travels
            // Use the fired edge's key so the token follows the exact rendered path
            // (per-edge tail/head/curve overrides + the same bend), not a default.
            var key = root.ctl.lastFrom + "\u001f" + root.ctl.lastSymbol + "\u001f" + root.ctl.lastTo;
            root.tokenPath = root.edgePath(root.ctl.lastFrom, root.ctl.lastTo, key)
                             || [root.posOf(root.ctl.lastFrom), root.posOf(root.ctl.lastTo)];
            tokenAnim.duration = Math.max(150, Math.round((root.ctl.stepInterval || 700) * 0.85));
            tokenAnim.restart();
        }
        function onRunChanged() {
            // Outside a travelling step (build / reset / manual) track state directly.
            if (!tokenAnim.running) root.visualCurrent = root.ctl.current;
        }
    }

    View3D {
        id: view
        anchors.fill: parent
        environment: SceneEnvironment {
            clearColor: root.colBg
            backgroundMode: SceneEnvironment.Color
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.High
            // Floor grid for spatial orientation (must live under SceneEnvironment).
            InfiniteGrid { gridInterval: 50; visible: root.showGrid3d }
        }

        Node {
            id: originNode
            PerspectiveCamera { id: camera; clipFar: 100000 }
        }

        DirectionalLight { eulerRotation.x: -40; eulerRotation.y: -25 }
        DirectionalLight { eulerRotation.x: 15; eulerRotation.y: 160; brightness: 0.5 }

        // Pickable ground at y=0: a node drag ray hits this to read the new XZ.
        // Fully transparent (Blend, alpha 0) so it is NOT drawn and writes no
        // depth — otherwise it would occlude the lower half of nodes near y=0 —
        // while geometry-based picking still hits it.
        Model {
            source: "#Rectangle"
            objectName: "ground"
            pickable: true
            eulerRotation.x: -90                 // lay the XY rectangle flat into XZ
            scale: Qt.vector3d(120, 120, 1)      // 100u rectangle -> 12000u plane
            materials: PrincipledMaterial {
                baseColor: Qt.rgba(0, 0, 0, 0)
                alphaMode: PrincipledMaterial.Blend
                lighting: PrincipledMaterial.NoLighting
            }
        }

        // X/Y/Z reference axes through the origin (red/green/blue), with tip cones
        // and billboarded labels. A spatial reference for dragging / slider edits.
        Node {
            visible: root.showAxes3d
            Repeater3D {
                model: [ { d: Qt.vector3d(1, 0, 0), c: "#ef4444", t: "X" },
                         { d: Qt.vector3d(0, 1, 0), c: "#22c55e", t: "Y" },
                         { d: Qt.vector3d(0, 0, 1), c: "#3b82f6", t: "Z" } ]
                delegate: Node {
                    id: ax
                    required property var modelData
                    readonly property vector3d dir: modelData.d
                    Model {   // axis line (full length through the origin)
                        source: "#Cylinder"; rotation: root.quatFromYTo(ax.dir)
                        scale: Qt.vector3d(0.03, 2 * root.posRange / 100, 0.03)
                        materials: PrincipledMaterial { baseColor: ax.modelData.c; lighting: PrincipledMaterial.NoLighting }
                    }
                    Model {   // +end tip
                        source: "#Cone"; position: ax.dir.times(root.posRange); rotation: root.quatFromYTo(ax.dir)
                        scale: Qt.vector3d(0.09, 0.14, 0.09)
                        materials: PrincipledMaterial { baseColor: ax.modelData.c; lighting: PrincipledMaterial.NoLighting }
                    }
                    Node {    // axis label (billboarded, constant on-screen size)
                        id: axLbl
                        position: ax.dir.times(root.posRange + 24)
                        eulerRotation.y: root.faceYaw(axLbl.position.x, axLbl.position.z)
                        scale: root.labelScale(axLbl.position)
                        Text { text: ax.modelData.t; color: ax.modelData.c; font.pixelSize: 22; font.bold: true }
                    }
                }
            }
        }

        // --- edges: tube shaft + cone arrowhead + symbol label ---
        Repeater3D {
            model: root.ctl ? root.ctl.transitions : []
            delegate: Node {
                id: edge
                required property int index
                required property var modelData
                readonly property bool isSelf: modelData.from === modelData.to
                readonly property string key: root.edgeKey(modelData)
                readonly property bool sel: root.selectedEdge === edge.key
                // The most recently fired transition (matches 2D's amber highlight).
                readonly property bool hot: root.ctl && root.ctl.lastFrom === modelData.from
                                            && root.ctl.lastSymbol === modelData.symbol
                                            && root.ctl.lastTo === modelData.to
                readonly property color col: edge.hot ? root.colCurrent
                                           : (root.edgeColors[edge.key] !== undefined) ? root.edgeColors[edge.key]
                                           : edge.sel ? root.colToken : root.colEdgeEff
                readonly property var ev: (root.posRev, root.nodeScale, root.edge3dStyle, root.curvature3d,
                                           edge.isSelf ? null : root.edgeXform(modelData.from, modelData.to, edge.key))
                readonly property var loop: (root.posRev, root.nodeScale, edge.isSelf ? root.selfLoopGeom(modelData.from, index) : null)
                visible: ev !== null || loop !== null
                Repeater3D {   // edge shaft: 1 segment when straight, N when curved.
                    // Drive by segment COUNT (not the array) so moving a node only
                    // updates the existing Models' transforms instead of destroying and
                    // recreating them every frame — the latter froze the UI at scale.
                    model: edge.ev ? edge.ev.segs.length : 0
                    delegate: Model {
                        required property int index
                        readonly property var seg: edge.ev.segs[index]
                        source: "#Cylinder"
                        pickable: root.dragName === "" && root.edgeDrag === ""   // off during drags: cheaper picks
                        objectName: "edge:" + edge.key
                        position: seg.mid
                        rotation: seg.quat
                        scale: Qt.vector3d(0.06 * root.edgeScale, seg.len / 100, 0.06 * root.edgeScale)
                        materials: PrincipledMaterial { baseColor: edge.col; roughness: 0.7 }
                    }
                }
                Model {   // edge arrowhead
                    source: "#Cone"
                    visible: edge.ev !== null
                    pickable: root.dragName === "" && root.edgeDrag === ""   // off during drags: cheaper picks
                    objectName: "edge:" + edge.key
                    position: edge.ev ? edge.ev.headPos : Qt.vector3d(0, 0, 0)
                    rotation: edge.ev ? edge.ev.headQuat : Qt.quaternion(1, 0, 0, 0)
                    scale: Qt.vector3d(0.13 * root.edgeScale, 0.18 * root.arrowScale3d, 0.13 * root.edgeScale)
                    materials: PrincipledMaterial { baseColor: edge.col; roughness: 0.7 }
                }
                Repeater3D {   // self-loop ring — drive by count (see edge shaft note)
                    model: edge.loop ? edge.loop.segs.length : 0
                    delegate: Model {
                        required property int index
                        readonly property var seg: edge.loop.segs[index]
                        source: "#Cylinder"
                        pickable: root.dragName === "" && root.edgeDrag === ""   // off during drags: cheaper picks
                        objectName: "edge:" + edge.key
                        position: seg.mid
                        rotation: seg.quat
                        scale: Qt.vector3d(0.05 * root.edgeScale, seg.len / 100, 0.05 * root.edgeScale)
                        materials: PrincipledMaterial { baseColor: edge.col; roughness: 0.7 }
                    }
                }
                Model {   // self-loop arrowhead
                    source: "#Cone"
                    visible: edge.loop !== null
                    pickable: root.dragName === "" && root.edgeDrag === ""   // off during drags: cheaper picks
                    objectName: "edge:" + edge.key
                    position: edge.loop ? edge.loop.headPos : Qt.vector3d(0, 0, 0)
                    rotation: edge.loop ? edge.loop.headQuat : Qt.quaternion(1, 0, 0, 0)
                    scale: Qt.vector3d(0.12 * root.edgeScale, 0.17 * root.arrowScale3d, 0.12 * root.edgeScale)
                    materials: PrincipledMaterial { baseColor: edge.col; roughness: 0.7 }
                }
                Node {    // symbol label (billboarded) — straight or self-loop
                    visible: root.showEdgeLabels3d
                    readonly property vector3d lp: edge.ev ? root.samplePath(edge.ev.path, root.labelAlong).plus(Qt.vector3d(0, 12, 0))
                                                   : (edge.loop ? edge.loop.labelPos : Qt.vector3d(0, 0, 0))
                    position: lp
                    eulerRotation.y: root.faceYaw(lp.x, lp.z)
                    scale: root.labelScale(lp)   // constant on-screen size (near == far)
                    Text { text: edge.modelData.symbol; color: root.colLabelEff; font.pixelSize: root.edgeLabelSize }
                }
            }
        }

        // --- nodes: role-coloured sphere + name label (billboarded) ---
        Repeater3D {
            model: root.states
            delegate: Node {
                id: node
                required property int index
                required property string modelData
                position: (root.posRev, root.posOf(modelData))
                readonly property bool isCurrent: root.ctl && root.visualCurrent === modelData
                readonly property bool isSelected: root.selected === modelData
                property real pulse: 1.0
                onIsCurrentChanged: if (isCurrent) pulseAnim.restart()
                SequentialAnimation {
                    id: pulseAnim
                    NumberAnimation { target: node; property: "pulse"; from: 1.0; to: 1.5; duration: 160; easing.type: Easing.OutQuad }
                    NumberAnimation { target: node; property: "pulse"; to: 1.0; duration: 240; easing.type: Easing.InQuad }
                }
                Model {
                    source: "#Sphere"
                    // During a node drag, make ALL spheres non-pickable so the only
                    // pickable thing under the cursor is the ground plane — the drag
                    // ray hits it directly and the per-move pick stays cheap at scale.
                    // (Edge-handle drags keep spheres pickable: they read attach points.)
                    pickable: root.dragName === ""
                    objectName: "node:" + node.modelData
                    scale: Qt.vector3d(0.6 * root.nodeScale * node.pulse,
                                       0.6 * root.nodeScale * node.pulse,
                                       0.6 * root.nodeScale * node.pulse)
                    materials: PrincipledMaterial {
                        baseColor: node.isCurrent ? root.colCurrent
                                 : (root.stateColors[node.modelData] !== undefined) ? root.stateColors[node.modelData]
                                 : (root.ctl && root.ctl.initialState === node.modelData) ? root.colInitial
                                 : (root.ctl && root.ctl.acceptStates.indexOf(node.modelData) >= 0) ? root.colAccept
                                 : root.colNodeEff
                        emissiveFactor: node.isSelected ? Qt.vector3d(0.10, 0.40, 0.55)
                                      : node.isCurrent ? Qt.vector3d(0.45, 0.28, 0.0)
                                      : Qt.vector3d(0, 0, 0)
                        metalness: 0.1; roughness: 0.5
                    }
                }
                Node {   // name label (billboarded, constant on-screen size)
                    readonly property vector3d wp: node.position.plus(Qt.vector3d(0, root.nr + 26, 0))
                    y: root.nr + 26
                    eulerRotation.y: root.faceYaw(node.position.x, node.position.z)
                    scale: root.labelScale(wp)
                    Text { text: node.modelData; color: root.colLabel; font.pixelSize: root.nodeLabelSize; font.bold: true }
                }
            }
        }

        // Run token: glides the firing edge during a run; shape = tokenStyle3d.
        Node {
            id: tokenNode
            visible: root.ctl && (root.ctl.running || tokenAnim.running)
            position: root.samplePath(root.tokenPath, root.tokenT)   // ride the edge line
            rotation: root.quatFromYTo(root.sampleDir(root.tokenPath, root.tokenT))  // local +Y = travel dir
            scale: Qt.vector3d(root.tokenScale3d, root.tokenScale3d, root.tokenScale3d)  // Token-size slider
            Model {   // dot
                visible: root.tokenStyle3d === "dot"
                source: "#Sphere"; scale: Qt.vector3d(0.3, 0.3, 0.3)
                materials: PrincipledMaterial { baseColor: root.colToken; lighting: PrincipledMaterial.NoLighting }
            }
            Model {   // chevron — cone pointing along travel (+Y)
                visible: root.tokenStyle3d === "chevron"
                source: "#Cone"; scale: Qt.vector3d(0.32, 0.5, 0.32)
                materials: PrincipledMaterial { baseColor: root.colToken; lighting: PrincipledMaterial.NoLighting }
            }
            Model {   // comet — sphere stretched along travel
                visible: root.tokenStyle3d === "comet"
                source: "#Sphere"; scale: Qt.vector3d(0.24, 0.6, 0.24)
                materials: PrincipledMaterial { baseColor: root.colToken; lighting: PrincipledMaterial.NoLighting }
            }
            Repeater3D {   // ring — encircles the path (local XZ, perpendicular to travel)
                model: root.tokenStyle3d === "ring" ? root.tokenRingSegs : []
                delegate: Model {
                    required property var modelData
                    source: "#Cylinder"
                    position: modelData.mid; rotation: modelData.quat
                    scale: Qt.vector3d(0.05, modelData.len / 100, 0.05)
                    materials: PrincipledMaterial { baseColor: root.colToken; lighting: PrincipledMaterial.NoLighting }
                }
            }
        }

        // Edge-edit handles — only for the selected edge. tail (green), head (red),
        // curve (cyan). Pickable to grab; the drag then picks past them.
        Node {
            id: edgeHandles
            readonly property var g: (root.posRev, root.nodeScale, root.edge3dStyle, root.curvature3d,
                                      root.selectedEdge === "" ? null : root.selectedEdgeABC())
            visible: g !== null
            Model {
                source: "#Sphere"; objectName: "etail"; pickable: true
                position: edgeHandles.g ? edgeHandles.g.a : Qt.vector3d(0, 0, 0)
                scale: Qt.vector3d(0.17, 0.17, 0.17)
                materials: PrincipledMaterial { baseColor: "#22c55e"; lighting: PrincipledMaterial.NoLighting }
            }
            Model {
                source: "#Sphere"; objectName: "ehead"; pickable: true
                position: edgeHandles.g ? edgeHandles.g.b : Qt.vector3d(0, 0, 0)
                scale: Qt.vector3d(0.17, 0.17, 0.17)
                materials: PrincipledMaterial { baseColor: "#ef4444"; lighting: PrincipledMaterial.NoLighting }
            }
            Model {
                source: "#Sphere"; objectName: "ecurve"; pickable: true
                position: edgeHandles.g ? edgeHandles.g.ctrl : Qt.vector3d(0, 0, 0)
                scale: Qt.vector3d(0.17, 0.17, 0.17)
                materials: PrincipledMaterial { baseColor: "#67e8f9"; lighting: PrincipledMaterial.NoLighting }
            }
        }

        // Transparent camera-facing plane: while dragging the curve handle, the ray
        // hits this so the control point moves parallel to the screen.
        Model {
            id: curvePlane
            source: "#Rectangle"; objectName: "dragplane"
            visible: root.edgeDrag === "curve"
            pickable: root.edgeDrag === "curve"
            position: edgeHandles.g ? edgeHandles.g.ctrl : Qt.vector3d(0, 0, 0)
            rotation: root.quatFromZTo(camera.scenePosition.minus(curvePlane.position).normalized())
            scale: Qt.vector3d(120, 120, 1)
            materials: PrincipledMaterial {
                baseColor: Qt.rgba(0, 0, 0, 0)
                alphaMode: PrincipledMaterial.Blend
                lighting: PrincipledMaterial.NoLighting
            }
        }
    }

    OrbitCameraController {
        anchors.fill: view
        origin: originNode
        camera: camera
        // Disabled while dragging a node, an edge handle, or an overlay pane so its
        // DragHandler can't grab the gesture and turn the drag into a scene orbit.
        enabled: root.dragName === "" && root.edgeDrag === "" && !root.paneDragging
    }

    // Selection + node drag. Sits above the orbit controller: a press on a node
    // grabs (select, then drag on the ground plane); a press on empty space is
    // rejected so the orbit controller handles it (orbit); wheel still zooms.
    MouseArea {
        id: picker
        anchors.fill: view
        acceptedButtons: Qt.LeftButton
        // Hold the grab once we've grabbed (a node press) — stop the orbit
        // controller's DragHandler from stealing it mid-gesture. Harmless on an
        // empty-space press since we don't accept/grab that one.
        preventStealing: true
        // Find the nearest hit whose objectName starts with `prefix` (or exactly
        // equals it). pickAll is used — not pick — because the infinite ground
        // plane would otherwise be the nearest hit for any node sitting below
        // y=0, hiding it from selection.
        function hitNamed(mx, my, prefix, exact) {
            var hits = view.pickAll(mx, my);
            for (var i = 0; i < hits.length; i++) {
                var on = hits[i].objectHit ? hits[i].objectHit.objectName : "";
                if (exact ? (on === prefix) : (on.indexOf(prefix) === 0))
                    return hits[i];
            }
            return null;
        }
        // Best interactive hit under the cursor, by PRIORITY rather than raw depth:
        // an edit handle, else a node sphere, else an edge. Nodes beat edges so a
        // sphere stays selectable even when a transition tube/arrowhead passes in
        // front of it (which otherwise swallowed the click, especially in a dense
        // cuboid layout). Each category takes its own nearest hit.
        function firstInteractive(mx, my) {
            var hits = view.pickAll(mx, my);
            var handle = "", node = "", edge = "";
            for (var i = 0; i < hits.length; i++) {
                var on = hits[i].objectHit ? hits[i].objectHit.objectName : "";
                if (handle === "" && (on === "etail" || on === "ehead" || on === "ecurve")) handle = on;
                else if (node === "" && on.indexOf("node:") === 0) node = on;
                else if (edge === "" && on.indexOf("edge:") === 0) edge = on;
            }
            return handle !== "" ? handle : (node !== "" ? node : edge);
        }
        onPressed: function (mouse) {
            var on = firstInteractive(mouse.x, mouse.y);
            if (on === "etail" || on === "ehead" || on === "ecurve") {
                root.edgeDrag = on === "etail" ? "tail" : on === "ehead" ? "head" : "curve";
                mouse.accepted = true;               // grab: drag the handle
            } else if (on.indexOf("node:") === 0) {
                root.selected = on.substring(5); root.selectedEdge = "";
                root.dragName = root.selected;
                mouse.accepted = true;               // grab: drag the node
            } else if (on.indexOf("edge:") === 0) {
                root.selectedEdge = on.substring(5); root.selected = "";
                mouse.accepted = false;              // select only; a drag then orbits
            } else {
                root.selected = ""; root.selectedEdge = "";
                mouse.accepted = false;              // let the orbit controller orbit
            }
        }
        onPositionChanged: function (mouse) {
            if (root.edgeDrag !== "") {
                var k = root.selectedEdge; if (k === "") return;
                var parts = k.split("\u001f"), fromN = parts[0], toN = parts[2];
                if (root.edgeDrag === "curve") {
                    var hc = hitNamed(mouse.x, mouse.y, "dragplane", true);
                    if (hc) { root.edgeCtrl[k] = hc.scenePosition; root.posRev++; }
                } else {
                    var nm = root.edgeDrag === "tail" ? fromN : toN;
                    var hn = hitNamed(mouse.x, mouse.y, "node:" + nm, true);
                    if (hn) {
                        var dir = hn.scenePosition.minus(root.posOf(nm));
                        var Ld = dir.length(); if (Ld < 1e-3) return;
                        dir = dir.times(1 / Ld);
                        if (root.edgeDrag === "tail") root.edgeTail[k] = dir;
                        else root.edgeHead[k] = dir;
                        root.posRev++;
                    }
                }
                return;
            }
            if (root.dragName === "") return;
            var hit = hitNamed(mouse.x, mouse.y, "ground", true);
            if (hit) {
                var p = hit.scenePosition;
                var m = root.posOverride;
                m[root.dragName] = Qt.vector3d(p.x, 0, p.z);
                root.posOverride = m;
                root.posRev++;
            }
        }
        onReleased: { root.dragName = ""; root.edgeDrag = ""; }
    }

    // Pan: right-mouse drag slides the whole scene (moves the orbit pivot in the
    // camera's screen plane). Left-drag still orbits; the orbit controller only
    // grabs the left button, so the right button is free for panning here.
    MouseArea {
        id: panArea
        anchors.fill: view
        acceptedButtons: Qt.RightButton
        property real lastX: 0
        property real lastY: 0
        onPressed: function (mouse) { panArea.lastX = mouse.x; panArea.lastY = mouse.y; }
        onPositionChanged: function (mouse) {
            var dx = mouse.x - panArea.lastX, dy = mouse.y - panArea.lastY;
            panArea.lastX = mouse.x; panArea.lastY = mouse.y;
            var dist = camera.position.length();
            var fov = (camera.fieldOfView > 0 ? camera.fieldOfView : 60) * Math.PI / 180;
            var k = 2 * dist * Math.tan(fov / 2) / Math.max(1, view.height);   // world units per pixel at the pivot
            var mv = camera.right.times(-dx * k).plus(camera.up.times(dy * k));
            originNode.position = originNode.position.plus(mv);
        }
    }

    // Run controls — 3D mode has no 2D ControlPane, so Run/Stop/Reset live here
    // (plus the current-state / accepting readout and the word to run).
    Rectangle {
        id: runPane
        visible: root.ctl !== null
        x: root.paneX("run", (root.width - width) / 2)
        y: root.paneY("run", root.height - height - 34)   // bottom-centre (room for the trace below)
        radius: 8; color: root.colPaneBg; border.color: root.colPaneBorder; border.width: 1
        width: runRow.width + 16; height: 40
        Row {
            id: runRow; anchors.centerIn: parent; spacing: 8
            PaneGrip { pane: runPane; name: "run"; anchors.verticalCenter: parent.verticalCenter }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 150; elide: Text.ElideRight
                text: (root.ctl && root.ctl.built) ? ("Current: " + root.visualCurrent) : "Not built"
                color: (root.ctl && root.ctl.built) ? root.colCurrent : root.colMuted
                font.bold: true; font.pixelSize: 13
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                radius: 4; width: 96; height: 22; opacity: (root.ctl && root.ctl.built) ? 1 : 0
                color: root.visualAccepted ? "#14532d" : "#4c1d1d"
                Text {
                    anchors.centerIn: parent
                    text: root.visualAccepted ? "Accepting" : "Not Accepting"
                    color: root.visualAccepted ? "#86efac" : "#fca5a5"
                    font.pixelSize: 11; font.bold: true
                }
            }
            TextField {
                id: wordField3d
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 170
                placeholderText: "word, e.g. 1 0 1"
                text: root.runWord                       // shared with the 2D view
                onTextEdited: root.runWordEdited(text)
            }
            Button { text: "Run"; enabled: root.ctl && root.ctl.built && !root.ctl.running
                     onClicked: root.ctl.runWord(root.runWord) }
            Button { text: "Stop"; enabled: root.ctl && root.ctl.running; onClicked: root.ctl.stopRun() }
            Button { text: "Reset"; enabled: root.ctl && root.ctl.built; onClicked: root.ctl.reset() }
        }
    }
    Text {   // run trace (FIFO, oldest scrolls off the left) — directly under the run bar
        x: runPane.x + 8
        y: runPane.y + runPane.height + 6
        width: runPane.width - 16
        visible: root.ctl && root.ctl.built && root.ctl.path.length > 1
        text: "Trace: " + (root.ctl ? root.ctl.path.join("  →  ") : "")
        elide: Text.ElideLeft
        horizontalAlignment: Text.AlignLeft
        color: root.colLabel; font.pixelSize: 12; font.bold: true
    }
}
