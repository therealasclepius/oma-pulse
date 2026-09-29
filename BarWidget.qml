pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "kosta.omaowl"
    readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor(moduleName) : null
    readonly property string screenName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""
    readonly property var panel: service ? service.windowForScreen(screenName) : null
    readonly property bool opened: panel ? panel.expanded || panel.dashboardOpen || panel.commandOpen : false
    function open() { if (panel) { panel.pinned = true; panel.open(); } }
    function close() { if (panel) { panel.commandOpen = false; panel.dashboardOpen = false; panel.close(); } }
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "◉"
        active: root.opened || (root.service && root.service.focusState.running)
        interactive: root.panel !== null
        tooltipText: root.service && root.service.focusState.running ? "OmaOwl · " + root.service.timerText : "OmaOwl · Tasks, focus, notes and calendar"
        onTooltipHoveredChanged: {
            if (tooltipHovered && !root.opened) hoverTimer.restart();
            else hoverTimer.stop();
        }
        onPressed: function(mouseButton) {
            hoverTimer.stop();
            if (!root.panel) return;
            if (mouseButton === Qt.RightButton) root.panel.openDashboard();
            else if (mouseButton === Qt.LeftButton) {
                if (root.opened && root.panel.pinned) root.close();
                else root.open();
            }
        }
    }
    Timer {
        id: hoverTimer; interval: 240
        onTriggered: if (root.panel && button.tooltipHovered && !root.opened) { button.hideOwnTooltip(); root.panel.open(); }
    }
    onOpenedChanged: if (opened) button.hideOwnTooltip()
}
