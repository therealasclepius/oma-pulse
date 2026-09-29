import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
    id: win
    required property var store
    signal dismissed()
    signal workspaceRequested()
    readonly property var assistant: store.assistant
    readonly property var matches: assistant.quickApps(input.text)
    property int selected: 0
    readonly property bool showConversation: assistant.messages.length > 0 || assistant.busy || !!assistant.error
    anchors.top: true
    margins.top: Style.bar.sizeHorizontal + 10
    implicitWidth: Math.min(800, screen.width - 40)
    implicitHeight: Math.min(screen.height - 100, showConversation ? 590 : matches.length ? 188 + matches.length * 48 : 250)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omaowl-command"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    Theme { id: theme }
    onVisibleChanged: {
        if (visible) { input.text = ""; selected = 0; Qt.callLater(() => input.forceActiveFocus()); }
        else assistant.cancelVoice();
    }
    function submit() {
        if (assistant.busy || assistant.recording) return;
        if (matches.length) { assistant.launchApp(matches[Math.min(selected,matches.length-1)]); dismissed(); }
        else if (assistant.ask(input.text)) {
            input.text = "";
        }
    }
    Connections {
        target: win.assistant
        function onTranscribed(text) { if (win.visible) { input.text = text; input.forceActiveFocus(); } }
        function onActionFinished(kind) { if (win.visible && kind === "start_focus" && win.assistant.actions.length === 1) win.dismissed(); }
    }
    component Copy: Text { color: theme.text; font.family: theme.font; textFormat: Text.PlainText; elide: Text.ElideRight; font.pixelSize: 13 }
    component Action: Button {
        id: button; implicitHeight: 32; focusPolicy: Qt.NoFocus
        background: Rectangle { color: button.hovered ? theme.hover : theme.raised; border.color: theme.border; radius: 2; opacity: button.enabled ? 1 : 0.4 }
        contentItem: Copy { text: button.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
    }
    Rectangle {
        anchors.fill: parent; color: theme.background; border.color: theme.accent; border.width: 1
        FocusScope {
            anchors.fill: parent; focus: true
            Keys.onEscapePressed: win.dismissed()
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 12
                RowLayout {
                    Copy { text: "◉  OmaOwl"; color: theme.accent; font.pixelSize: 17; font.bold: true }
                    Copy { text: "Command center"; color: theme.muted; Layout.fillWidth: true }
                    Action { text: "Workspace"; onClicked: win.workspaceRequested() }
                    Action { text: "×"; implicitWidth: 32; onClicked: win.dismissed(); Accessible.name: "Close command center" }
                }
                RowLayout {
                    TextField {
                        id: input; objectName: "command-input"; Layout.fillWidth: true; implicitHeight: 54
                        placeholderText: "Open an app, ask a question, get things done…"; maximumLength: 8000
                        color: theme.text; placeholderTextColor: theme.muted; font.family: theme.font; font.pixelSize: 18; padding: 13
                        background: Rectangle { color: theme.surface; border.color: theme.border }
                        onTextChanged: win.selected = 0
                        onAccepted: win.submit()
                        Keys.onDownPressed: win.selected = Math.min(win.matches.length-1, win.selected+1)
                        Keys.onUpPressed: win.selected = Math.max(0, win.selected-1)
                        Keys.onEscapePressed: win.dismissed()
                    }
                    Action { text: win.assistant.recording ? "■ Stop" : "● Voice"; implicitHeight: 54; enabled: !win.assistant.busy; onClicked: win.assistant.voice() }
                    Action { text: "↵"; implicitHeight: 54; implicitWidth: 42; enabled: !win.assistant.busy && !win.assistant.recording; onClicked: win.submit(); Accessible.name: "Submit request" }
                }
                ColumnLayout {
                    visible: win.matches.length > 0; Layout.fillWidth: true; spacing: 4
                    Repeater {
                        model: win.matches
                        AbstractButton {
                            id: appRow; required property var modelData; required property int index
                            Layout.fillWidth: true; implicitHeight: 42; hoverEnabled: true
                            background: Rectangle { color: win.selected === appRow.index || appRow.hovered ? theme.hover : theme.surface }
                            contentItem: Copy { text: "  " + appRow.modelData.name; verticalAlignment: Text.AlignVCenter; font.pixelSize: 15 }
                            onClicked: { win.assistant.launchApp(appRow.modelData); win.dismissed(); }
                        }
                    }
                }
                ScrollView {
                    id: conversation; visible: win.showConversation && !win.matches.length; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; contentWidth: availableWidth
                    ColumnLayout {
                        width: conversation.availableWidth; spacing: 14
                        Repeater {
                            model: win.assistant.messages.slice(-3)
                            ColumnLayout {
                                required property var modelData; Layout.fillWidth: true
                                Copy { text: modelData.role === "user" ? "You" : modelData.role === "result" ? "Result" : "OmaOwl"; color: theme.accent; font.bold: true; font.pixelSize: 11 }
                                TextEdit { text: parent.modelData.text; textFormat: parent.modelData.role === "assistant" ? TextEdit.MarkdownText : TextEdit.PlainText; onLinkActivated: function(link) { if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link); } readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; Layout.fillWidth: true; color: theme.text; font.family: theme.font; font.pixelSize: 14 }
                            }
                        }
                        Repeater {
                            model: win.assistant.actions
                            RowLayout {
                                id: planned; required property var modelData; required property int index; Layout.fillWidth: true
                                Copy { text: win.assistant.label(planned.modelData); Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 4 }
                                Action { text: win.assistant.actionStates[planned.index] || "Run"; enabled: !win.assistant.busy && text !== "Done"; onClicked: win.assistant.execute(planned.index) }
                            }
                        }
                    }
                }
                Copy {
                    visible: !win.showConversation && !win.matches.length; Layout.fillWidth: true; Layout.fillHeight: true; wrapMode: Text.Wrap
                    text: "Try “brief me on my day”, “start 25 minutes of focus”,\nor type an app name. ↑ ↓ to choose, Enter to open."; color: theme.muted; verticalAlignment: Text.AlignVCenter
                }
                Copy { visible: !!win.assistant.error; text: win.assistant.error; color: theme.urgent; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2 }
                RowLayout {
                    Copy { Layout.fillWidth: true; text: win.assistant.recording ? "Listening…" : win.assistant.busy ? (win.assistant.mode === "plan" ? "Thinking with Codex…" : "Working…") : "Super + N · Esc to close · Codex"; color: theme.muted; font.pixelSize: 11 }
                    Action { visible: win.assistant.busy && win.assistant.mode === "plan"; text: "Cancel"; onClicked: win.assistant.cancel() }
                    Action { visible: win.assistant.messages.length > 0 && !win.assistant.busy; text: "Clear"; onClicked: win.assistant.clear() }
                }
            }
        }
    }
}
