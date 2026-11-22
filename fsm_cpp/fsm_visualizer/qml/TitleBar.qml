pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Single integrated title bar for the frameless window: app title, the
// light/dark toggle, and the minimise / maximise / close buttons. The window
// owns the behaviour and wires it through the signals below.
Rectangle {
    id: bar
    height: 42
    color: "#1e293b"

    property string title: ""
    property bool dark: false
    property bool maximized: false
    property bool use3D: false

    signal moveRequested()
    signal maximizeToggled()
    signal minimizeRequested()
    signal closeRequested()
    signal themeToggled(bool checked)
    signal view3DToggled(bool checked)

    // Drag anywhere on the bar to move; double-click to maximise/restore.
    MouseArea {
        anchors.fill: parent
        onPressed: bar.moveRequested()
        onDoubleClicked: bar.maximizeToggled()
    }

    component WinBtn: ToolButton {
        implicitWidth: 46; implicitHeight: 38
        property color hoverColor: "#334155"
        contentItem: Text {
            text: parent.text; color: "white"; font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle { color: parent.hovered ? parent.hoverColor : "transparent" }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        spacing: 8
        Label { text: bar.title; color: "white"; font.pixelSize: 18; font.bold: true }
        Item { Layout.fillWidth: true }
        Switch {
            id: view3dSwitch
            checked: bar.use3D
            onToggled: bar.view3DToggled(checked)
            indicator: Rectangle {
                implicitWidth: 44; implicitHeight: 26; radius: height / 2
                x: view3dSwitch.leftPadding
                y: view3dSwitch.height / 2 - height / 2
                color: view3dSwitch.checked ? "#0a84ff" : "#e5e7eb"
                border.color: view3dSwitch.checked ? "#0a84ff" : "#d1d5db"
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }
                Rectangle {
                    width: 22; height: 22; radius: height / 2; color: "white"
                    anchors.verticalCenter: parent.verticalCenter
                    x: view3dSwitch.checked ? parent.width - width - 2 : 2
                    border.color: "#00000022"; border.width: 1
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
            }
            contentItem: Text {
                text: bar.use3D ? "3D view" : "2D view"
                color: "#e2e8f0"; font.pixelSize: 13; font.bold: true
                leftPadding: view3dSwitch.indicator.width + 10
                verticalAlignment: Text.AlignVCenter
            }
        }
        Item { Layout.preferredWidth: 12 }
        Switch {
            id: themeSwitch
            checked: bar.dark
            onToggled: bar.themeToggled(checked)
            indicator: Rectangle {   // iOS-style pill: blue when on, light grey when off
                implicitWidth: 44; implicitHeight: 26; radius: height / 2
                x: themeSwitch.leftPadding
                y: themeSwitch.height / 2 - height / 2
                color: themeSwitch.checked ? "#0a84ff" : "#e5e7eb"
                border.color: themeSwitch.checked ? "#0a84ff" : "#d1d5db"
                border.width: 1
                Behavior on color { ColorAnimation { duration: 120 } }
                Rectangle {   // white sliding knob
                    width: 22; height: 22; radius: height / 2; color: "white"
                    anchors.verticalCenter: parent.verticalCenter
                    x: themeSwitch.checked ? parent.width - width - 2 : 2
                    border.color: "#00000022"; border.width: 1
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
            }
            contentItem: Text {
                text: bar.dark ? "Dark" : "Light"
                color: "#e2e8f0"; font.pixelSize: 13; font.bold: true
                leftPadding: themeSwitch.indicator.width + 10
                verticalAlignment: Text.AlignVCenter
            }
        }
        Item { Layout.preferredWidth: 12 }
        WinBtn { text: "—"; onClicked: bar.minimizeRequested() }
        WinBtn { text: bar.maximized ? "❐" : "☐"; onClicked: bar.maximizeToggled() }
        WinBtn { text: "✕"; hoverColor: "#e81123"; onClicked: bar.closeRequested() }
    }
}
