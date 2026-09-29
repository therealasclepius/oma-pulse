import QtQuick
import Quickshell
import Quickshell.Io
import "Intents.js" as Intents

Item {
    id: root
    required property var store
    property var messages: []
    property var actions: []
    property var actionStates: []
    property string error: ""
    property string mode: ""
    property var payload: ({})
    property int runningIndex: -1
    property bool received: false
    property bool recording: false
    property bool includeMail: true
    property var apps: []
    property var pendingActions: []
    readonly property bool busy: worker.running || pendingActions.length > 0
    signal transcribed(string text)
    signal actionFinished(string kind)
    function quickApps(query) {
        var q = String(query).trim().toLowerCase().replace(/^open\s+/, "");
        if (q.length < 2 || q.length > 50) return [];
        return apps.filter(a => a.name.toLowerCase().indexOf(q) >= 0 || a.id.toLowerCase().indexOf(q) >= 0).slice(0, 6);
    }
    function launchApp(app) {
        if (busy) return;
        actions = [{kind:"open_app",value:app.id,number:0,task_id:""}]; actionStates = ["Run"];
        execute(0);
    }
    function append(role, text) { messages = messages.concat([{role:role,text:String(text)}]).slice(-30); }
    function context() {
        return {today: store.today, focus: store.focusState, tasks: store.tasks.slice(0, 80),
            calendar_days: store.agendaDays, note: store.note.slice(0, 4000),
            mail_previews: includeMail ? store.newMail.slice(0, 15).map(m => ({sender:m.creator,subject:m.title,preview:m.excerpt,url:m.url})) : [],
            mail_included: includeMail, todoist_connected: store.todoist.connected};
    }
    function send(data) {
        if (worker.running) return false;
        mode = data.mode; payload = data; received = false; error = "";
        worker.stdinEnabled = true; worker.running = true;
        return true;
    }
    function ask(question) {
        question = String(question).trim();
        if (!question || busy || recording) return false;
        var history = messages.slice(-12);
        actions = []; actionStates = [];
        append("user", question);
        var local = Intents.parse(question, store.today);
        if (local) { actions = [local]; actionStates = ["Run"]; execute(0); return true; }
        return send({mode:"plan",question:question,context:context(),history:history});
    }
    function label(action) {
        switch(action.kind) {
        case "start_focus": return "Start " + action.number + " min focus · " + (action.value || "Open focus");
        case "pause_focus": return "Pause focus";
        case "resume_focus": return "Resume focus";
        case "add_task": return "Add Todoist task · " + action.value;
        case "complete_task": return "Complete task · " + taskTitle(action.task_id);
        case "remind_task": return "Remind me · " + taskTitle(action.task_id) + " · " + action.value;
        case "append_note": return "Add to today’s note · " + action.value;
        case "show_day": return "Show calendar · " + action.value;
        case "open_app": return "Open app · " + action.value;
        case "open_url": return "Open link · " + action.value;
        case "set_volume": return "Set volume · " + action.number + "%";
        case "search_files": return "Find files named · " + action.value;
        case "open_file": return "Open file · " + action.value;
        default: return "Unsupported action";
        }
    }
    function taskTitle(id) { var task = store.tasks.find(t => t.id === id); return task ? task.title : id; }
    function state(index, value) { var states = actionStates.slice(); states[index] = value; actionStates = states; }
    function execute(index) {
        if (worker.running || recording || index < 0 || index >= actions.length || actionStates[index] === "Done") return;
        var action = actions[index]; error = ""; runningIndex = index;
        try {
            switch(action.kind) {
            case "start_focus":
                if (!store.ready || store.error || action.number < 1 || action.number > 999) throw new Error("Focus is unavailable.");
                store.chooseFocus(action.value, action.number * 60); store.toggleTimer(); break;
            case "pause_focus": if (store.focusState.running) store.toggleTimer(); break;
            case "resume_focus": if (!store.focusState.running) store.toggleTimer(); break;
            case "append_note":
                if (!store.ready || store.error) throw new Error("Notepad is unavailable.");
                store.noteDay = store.today; store.setNote((store.note ? store.note + "\n" : "") + action.value); break;
            case "show_day":
                if (!store.agendaDays.some(d => d.date === action.value)) throw new Error("That day is outside the loaded calendar.");
                store.eachWindow(w => { w.workspacePanel.calendarDate = action.value; w.dashboard.calendarDate = action.value; w.workspacePanel.assistantOpen = false; w.workspacePanel.insights = false; w.pinned = true; w.open(); }); break;
            default:
                state(index, "Running…"); send({mode:"execute",action:action}); return;
            }
            state(index, "Done"); append("result", label(action) + " — done.");
            actionFinished(action.kind); queueTimer.restart();
        } catch(e) { pendingActions = []; state(index,"Retry"); error = String(e.message || e); }
    }
    function acceptPlan(result) {
        append("assistant", result.answer); actions = result.actions;
        actionStates = actions.map(a => "Run");
        pendingActions = result.auto_run === true ? actions.map((a, index) => index) : [];
        queueTimer.restart();
    }
    function runNext() {
        if (worker.running || recording || !pendingActions.length) return;
        var index = pendingActions[0]; pendingActions = pendingActions.slice(1);
        execute(index);
    }
    function voice() {
        if (!busy) send({mode:recording ? "voice_stop" : "voice_start"});
    }
    function cancelVoice() { if (recording && !busy) send({mode:"voice_cancel"}); }
    function cancel() { if (busy && mode === "plan") { pendingActions = []; worker.running = false; error = "Request cancelled."; } }
    function clear() { if (!busy && !recording) { messages = []; actions = []; actionStates = []; error = ""; } }
    Process {
        id: worker
        command: ["python3", Qt.resolvedUrl("assistant.py").toString().replace("file://", "")]
        onStarted: { write(JSON.stringify(root.payload) + "\n"); stdinEnabled = false; root.payload = ({}); }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text); root.received = true;
                    if (root.mode === "voice_stop" || root.mode === "voice_cancel") root.recording = false;
                    if (!result.ok) { root.pendingActions = []; root.error = result.error; if (root.mode === "execute") root.state(root.runningIndex,"Retry"); return; }
                    if (root.mode === "plan") {
                        root.acceptPlan(result);
                    } else if (root.mode === "execute") {
                        root.state(root.runningIndex,"Done"); root.append("result",result.result);
                        var action = root.actions[root.runningIndex];
                        if (["add_task","complete_task","remind_task"].indexOf(action.kind) >= 0) todoistRefresh.restart();
                        if (action.kind === "complete_task") root.store.todoist.taskClosed(action.task_id);
                        root.actionFinished(action.kind);
                    } else {
                        root.recording = result.recording === true;
                        if (result.transcript) root.transcribed(result.transcript);
                    }
                } catch(e) { root.pendingActions = []; if (root.mode === "execute") root.state(root.runningIndex,"Retry"); root.error = "Could not read the assistant response. Please retry."; }
            }
        }
        onExited: function(code) {
            root.payload = ({});
            if (!root.received) { root.pendingActions = []; if (root.mode === "execute") root.state(root.runningIndex,"Retry"); if (!root.error) root.error = "The assistant stopped. Please retry."; }
            queueTimer.restart();
        }
    }
    Timer { id: queueTimer; interval: 1; onTriggered: root.runNext() }
    Timer { id: todoistRefresh; interval: 200; onTriggered: root.store.todoist.refresh() }
    Process {
        id: catalog
        command: ["python3", Qt.resolvedUrl("assistant.py").toString().replace("file://", "")]
        stdinEnabled: true
        onStarted: { write('{"mode":"catalog"}\n'); stdinEnabled = false; }
        stdout: StdioCollector { onStreamFinished: { try { root.apps = JSON.parse(text).apps || []; } catch(e) {} } }
    }
    Component.onCompleted: catalog.running = true
}
