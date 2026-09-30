import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property bool connected: false
    property bool loaded: false
    property var tasks: []
    property var reminders: []
    property string reminderTaskId: ""
    property string error: ""
    property double lastSync: 0
    property string action: ""
    property string submittedTitle: ""
    property var payload: ({})
    property bool received: false
    readonly property bool busy: worker.running
    signal taskCreated(string title)
    signal taskClosed(string taskId)
    signal reminderCreated(string taskId)
    function send(request) {
        if (busy) return false;
        action = request.action; submittedTitle = request.title || "";
        payload = request; error = ""; received = false;
        worker.stdinEnabled = true; worker.running = true;
        return true;
    }
    function refresh() { return send({action: "sync"}); }
    function refreshIfStale() { if (!busy && Date.now() - lastSync > 60000) refresh(); }
    function connectToken(token) { return send({action: "connect", token: token}); }
    function disconnect() { return send({action: "disconnect"}); }
    function add(title) { return send({action: "add", title: title}); }
    function complete(taskId) { return send({action: "close", id: taskId}); }
    function loadReminders(taskId) {
        if (busy) return false;
        reminders = []; reminderTaskId = taskId;
        return send({action: "reminders", id: taskId});
    }
    function remind(taskId, when) { return send({action: "remind", id: taskId, when: when}); }
    Process {
        id: worker
        command: ["timeout", "90s", "python3", Qt.resolvedUrl("todoist.py").toString().replace("file://", "")]
        onStarted: { write(JSON.stringify(root.payload) + "\n"); stdinEnabled = false; root.payload = ({}); }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var response = JSON.parse(text);
                    root.received = true; root.loaded = true;
                    root.connected = response.connected === true;
                    if (!response.ok) { root.error = response.error; return; }
                    if (Array.isArray(response.tasks)) { root.tasks = response.tasks; root.lastSync = Date.now(); }
                    if (Array.isArray(response.reminders)) { root.reminders = response.reminders; root.reminderTaskId = response.reminderTaskId; }
                    if (response.reminder) {
                        root.reminders = root.reminders.filter(r => r.id !== response.reminder.id).concat([response.reminder]);
                        root.reminderTaskId = response.reminderTaskId;
                        root.reminderCreated(response.reminderTaskId);
                    }
                    if (!root.connected) { root.reminders = []; root.reminderTaskId = ""; }
                    if (response.created) { root.taskCreated(root.submittedTitle); refreshSoon.restart(); }
                    if (response.closed) {
                        root.tasks = root.tasks.filter(t => t.id !== response.closed);
                        root.taskClosed(response.closed); refreshSoon.restart();
                    }
                } catch (e) { root.error = "Could not read Todoist’s response. Try refreshing."; }
            }
        }
        onExited: function(code) {
            root.payload = ({});
            if (code === 124) root.error = "Todoist timed out. Refresh and try again.";
            else if (code !== 0 || !root.received) root.error = "Todoist connection stopped. Try refreshing.";
        }
    }
    Timer { id: refreshSoon; interval: 150; onTriggered: root.refresh() }
    Timer { interval: 120000; repeat: true; running: true; onTriggered: if (root.connected) root.refresh() }
    Component.onCompleted: refresh()
}
