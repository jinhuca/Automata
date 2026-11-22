import QtQuick
import QtQuick.Shapes

// Entry/exit action glyph (vector, recolorable): a door-frame bracket opening
// left with an arrow going in (entry) or out (exit) — the classic log-in /
// log-out mark. Drawn as a Shape so it stays crisp and tints with `color`.
Shape {
    id: ag
    property bool isExit: false
    property color color: "#000000"
    property real sz: 13
    implicitWidth: sz; implicitHeight: sz
    preferredRendererType: Shape.CurveRenderer
    // Door frame "]" (top, right wall, bottom) — opening to the left.
    ShapePath {
        strokeColor: ag.color; strokeWidth: 1.6; fillColor: "transparent"
        capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
        startX: ag.sz * 0.56; startY: ag.sz * 0.16
        PathLine { x: ag.sz * 0.82; y: ag.sz * 0.16 }
        PathLine { x: ag.sz * 0.82; y: ag.sz * 0.84 }
        PathLine { x: ag.sz * 0.56; y: ag.sz * 0.84 }
    }
    // Arrow shaft — points into the frame for entry, out of it for exit.
    ShapePath {
        strokeColor: ag.color; strokeWidth: 1.6; fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        startX: ag.sz * (ag.isExit ? 0.52 : 0.08); startY: ag.sz * 0.5
        PathLine { x: ag.sz * (ag.isExit ? 0.14 : 0.52); y: ag.sz * 0.5 }
    }
    // Arrowhead chevron at the shaft tip.
    ShapePath {
        strokeColor: ag.color; strokeWidth: 1.6; fillColor: "transparent"
        capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
        startX: ag.sz * (ag.isExit ? 0.28 : 0.36); startY: ag.sz * 0.30
        PathLine { x: ag.sz * (ag.isExit ? 0.14 : 0.52); y: ag.sz * 0.5 }
        PathLine { x: ag.sz * (ag.isExit ? 0.28 : 0.36); y: ag.sz * 0.70 }
    }
}
