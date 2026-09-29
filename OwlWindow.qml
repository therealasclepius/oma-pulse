pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

Item {
    id: win
    property var screen
    required property var store
    property bool expanded: false
    property bool dashboardOpen: false
    property bool commandOpen: false
    property string currentTab: "Workspace"
    property alias pinned: compactBoard.pinned
    readonly property bool hovered: compactBoard.hovered
    readonly property alias dashboard: dashboardWindow
    readonly property alias workspacePanel: compactBoard
    readonly property alias timerPopout: focusPopout
    readonly property alias commandPanel: commandWindow
    function open() { commandOpen = false; expanded = true; dashboardOpen = false; }
    function close() { store.flush(); expanded = false; compactBoard.pinned = false; }
    function openDashboard() { commandOpen = false; close(); dashboardOpen = true; }
    function openCommand() { close(); dashboardOpen = false; commandOpen = true; }
    CommandWindow {
        id: commandWindow; screen: win.screen; store: win.store; visible: win.commandOpen
        onDismissed: win.commandOpen = false
        onWorkspaceRequested: { win.pinned = true; win.open(); }
    }
    TimerPopout {
        id: focusPopout; screen: win.screen; store: win.store
        visible: win.store.focusState.running && !win.expanded && !win.dashboardOpen && !win.commandOpen
        onOpenRequested: { win.pinned = true; win.open(); }
    }
    Dashboard {
        id: compactBoard; compact: true; screen: win.screen; store: win.store; visible: win.expanded
        onDismissed: win.close()
        onExpandRequested: win.openDashboard()
    }
    Dashboard {
        id: dashboardWindow; screen: win.screen; store: win.store; visible: win.dashboardOpen
        onDismissed: { win.dashboardOpen = false; win.pinned = true; win.expanded = true; }
    }
}
