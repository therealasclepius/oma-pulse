import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: popup
    Theme { id: theme }
    required property var store
    property string taskId: ""
    property string taskTitle: ""
    property string selectedWhen: ""
    property string message: ""
    property bool saved: false
    readonly property var reminders: store.todoist.reminderTaskId === taskId ? store.todoist.reminders : []
    width: Math.min(440, parent.width - 24)
    height: Math.min(468, parent.height - 20)
    x: (parent.width - width) / 2; y: (parent.height - height) / 2
    modal: true; focus: true; padding: 22
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { color: theme.surface; border.color: theme.border; radius: 0 }
    Overlay.modal: Rectangle { color: theme.alpha(theme.background, 0.8) }
    function showFor(task) {
        taskId = task.id; taskTitle = task.title; message = ""; selectedWhen = ""; saved = false;
        var next = new Date(Date.now() + 3600000);
        dateInput.text = Qt.formatDate(next, "yyyy-MM-dd"); timeInput.text = Qt.formatTime(next, "HH:mm");
        open(); store.todoist.loadReminders(taskId);
    }
    function choose(minutes, tomorrow) {
        var date = new Date();
        if (tomorrow) { date.setDate(date.getDate() + 1); date.setHours(9, 0, 0, 0); }
        else if (minutes === 0) date.setHours(18, 0, 0, 0);
        else date = new Date(Date.now() + minutes * 60000);
        if (date.getTime() <= Date.now()) { message = "This evening has passed. Choose another time."; return; }
        dateInput.text = Qt.formatDate(date, "yyyy-MM-dd"); timeInput.text = Qt.formatTime(date, "HH:mm");
        selectedWhen = date.toISOString(); message = ""; saved = false;
    }
    function customDate() {
        var raw = dateInput.text.trim() + "T" + timeInput.text.trim() + ":00";
        var date = new Date(raw);
        if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:00$/.test(raw) || !isFinite(date.getTime())
            || Qt.formatDateTime(date, "yyyy-MM-ddTHH:mm:ss") !== raw || date.getTime() <= Date.now()) return "";
        return date.toISOString();
    }
    function save() {
        if (store.todoist.busy) return;
        var when = selectedWhen || customDate();
        if (!when) { message = "Enter a future date (YYYY-MM-DD) and time (HH:MM)."; return; }
        selectedWhen = when; message = ""; saved = false;
        store.todoist.remind(taskId, when);
    }
    Connections {
        target: popup.store.todoist
        function onReminderCreated(taskId) {
            if (taskId === popup.taskId) { popup.saved = true; popup.message = "Saved in Todoist."; }
        }
    }
    component Copy: Text { color: theme.text; textFormat: Text.PlainText; font.pixelSize: 13; elide: Text.ElideRight }
    component Choice: Button {
        id: choice; implicitHeight: 32; focusPolicy: Qt.NoFocus
        background: Rectangle { color: choice.hovered ? theme.hover : theme.raised; radius: 3; opacity: choice.enabled ? 1 : 0.4 }
        contentItem: Copy { text: choice.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
    }
    component Field: TextField {
        color: theme.text; font.pixelSize: 14; padding: 9
        background: Rectangle { color: theme.background; border.color: parent.activeFocus ? theme.accent : theme.border; radius: 3 }
        onTextEdited: { popup.selectedWhen = ""; popup.saved = false; popup.message = ""; }
    }
    ColumnLayout {
        anchors.fill: parent; spacing: 12
        RowLayout {
            Copy { text: "Remind me"; font.pixelSize: 23; font.bold: true; Layout.fillWidth: true }
            Choice { text: "×"; implicitWidth: 32; onClicked: popup.close(); Accessible.name: "Close reminders" }
        }
        Copy { text: popup.taskTitle; Layout.fillWidth: true; maximumLineCount: 2; wrapMode: Text.Wrap; color: theme.muted }
        GridLayout {
            columns: 2; Layout.fillWidth: true; enabled: !popup.store.todoist.busy
            Choice { objectName: "reminder-30"; text: "In 30 minutes"; Layout.fillWidth: true; onClicked: popup.choose(30, false) }
            Choice { text: "In 1 hour"; Layout.fillWidth: true; onClicked: popup.choose(60, false) }
            Choice { text: "This evening · 6 PM"; Layout.fillWidth: true; enabled: new Date(popup.store.now).getHours() < 18; onClicked: popup.choose(0, false) }
            Choice { text: "Tomorrow · 9 AM"; Layout.fillWidth: true; onClicked: popup.choose(0, true) }
        }
        Copy { text: "Or choose a date and time · local time"; color: theme.muted; font.pixelSize: 12 }
        RowLayout {
            enabled: !popup.store.todoist.busy
            Field { id: dateInput; objectName: "reminder-date"; Layout.fillWidth: true; maximumLength: 10; placeholderText: "YYYY-MM-DD"; Accessible.name: "Reminder date" }
            Field { id: timeInput; objectName: "reminder-time"; implicitWidth: 88; maximumLength: 5; placeholderText: "HH:MM"; Accessible.name: "Reminder time"; onAccepted: popup.save() }
        }
        Copy {
            Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 3; font.pixelSize: 12
            text: popup.message || popup.store.todoist.error || "Delivered by Todoist push notifications."
            color: popup.saved ? theme.tasks : popup.message || popup.store.todoist.error ? theme.urgent : theme.muted
        }
        Choice { objectName: "reminder-save"; Layout.fillWidth: true; text: popup.store.todoist.busy ? "Working…" : popup.saved ? "Reminder saved" : "Set reminder"; enabled: !popup.store.todoist.busy && !popup.saved; onClicked: popup.save() }
        Copy { text: "Scheduled reminders"; font.bold: true }
        ListView {
            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 5
            model: popup.reminders
            delegate: Copy {
                required property var modelData
                width: ListView.view.width
                text: {
                    var due = modelData.due || {};
                    if (due.date) {
                        var date = new Date(due.date);
                        return isFinite(date.getTime()) ? Qt.formatDateTime(date, "ddd, d MMM · h:mm AP") : due.date;
                    }
                    return modelData.minute_offset !== undefined ? modelData.minute_offset + " min before due time" : due.string || "Scheduled in Todoist";
                }
                color: theme.accent; font.pixelSize: 12
            }
            Copy { visible: parent.count === 0; text: popup.store.todoist.busy ? "Loading…" : "No reminders loaded."; color: theme.muted; font.pixelSize: 12 }
            ScrollBar.vertical: ScrollBar {}
        }
    }
}
