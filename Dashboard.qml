pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons

PanelWindow {
    id: dash
    Theme { id: theme }
    required property var store
    signal dismissed()
    signal expandRequested()
    property bool compact: false
    property bool pinned: false
    property bool accountOpen: false
    property bool awaitingEntry: false
    readonly property bool hovered: workspaceHover.hovered
    readonly property bool editing: taskInput.activeFocus || notes.activeFocus || tokenInput.activeFocus || minutesInput.activeFocus || remindersPopup.visible || (assistantOpen && assistantPane.editing)
    readonly property alias reminderPopup: remindersPopup
    readonly property real uiScale: compact ? 0.82 : 1
    property string taskView: "Today"
    property bool insights: false
    property bool assistantOpen: false
    onAssistantOpenChanged: if (assistantOpen) Qt.callLater(() => assistantPane.focusInput())
    property string calendarDate: store.calendarToday
    readonly property int calendarIndex: store.agendaDays.findIndex(d => d.date === dash.calendarDate)
    readonly property var calendarDay: store.agendaDays[Math.max(0, calendarIndex)] || null
    readonly property var taskRows: store.tasks.filter(t => !t.done && (!dash.store.useTodoist || dash.taskView === "All" || (!!t.due && t.due.slice(0,10) <= dash.store.today)))
    readonly property color textColor: theme.text
    anchors { top: true; bottom: !dash.compact; left: !dash.compact; right: !dash.compact }
    margins.top: compact ? Style.bar.sizeHorizontal + 5 : 0
    implicitWidth: compact ? Math.min(1560, screen.width - 32) : screen.width
    implicitHeight: compact ? Math.min(520, screen.height - 80) : screen.height
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: compact ? "omaowl-workspace" : "omaowl-dashboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? (compact ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive) : WlrKeyboardFocus.None
    color: "transparent"
    onVisibleChanged: if (visible) { awaitingEntry = compact; page.forceActiveFocus(); if (assistantOpen) Qt.callLater(() => assistantPane.focusInput()); if (store.useTodoist) store.todoist.refreshIfStale(); store.hey.refreshIfStale(); if (compact && !pinned) leaveTimer.restart(); } else { remindersPopup.close(); store.assistant.cancelVoice(); }
    onEditingChanged: if (!editing && !hovered) leaveTimer.restart()
    Timer { id: leaveTimer; interval: dash.awaitingEntry ? 1200 : 700; onTriggered: if (dash.compact && dash.visible && !dash.hovered && !dash.pinned && !dash.editing) dash.close() }
    Rectangle { anchors.fill: parent; color: theme.background; radius: 0; border.width: dash.compact ? 1 : 0; border.color: theme.border }
    function close() { store.flush(); dismissed(); }
    function moveDay(offset) {
        var index = Math.max(0, calendarIndex) + offset;
        if (index >= 0 && index < store.agendaDays.length) calendarDate = store.agendaDays[index].date;
    }
    function eventClock(ms) { return store.calendarClocks[String(ms)] || Qt.formatTime(new Date(ms), "h:mm AP"); }
    Connections {
        target: dash.store
        function onTaskAdded(title) { if (taskInput.text.trim() === title) taskInput.text = ""; }
    }

    component Label: Text {
        color: dash.textColor; font.family: theme.font; font.pixelSize: 16
        textFormat: Text.PlainText; elide: Text.ElideRight
    }
    component Action: AbstractButton {
        id: action
        property bool selected: false
        property bool dark: false
        implicitHeight: 38
        implicitWidth: Math.max(38, label.implicitWidth + 24)
        hoverEnabled: true; focusPolicy: Qt.NoFocus
        background: Rectangle { radius: 3; color: action.dark ? (action.selected ? theme.accent : action.hovered ? theme.border : theme.raised) : action.selected ? theme.accent : action.hovered ? theme.hover : theme.raised; opacity: action.enabled ? 1 : 0.4 }
        contentItem: Label { id: label; text: action.text; font.pixelSize: 14; font.weight: Font.Medium; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: action.dark ? (action.selected ? theme.background : theme.text) : action.selected ? theme.background : dash.textColor }
    }
    component Card: Rectangle {
        radius: 0
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.topMargin: 11; width: 32; height: 4; radius: 2; color: theme.alpha(theme.text, 0.18) }
    }
    component Entry: TextField {
        color: dash.textColor; font.family: theme.font; font.pixelSize: 16
        placeholderTextColor: theme.muted; padding: 12; implicitHeight: 48
        selectionColor: theme.accent; selectedTextColor: theme.background
        background: Rectangle { radius: 3; color: theme.raised; border.width: parent.activeFocus ? 1 : 0; border.color: theme.accent }
    }

    FocusScope {
        id: page; anchors.fill: parent; focus: true
        ReminderPopup { id: remindersPopup; store: dash.store }
        HoverHandler { id: workspaceHover; onHoveredChanged: { if (hovered) { dash.awaitingEntry = false; leaveTimer.stop(); } else leaveTimer.restart(); } }
        Keys.onEscapePressed: dash.close()
        ColumnLayout {
            anchors.centerIn: parent
            width: (dash.compact ? parent.width - 30 : Math.min(2100, parent.width - 80)) / dash.uiScale
            height: (dash.compact ? parent.height - 30 : Math.min(980, parent.height - 100)) / dash.uiScale
            scale: dash.uiScale
            spacing: 25
            RowLayout {
                Layout.fillWidth: true
                Image { Layout.preferredWidth: 46; Layout.preferredHeight: 46; source: Qt.resolvedUrl("assets/omapulse.svg"); fillMode: Image.PreserveAspectFit }
                ColumnLayout {
                    spacing: 3
                    Label { text: "Oma Pulse"; color: theme.text; font.pixelSize: 27; font.weight: Font.DemiBold }
                    Label { text: "A little room for your day."; color: theme.muted; font.pixelSize: 13 }
                }
                Item { Layout.fillWidth: true }
                Action { text: "Workspace"; dark: true; selected: !dash.insights && !dash.assistantOpen; onClicked: { dash.insights = false; dash.assistantOpen = false; } }
                Action { text: "Assistant"; dark: true; selected: dash.assistantOpen; onClicked: { dash.assistantOpen = true; dash.insights = false; } }
                Action { text: "Insights"; dark: true; selected: dash.insights && !dash.assistantOpen; onClicked: { dash.insights = true; dash.assistantOpen = false; } }
                Action { visible: dash.compact; text: dash.pinned ? "Pinned" : "Pin"; dark: true; selected: dash.pinned; onClicked: { dash.pinned = !dash.pinned; if (!dash.pinned && !dash.hovered) leaveTimer.restart(); } }
                Action { text: dash.compact ? "⤢  Full screen" : "↙  Compact"; dark: true; onClicked: dash.compact ? dash.expandRequested() : dash.close() }
                Action { text: "×"; dark: true; onClicked: dash.close(); Accessible.name: "Close full screen" }
            }
            RowLayout {
                visible: !dash.insights && !dash.assistantOpen
                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 18
                Card {
                    color: theme.tasks; Layout.fillHeight: true; Layout.fillWidth: true; Layout.preferredWidth: 420
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 24; anchors.topMargin: 35; spacing: 16
                        RowLayout {
                            Label { Layout.fillWidth: true; text: dash.taskView === "Today" ? "Today’s tasks" : "All tasks"; font.pixelSize: 22; font.weight: Font.DemiBold }
                            Label { text: Qt.formatDate(new Date(dash.store.now), "ddd, d MMM"); font.pixelSize: 12 }
                        }
                        RowLayout {
                            Action { text: "Today"; selected: dash.taskView === "Today"; onClicked: dash.taskView = "Today" }
                            Action { text: "All " + dash.store.remainingTasks; selected: dash.taskView === "All"; onClicked: dash.taskView = "All" }
                            Item { Layout.fillWidth: true }
                            Action { text: "↻"; enabled: dash.store.useTodoist && !dash.store.todoist.busy; onClicked: dash.store.todoist.refresh(); Accessible.name: "Refresh Todoist" }
                        }
                        RowLayout {
                            Action { text: dash.store.useTodoist ? "Todoist" : "Local"; onClicked: dash.store.setTaskSource(dash.store.useTodoist ? "local" : "todoist") }
                            Label { Layout.fillWidth: true; text: dash.store.todoist.busy ? "Syncing…" : dash.taskRows.length + " to do"; font.pixelSize: 12; opacity: 0.7 }
                            Action { text: "Account"; visible: dash.store.useTodoist; onClicked: dash.accountOpen = !dash.accountOpen }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: dash.store.useTodoist && (dash.accountOpen || (dash.store.todoist.loaded && !dash.store.todoist.connected))
                            Entry { id: tokenInput; Layout.fillWidth: true; placeholderText: "Todoist API key"; echoMode: TextInput.Password; maximumLength: 512; enabled: !dash.store.todoist.busy }
                            RowLayout {
                                Action { text: "Connect"; enabled: !dash.store.todoist.busy && tokenInput.text.trim().length > 0; onClicked: { dash.store.todoist.connectToken(tokenInput.text); tokenInput.text = ""; page.forceActiveFocus(); } }
                                Action { text: "Disconnect"; visible: dash.store.todoist.connected; enabled: !dash.store.todoist.busy; onClicked: dash.store.todoist.disconnect() }
                            }
                        }
                        Label { visible: !!dash.store.todoist.error && dash.store.useTodoist; text: dash.store.todoist.error; Layout.fillWidth: true; wrapMode: Text.Wrap; color: theme.urgent; font.pixelSize: 12 }
                        ListView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 6
                            model: dash.taskRows
                            ScrollBar.vertical: ScrollBar {}
                            delegate: Item {
                                id: taskRow
                                required property var modelData
                                width: ListView.view.width; height: Math.max(78, taskContent.implicitHeight + 16)
                                RowLayout {
                                    id: taskContent
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 10
                                    Action { text: "○"; implicitWidth: 34; enabled: !dash.store.useTodoist || !dash.store.todoist.busy; onClicked: dash.store.toggleTask(modelData.id); Accessible.name: "Complete task" }
                                    AbstractButton {
                                        id: taskLink
                                        objectName: "task-open"
                                        Layout.fillWidth: true
                                        implicitHeight: contentItem.implicitHeight
                                        enabled: dash.store.useTodoist
                                        hoverEnabled: true
                                        Accessible.name: "Open in Todoist: " + taskRow.modelData.title
                                        onClicked: dash.store.openTask(taskRow.modelData)
                                        HoverHandler { cursorShape: taskLink.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                        ToolTip.visible: hovered; ToolTip.text: "Open in Todoist"
                                        contentItem: ColumnLayout {
                                            spacing: 6
                                            Label { Layout.fillWidth: true; text: taskRow.modelData.title; font.pixelSize: 16; wrapMode: Text.Wrap; elide: Text.ElideNone; font.underline: taskLink.hovered }
                                            Label { Layout.fillWidth: true; text: [taskRow.modelData.due || "", taskRow.modelData.project ? "#" + taskRow.modelData.project : ""].filter(Boolean).join(" · "); font.pixelSize: 11; opacity: 0.6; visible: !!text }
                                        }
                                    }
                                    Action { text: "▶"; implicitWidth: 34; onClicked: dash.store.chooseFocus(modelData.title, 1500); Accessible.name: "Focus on task" }
                                    Action { objectName: "task-reminder"; text: "🔔"; implicitWidth: 30; visible: dash.store.useTodoist; enabled: dash.store.todoist.connected && !dash.store.todoist.busy; onClicked: remindersPopup.showFor(taskRow.modelData); Accessible.name: "Remind me"; ToolTip.visible: hovered; ToolTip.text: "Remind me" }
                                }
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: theme.alpha(theme.text, 0.14) }
                            }
                            Label { anchors.centerIn: parent; width: parent.width; visible: parent.count === 0; text: dash.store.todoist.connected || !dash.store.useTodoist ? "Some breathing room.\nNo tasks in this view." : "Connect Todoist in the compact view."; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; opacity: 0.65; lineHeight: 1.5 }
                        }
                        RowLayout {
                            enabled: !dash.store.useTodoist || (dash.store.todoist.connected && !dash.store.todoist.busy)
                            Entry { id: taskInput; Layout.fillWidth: true; maximumLength: 500; placeholderText: "+  Add a task"; onAccepted: dash.store.addTask(text) }
                            Action { text: "+"; onClicked: dash.store.addTask(taskInput.text) }
                        }
                    }
                }
                Card {
                    color: theme.focus; Layout.fillHeight: true; Layout.fillWidth: true; Layout.preferredWidth: 260
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 24; anchors.topMargin: 35; spacing: dash.compact ? 9 : 20
                        Label { text: "Focus"; font.pixelSize: 22; font.weight: Font.DemiBold }
                        Label { Layout.fillWidth: true; text: dash.store.focusState.title; wrapMode: Text.Wrap; maximumLineCount: 3; font.pixelSize: 17; opacity: 0.75 }
                        Item { Layout.fillHeight: true }
                        Label { Layout.fillWidth: true; text: dash.store.timerText; horizontalAlignment: Text.AlignHCenter; font.family: "monospace"; font.pixelSize: Math.min(57, parent.width / 5); font.letterSpacing: 1 }
                        Label { Layout.alignment: Qt.AlignHCenter; text: dash.store.focusState.running ? "One thing at a time." : "Ready when you are."; font.pixelSize: 12; opacity: 0.65 }
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            Action { objectName: "focus-toggle"; text: dash.store.focusState.running ? "Pause" : "Start"; selected: true; onClicked: dash.store.toggleTimer() }
                            Action { text: "+5"; enabled: dash.store.focusState.duration > 0; onClicked: dash.store.addFive() }
                        }
                        Item { Layout.fillHeight: true }
                        RowLayout {
                            Layout.fillWidth: true
                            Action { Layout.fillWidth: true; text: "25m"; enabled: !dash.store.focusState.running; onClicked: dash.store.chooseFocus(dash.store.focusState.title, 1500) }
                            Action { Layout.fillWidth: true; text: "50m"; enabled: !dash.store.focusState.running; onClicked: dash.store.chooseFocus(dash.store.focusState.title, 3000) }
                        }
                        Action { Layout.fillWidth: true; text: "Stopwatch"; enabled: !dash.store.focusState.running; onClicked: dash.store.chooseFocus(dash.store.focusState.title, 0) }
                        RowLayout {
                            Layout.fillWidth: true
                            Entry { id: minutesInput; Layout.fillWidth: true; implicitWidth: 65; implicitHeight: 38; placeholderText: "Minutes"; maximumLength: 3; validator: IntValidator { bottom: 1; top: 999 } }
                            Action { text: "Set"; enabled: !dash.store.focusState.running && minutesInput.acceptableInput; onClicked: { dash.store.chooseFocus(dash.store.focusState.title, Number(minutesInput.text) * 60); page.forceActiveFocus(); } }
                        }
                        Label { Layout.alignment: Qt.AlignHCenter; text: dash.store.todayMinutes + " minutes focused today"; font.pixelSize: 12; opacity: 0.65 }
                    }
                }
                Card {
                    color: theme.notes; Layout.fillHeight: true; Layout.fillWidth: true; Layout.preferredWidth: 330
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 24; anchors.topMargin: 35; spacing: 16
                        Label { text: "Notepad"; font.pixelSize: 22; font.weight: Font.DemiBold }
                        RowLayout {
                            Label { Layout.fillWidth: true; text: dash.store.noteDay; font.pixelSize: 13; opacity: 0.7 }
                            Action { text: "‹"; onClicked: { page.forceActiveFocus(); dash.store.moveNoteDay(-1); } }
                            Action { text: "Today"; onClicked: { page.forceActiveFocus(); dash.store.noteDay = dash.store.today; } }
                            Action { text: "›"; enabled: dash.store.noteDay < dash.store.today; onClicked: { page.forceActiveFocus(); dash.store.moveNoteDay(1); } }
                        }
                        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.alpha(theme.text, 0.18) }
                        ScrollView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                            TextArea {
                                id: notes; text: dash.store.note
                                onTextChanged: if (activeFocus) dash.store.setNote(text)
                                placeholderText: "Catch a thought.\nMake a little space."; placeholderTextColor: theme.muted
                                color: dash.textColor; wrapMode: TextEdit.Wrap; font.family: theme.font; font.pixelSize: 19
                                padding: 0; background: null; selectionColor: theme.accent; selectedTextColor: theme.background
                                Keys.onPressed: function(event) {
                                    if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                        var start = text.lastIndexOf("\n", cursorPosition - 1) + 1;
                                        var end = text.indexOf("\n", cursorPosition); if (end < 0) end = text.length;
                                        dash.store.addTask(text.slice(start,end)); event.accepted = true;
                                    }
                                }
                            }
                        }
                        Label { text: (notes.text.trim() ? notes.text.trim().split(/\s+/).length : 0) + " words · Saved locally"; font.pixelSize: 12; opacity: 0.65 }
                        Label { text: "Ctrl+Enter → task"; font.pixelSize: 11; opacity: 0.5 }
                    }
                }
                Card {
                    color: theme.events; Layout.fillHeight: true; Layout.fillWidth: true; Layout.preferredWidth: 350
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 24; anchors.topMargin: 35; spacing: 16
                        Label { text: "Events"; font.pixelSize: 22; font.weight: Font.DemiBold }
                        RowLayout {
                            Label { Layout.fillWidth: true; text: dash.calendarDay ? dash.calendarDay.label : "Calendar"; font.pixelSize: 13 }
                            Action { objectName: "dashboard-previous"; text: "‹"; enabled: dash.calendarIndex > 0; onClicked: dash.moveDay(-1) }
                            Action { objectName: "dashboard-next"; text: "›"; enabled: dash.calendarIndex < dash.store.agendaDays.length - 1; onClicked: dash.moveDay(1) }
                        }
                        Action { text: "Back to today"; visible: dash.calendarDate !== dash.store.calendarToday; onClicked: dash.calendarDate = dash.store.calendarToday }
                        ListView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 14
                            model: dash.calendarDay ? dash.calendarDay.events : []
                            ScrollBar.vertical: ScrollBar {}
                            delegate: AbstractButton {
                                id: eventLink
                                objectName: "event-open"
                                required property var modelData
                                width: ListView.view.width; height: 102; padding: 13
                                hoverEnabled: true
                                Accessible.name: "Open calendar: " + (modelData.title || "Untitled event")
                                onClicked: dash.store.openCalendar(dash.calendarDate)
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                ToolTip.visible: hovered; ToolTip.text: "Open full calendar"
                                background: Rectangle { radius: 3; color: eventLink.hovered ? theme.hover : theme.raised }
                                contentItem: ColumnLayout {
                                    spacing: 7
                                    Label { Layout.fillWidth: true; text: eventLink.modelData.title || "Untitled event"; font.weight: Font.Medium; font.pixelSize: 16; wrapMode: Text.Wrap; maximumLineCount: 2 }
                                    Label { Layout.fillWidth: true; text: eventLink.modelData.all_day ? "All day" : dash.eventClock(eventLink.modelData.start_ms) + " – " + dash.eventClock(eventLink.modelData.end_ms); font.pixelSize: 12; opacity: 0.7 }
                                    Label { Layout.fillWidth: true; text: eventLink.modelData.calendar || ""; font.pixelSize: 11; opacity: 0.55 }
                                }
                            }
                            Column {
                                anchors.centerIn: parent; width: parent.width; spacing: 12; visible: parent.count === 0
                                Label { width: parent.width; text: "Nothing scheduled"; font.pixelSize: 21; font.weight: Font.DemiBold; horizontalAlignment: Text.AlignHCenter }
                                Label { width: parent.width; text: dash.store.agendaDays.length ? "Pick another day with the arrows above." : "Connect your calendars in OmaCal to see events here."; font.pixelSize: 14; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; opacity: 0.65 }
                            }
                        }
                        Label { Layout.fillWidth: true; text: "OmaCal · " + dash.store.agendaDays.length + " days available"; font.pixelSize: 12; opacity: 0.65 }
                    }
                }
                Card {
                    color: theme.mail; Layout.fillHeight: true; Layout.fillWidth: true; Layout.preferredWidth: 340
                    HeyMail { anchors.fill: parent; anchors.margins: 24; anchors.topMargin: 35; store: dash.store }
                }
            }
            AssistantPane { id: assistantPane; visible: dash.assistantOpen; Layout.fillWidth: true; Layout.fillHeight: true; store: dash.store }
            Rectangle {
                visible: dash.insights && !dash.assistantOpen; Layout.fillWidth: true; Layout.fillHeight: true; color: theme.focus; radius: 0
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 48; spacing: 24
                    Label { text: "The work you put in"; font.pixelSize: 34; font.weight: Font.DemiBold }
                    Label { text: dash.store.todayMinutes + " minutes of focus today     ·     " + dash.store.todayCompleted + " tasks completed here today"; font.pixelSize: 21 }
                    RowLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 25
                        Repeater {
                            model: dash.store.week
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 15
                                Item { Layout.fillHeight: true }
                                Label { Layout.alignment: Qt.AlignHCenter; text: modelData.minutes + "m"; font.pixelSize: 23 }
                                Rectangle { Layout.fillWidth: true; implicitHeight: 10 + 250 * modelData.minutes / Math.max(1, ...dash.store.week.map(d => d.minutes)); radius: 12; color: theme.accent; opacity: modelData.minutes ? 0.8 : 0.15 }
                                Label { Layout.alignment: Qt.AlignHCenter; text: modelData.label; font.pixelSize: 17 }
                            }
                        }
                    }
                }
            }
            RowLayout {
                Label { Layout.fillWidth: true; text: dash.store.notice || "Your day, a little closer."; color: theme.muted; font.pixelSize: 13 }
                Label { text: dash.compact ? "Hover to open · Pin to keep open" : "Esc to return to the workspace"; color: theme.muted; font.pixelSize: 13 }
            }
        }
    }
}
