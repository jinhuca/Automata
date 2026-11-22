pragma Singleton
import QtQuick

// App-wide light / dark palette. `dark` is the single input (driven by the
// window via a Binding in Main.qml); every colour derives from it, so the
// whole UI switches theme by flipping one property.
QtObject {
    property bool dark: false
    readonly property color windowBg:    dark ? "#0b1220" : "#f1f5f9"
    readonly property color panelBg:      dark ? "#111827" : "#ffffff"
    readonly property color panelBorder:  dark ? "#334155" : "#cbd5e1"
    readonly property color textPrimary:  dark ? "#e2e8f0" : "#0f172a"
    readonly property color textMuted:    dark ? "#94a3b8" : "#475569"
    readonly property color canvasBg:     dark ? "#0b1220" : "#ffffff"
    readonly property color nodeFill:     dark ? "#1e293b" : "#dbeafe"
    readonly property color nodeBorder:   dark ? "#3b82f6" : "#2563eb"
    readonly property color nodeText:     dark ? "#dbeafe" : "#1e3a8a"
    readonly property color edge:         dark ? "#94a3b8" : "#64748b"
    readonly property color labelBg:      dark ? "#ee1e293b" : "#f2ffffff"  // #AARRGGBB: opaque chip so labels read over edges
    readonly property color labelBorder:  dark ? "#334155" : "#e2e8f0"
    readonly property color labelText:    dark ? "#cbd5e1" : "#64748b"
    // Background-grid lines (minor every cell, major every 5), derived from the
    // panel border so they stay subtle in both themes.
    readonly property color gridMinor:    Qt.rgba(panelBorder.r, panelBorder.g, panelBorder.b, 0.22)
    readonly property color gridMajor:    Qt.rgba(panelBorder.r, panelBorder.g, panelBorder.b, 0.45)

    // Control palette (buttons, combo boxes, sliders, …) so Qt Quick Controls
    // follow the theme instead of the default system palette. Applied to the
    // window's `palette` in Main.qml, which propagates to every control.
    readonly property color button:       dark ? "#334155" : "#e2e8f0"
    readonly property color accent:       dark ? "#3b82f6" : "#2563eb"
}
