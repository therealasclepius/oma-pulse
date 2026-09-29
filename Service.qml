pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "Logic.js" as Logic

Item {
    id: root
    property var shell
    property var manifest
    property string omarchyPath
    property var pluginRegistry
    property var workspace: Logic.fresh()
    property int revision: 0
    property int taskRevision: 0
    property bool ready: false
    property bool storagePrepared: false
    property string error: ""
    property string notice: ""
    property double now: Date.now()
    property double previousTick: Date.now()
    property string today: Logic.dayKey(now)
    property string noteDay: today
    property var agenda: []
    property var agendaDays: []
    property string calendarToday: today
    property var calendarClocks: ({})
    property string calendarTimezone: ""
    property double agendaUpdated: 0
    readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/omaowl"
    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state"
    readonly property string taskSource: workspace.taskSource || (todoistController.connected ? "todoist" : "local")
    readonly property bool useTodoist: taskSource === "todoist"
    readonly property alias todoist: todoistController
    property bool mailEnabled: true
    readonly property alias hey: mailController
    readonly property var newMail: hey ? hey.notifications.filter(m => m.unread) : []
    HeyStore { id: mailController; active: root.mailEnabled }
    readonly property alias assistant: assistantController
    Assistant { id: assistantController; store: root }
    readonly property var localTasks: { taskRevision; return workspace.tasks.map(t => Object.assign({}, t)); }
    readonly property var tasks: useTodoist ? todoistController.tasks : localTasks
    readonly property var focusState: { revision; return Object.assign({}, workspace.focus); }
    readonly property string note: { revision; return workspace.notes[noteDay] || ""; }
    readonly property int remainingTasks: tasks.filter(t => !t.done).length
    readonly property string timerText: { revision; return Logic.clock(workspace.focus.duration ? workspace.focus.duration - workspace.focus.elapsed : workspace.focus.elapsed); }
    readonly property int todayMinutes: { revision; return Math.floor((workspace.activity[today] || 0) / 60); }
    readonly property int todayCompleted: { revision; return workspace.tasks.filter(t => t.done && Logic.dayKey(t.completedAt) === today).length + (workspace.todoistCompleted || []).filter(t => Logic.dayKey(t.at) === today).length; }
    readonly property var week: {
        revision;
        var rows = [];
        for (var i = 6; i >= 0; i--) {
            var d = new Date(now); d.setDate(d.getDate() - i);
            var key = Logic.dayKey(d.getTime());
            rows.push({label: Qt.formatDate(d, "ddd"), minutes: Math.floor((workspace.activity[key] || 0) / 60)});
        }
        return rows;
    }
    function changed(save, tasksChanged) { revision++; if (tasksChanged) taskRevision++; if (save !== false && ready) saveTimer.restart(); }
    function flush() {
        if (ready && !error) storage.setText(JSON.stringify(workspace, null, 2) + "\n");
    }
    signal taskAdded(string title)
    Todoist {
        id: todoistController
        onTaskCreated: function(title) { root.notice = "Added to Todoist."; root.taskAdded(title); }
        onReminderCreated: root.notice = "Reminder saved in Todoist."
        onTaskClosed: function(taskId) {
            if (!root.ready) return;
            if (!root.workspace.todoistCompleted) root.workspace.todoistCompleted = [];
            root.workspace.todoistCompleted.push({id: taskId, at: Date.now()});
            root.changed(); root.notice = "Completed in Todoist.";
        }
    }
    function setTaskSource(source) {
        if (!ready || ["local", "todoist"].indexOf(source) < 0) return;
        workspace = Object.assign({}, workspace, {taskSource: source}); changed();
    }
    function addTask(title) {
        title = String(title).trim().slice(0, 500);
        if (!ready || error || !title) return;
        if (useTodoist) { if (todoistController.connected) todoistController.add(title); return; }
        workspace.tasks.unshift({id: Date.now().toString(36) + Math.random().toString(36).slice(2, 8), title: title, done: false, completedAt: 0});
        changed(true, true);
        taskAdded(title);
    }
    function dismissWorkspace() {
        eachWindow(w => { w.commandOpen = false; w.dashboardOpen = false; w.close(); });
    }
    function openTask(task) {
        if (!useTodoist || !task || !task.id) return;
        Quickshell.execDetached(["xdg-open", "https://app.todoist.com/app/task/" + encodeURIComponent(task.id)]);
        dismissWorkspace();
    }
    function openCalendar(date) {
        var day = /^\d{4}-\d{2}-\d{2}$/.test(date || "") ? date : calendarToday;
        // Raise an existing calendar even when it lives on another workspace.
        Quickshell.execDetached(["sh", "-c",
            'omacal "$1" >/dev/null 2>&1 & sleep 0.4; '
            + 'hyprctl dispatch \'hl.dsp.focus({ window = "class:omacal" })\'; '
            + 'exec hyprctl dispatch \'hl.dsp.window.bring_to_top({ window = "class:omacal" })\'',
            "omaowl-calendar", day]);
        dismissWorkspace();
    }
    function toggleTask(id) {
        if (useTodoist) { if (todoistController.connected) todoistController.complete(id); return; }
        var t = workspace.tasks.find(t => t.id === id);
        if (!t || !ready || error) return;
        t.done = !t.done; t.completedAt = t.done ? Date.now() : 0; changed(true, true);
    }
    function setNote(text) {
        if (!ready || error || text === note) return;
        workspace.notes[noteDay] = text; changed();
    }
    function moveNoteDay(offset) {
        var d = new Date(noteDay + "T12:00:00"); d.setDate(d.getDate() + offset);
        noteDay = Logic.dayKey(d.getTime());
    }
    function chooseFocus(title, duration) {
        if (!ready || error) return;
        workspace.focus = {title: title || "Open focus", duration: duration, elapsed: 0, running: false};
        notice = ""; changed();
    }
    function toggleTimer() {
        if (!ready || error) return;
        if (workspace.focus.duration && workspace.focus.elapsed >= workspace.focus.duration) workspace.focus.elapsed = 0;
        workspace.focus.running = !workspace.focus.running;
        previousTick = Date.now(); notice = ""; changed(); flush();
    }
    function addFive() {
        if (!ready || error || !workspace.focus.duration) return;
        workspace.focus.duration += 300; changed();
    }
    Process {
        command: ["python3", Qt.resolvedUrl("initialize.py").toString().replace("file://", "")]
        running: true
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("Oma Owl storage:", text.trim()) }
        onExited: function(code) {
            if (code === 0) root.storagePrepared = true;
            else root.error = "Could not prepare workspace storage. Check " + root.dataDir;
        }
    }
    FileView {
        id: storage
        path: root.storagePrepared ? root.dataDir + "/workspace.json" : ""
        atomicWrites: true
        printErrors: false
        onLoaded: {
            if (root.ready || root.error) return;
            try { root.workspace = Logic.parse(text()); root.ready = true; root.changed(false, true); }
            catch (e) { root.error = "Could not read saved workspace. Original file preserved."; console.warn("OmaOwl:", e); }
        }
        onLoadFailed: { if (root.storagePrepared) root.error = "Workspace file unavailable. Check " + root.dataDir; }
        onSaveFailed: { root.error = "Saving failed. Keep this workspace open and check disk space."; }
    }
    FileView {
        id: feed
        path: root.stateDir + "/omacal/upcoming.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                var f = JSON.parse(text());
                root.agendaDays = Logic.calendarDays(f);
                root.calendarToday = f.panel && f.panel.date ? f.panel.date : root.today;
                root.calendarClocks = f.panel && f.panel.clocks ? f.panel.clocks : ({});
                root.calendarTimezone = f.panel && f.panel.timezone ? f.panel.timezone : "";
                var events = (f.events || []).concat(f.panel && f.panel.events ? f.panel.events : []);
                var seen = {};
                root.agenda = events.filter(function(e) {
                    var key = e.start_ms + ":" + e.end_ms + ":" + e.title;
                    if (seen[key] || typeof e.start_ms !== "number" || typeof e.end_ms !== "number") return false;
                    seen[key] = true; return true;
                });
                root.agendaUpdated = Date.now();
            } catch (e) { root.agenda = []; root.agendaDays = []; }
        }
        onLoadFailed: { root.agenda = []; root.agendaDays = []; }
    }
    Timer { id: saveTimer; interval: 300; onTriggered: root.flush() }
    Timer {
        interval: 1000; repeat: true; running: root.ready
        onTriggered: {
            var current = Date.now();
            var result = Logic.advance(root.workspace, (current - root.previousTick) / 1000, current);
            root.previousTick = current; root.now = current;
            if (result !== "idle") {
                root.changed(false);
                if (result === "finished") {
                    root.notice = "Session complete. Take a breath.";
                    Quickshell.execDetached(["notify-send", "OmaOwl · Focus complete", root.workspace.focus.title]);
                } else if (result === "paused") root.notice = "Focus paused while the desktop was away.";
                if (result !== "running" || Math.floor(root.workspace.focus.elapsed) % 5 === 0) root.flush();
            }
        }
    }
    Timer { interval: 60000; repeat: true; running: true; onTriggered: feed.reload() }
    Instantiator {
        id: windows
        model: Quickshell.screens
        delegate: OwlWindow { required property var modelData; screen: modelData; store: root }
    }
    function eachWindow(action) {
        for (var i = 0; i < windows.count; i++) action(windows.objectAt(i));
    }
    function windowForScreen(name) {
        for (var i = 0; i < windows.count; i++) {
            var panel = windows.objectAt(i);
            if (panel && panel.screen && panel.screen.name === name) return panel;
        }
        return windows.count ? windows.objectAt(0) : null;
    }
    IpcHandler {
        target: "omaowl"
        function open(): void { root.eachWindow(w => { w.pinned = true; w.open(); }); }
        function close(): void { root.eachWindow(w => { w.commandOpen = false; w.dashboardOpen = false; w.close(); }); }
        function dashboard(): void { if (windows.count > 0) windows.objectAt(0).openDashboard(); }
        function assistant(): void { root.eachWindow(w => { w.pinned = true; w.open(); w.workspacePanel.assistantOpen = true; }); }
        function toggle(): void { root.eachWindow(w => { if (w.commandOpen) w.commandOpen = false; else w.openCommand(); }); }
        function command(): void { root.eachWindow(w => w.openCommand()); }
        function tab(name: string): void { root.eachWindow(w => { w.workspacePanel.insights = name === "Insights"; w.pinned = true; w.open(); }); }
        function status(): string {
            var panels = []; root.eachWindow(w => panels.push({screen: w.screen.name, expanded: w.expanded, dashboard: w.dashboardOpen, command: w.commandOpen, timerPopout: w.timerPopout.visible, tab: w.currentTab, hovered: w.hovered}));
            return JSON.stringify({ready: root.ready, error: root.error, tasks: root.tasks.length, remaining: root.remainingTasks, taskSource: root.taskSource, todoistConnected: todoistController.connected, todoistBusy: todoistController.busy, todoistError: todoistController.error, running: root.focusState.running, timer: root.timerText, agendaEvents: root.agenda.length, calendarDays: root.agendaDays.length, windows: panels});
        }
        function mailStatus(): string { return JSON.stringify({connected: root.hey.connected, authenticated: root.hey.authenticated, newForYou: root.newMail.length, busy: root.hey.busy, error: root.hey.lastError}); }
    }
    Component.onDestruction: flush()
}
