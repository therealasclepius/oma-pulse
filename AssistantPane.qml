import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: pane
    required property var store
    readonly property var assistant: store.assistant
    readonly property bool editing: input.activeFocus || assistant.busy || assistant.recording
    color: theme.surface; border.color: theme.border; radius: 0
    Theme { id: theme }
    function focusInput() { input.forceActiveFocus(); }
    function submit() { if (assistant.ask(input.text)) input.text = ""; }
    Connections { target: pane.assistant; function onTranscribed(text) { input.text = text; input.forceActiveFocus(); } }
    component Copy: Text { color: theme.text; font.family: theme.font; textFormat: Text.PlainText; font.pixelSize: 14; elide: Text.ElideRight }
    component Action: Button {
        id: button; implicitHeight: 34; focusPolicy: Qt.NoFocus
        background: Rectangle { color: button.hovered ? theme.hover : theme.raised; border.color: theme.border; radius: 3; opacity: button.enabled ? 1 : 0.4 }
        contentItem: Copy { text: button.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.pixelSize: 12 }
    }
    ColumnLayout {
        anchors.fill: parent; anchors.margins: 22; spacing: 10
        RowLayout {
            Copy { text: "Your desktop, in a conversation"; font.pixelSize: 20; Layout.fillWidth: true }
            Action { text: "Clear"; enabled: !pane.assistant.busy && !pane.assistant.recording; onClicked: pane.assistant.clear() }
        }
        RowLayout {
            Copy { Layout.fillWidth: true; text: "Codex · Tasks, calendar, notes & desktop controls"; color: theme.muted; font.pixelSize: 12 }
            CheckBox { text: "Include mail previews"; checked: pane.assistant.includeMail; onToggled: pane.assistant.includeMail = checked; palette.windowText: theme.text; palette.text: theme.text; palette.highlight: theme.accent; font.pixelSize: 12 }
        }
        ScrollView {
            id: scroll; Layout.fillWidth: true; Layout.fillHeight: true; clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: scroll.availableWidth; spacing: 12
                Copy { visible: pane.assistant.messages.length === 0; Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Ask about your day, find a file, open an app, or tell me what you want to get done."; color: theme.muted; font.pixelSize: 17 }
                Flow {
                    visible: pane.assistant.messages.length === 0; Layout.fillWidth: true; spacing: 8
                    Repeater { model: ["Brief me on my day", "Start 25 minutes of focus", "What’s New for You in HEY?", "Open my browser"]
                        Action { required property string modelData; text: modelData; onClicked: { input.text = modelData; input.forceActiveFocus(); } }
                    }
                }
                Repeater {
                    model: pane.assistant.messages
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true; spacing: 5
                        Copy { text: modelData.role === "user" ? "You" : modelData.role === "result" ? "Result" : "Oma Pulse"; color: theme.accent; font.bold: true; font.pixelSize: 11 }
                        TextEdit { text: parent.modelData.text; textFormat: parent.modelData.role === "assistant" ? TextEdit.MarkdownText : TextEdit.PlainText; onLinkActivated: function(link) { if (/^https?:\/\//i.test(link)) Qt.openUrlExternally(link); } readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap; Layout.fillWidth: true; color: theme.text; font.family: theme.font; font.pixelSize: 14; selectionColor: theme.accent; selectedTextColor: theme.background }
                    }
                }
                Repeater {
                    model: pane.assistant.actions
                    Rectangle {
                        id: actionCard
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true; implicitHeight: Math.max(54, actionLabel.implicitHeight + 20)
                        color: theme.raised; border.color: theme.border
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 10
                            Copy { id: actionLabel; Layout.fillWidth: true; text: pane.assistant.label(actionCard.modelData); wrapMode: Text.Wrap; maximumLineCount: 4 }
                            Action { text: pane.assistant.actionStates[actionCard.index] || "Run"; enabled: !pane.assistant.busy && !pane.assistant.recording && text !== "Done"; onClicked: pane.assistant.execute(actionCard.index) }
                        }
                    }
                }
            }
        }
        Copy { visible: !!pane.assistant.error; text: pane.assistant.error; color: theme.urgent; Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 3 }
        Copy { visible: pane.assistant.busy || pane.assistant.recording; text: pane.assistant.recording ? "Listening… Click Stop when you’re finished." : pane.assistant.mode === "plan" ? "Thinking with Codex…" : "Working…"; color: theme.accent; Layout.fillWidth: true; font.pixelSize: 12 }
        RowLayout {
            TextField {
                id: input; objectName: "assistant-input"; Layout.fillWidth: true; implicitHeight: 44
                placeholderText: "Ask Oma Pulse…"; maximumLength: 8000; color: theme.text; placeholderTextColor: theme.muted
                font.family: theme.font; font.pixelSize: 15; padding: 12; onAccepted: pane.submit()
                background: Rectangle { color: theme.background; border.color: input.activeFocus ? theme.accent : theme.border; radius: 3 }
            }
            Action { text: pane.assistant.recording ? "■ Stop" : "● Voice"; enabled: !pane.assistant.busy; onClicked: pane.assistant.voice(); Accessible.name: "Voice request" }
            Action { text: pane.assistant.busy && pane.assistant.mode === "plan" ? "Cancel" : "Ask"; enabled: !pane.assistant.recording && (!pane.assistant.busy || pane.assistant.mode === "plan"); onClicked: pane.assistant.busy ? pane.assistant.cancel() : pane.submit() }
        }
        Copy { text: "Direct requests run automatically. Ask for a preview to review first. Voice fills the input. Conversation stays in this session."; color: theme.muted; font.pixelSize: 10; Layout.fillWidth: true; wrapMode: Text.Wrap }
    }
}
