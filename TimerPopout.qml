import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
    id: popout
    Theme { id: theme }
    required property var store
    signal openRequested()
    anchors.top: true
    margins.top: Style.bar.sizeHorizontal + 5
    implicitWidth: 330
    implicitHeight: 60
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omaowl-timer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    Rectangle {
        anchors.fill: parent; color: theme.background; border.color: theme.border; radius: 0
        RowLayout {
            anchors.fill: parent; anchors.margins: 9; spacing: 8
            AbstractButton {
                objectName: "timer-open"; Layout.fillWidth: true; Layout.fillHeight: true
                onClicked: popout.openRequested()
                Accessible.name: "Open focus workspace"
                contentItem: RowLayout {
                    spacing: 12
                    Text { text: popout.store.timerText; color: theme.accent; font.family: "monospace"; font.pixelSize: 23 }
                    Text { text: popout.store.focusState.title; textFormat: Text.PlainText; Layout.fillWidth: true; color: theme.text; font.pixelSize: 12; elide: Text.ElideRight }
                }
            }
            Button {
                objectName: "timer-pause"; text: "Ⅱ"; implicitWidth: 34; implicitHeight: 34
                focusPolicy: Qt.NoFocus; onClicked: popout.store.toggleTimer()
                Accessible.name: "Pause focus timer"
                background: Rectangle { color: parent.hovered ? theme.hover : theme.raised; radius: 3 }
                contentItem: Text { text: parent.text; color: theme.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
        }
        Rectangle {
            anchors.left: parent.left; anchors.bottom: parent.bottom; height: 2; color: theme.accent
            width: parent.width * (popout.store.focusState.duration ? Math.min(1, popout.store.focusState.elapsed / popout.store.focusState.duration) : 1)
        }
    }
}
