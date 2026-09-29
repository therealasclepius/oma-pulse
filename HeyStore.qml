import QtQuick
import Quickshell.Io

Item {
    id: root
    property bool active: true
    property bool authenticated: true
    property bool installed: true
    property bool connected: false
    property bool received: false
    property bool refreshPending: false
    property var notifications: []
    property string lastError: ""
    property double lastUpdated: 0
    property var pendingChange: null
    property var undoStack: []
    property string actionError: ""
    property bool changeReceived: false
    readonly property bool changing: pendingChange !== null
    readonly property bool busy: reader.running
    function markRead(message) { changeSeen(message, true); }
    function undoRead() { if (undoStack.length) changeSeen(undoStack[undoStack.length - 1], false); }
    function changeSeen(message, seen) {
        if (changing || !message) return;
        if (!/^[1-9][0-9]*$/.test(message.id) || !/^[1-9][0-9]*$/.test(message.accountId || "")) {
            actionError = "Refresh HEY before changing this email."; return;
        }
        pendingChange = {message: Object.assign({}, message), seen: seen};
        actionError = ""; changeReceived = false;
        writer.stdinEnabled = true; writer.running = true;
    }
    function applyChange() {
        var change = pendingChange, message = change.message;
        notifications = notifications.map(m => m.id === message.id && m.accountId === message.accountId ? Object.assign({}, m, {unread: !change.seen}) : m);
        if (change.seen) undoStack = undoStack.concat([message]).slice(-20);
        else {
            undoStack = undoStack.slice(0, -1);
            if (!notifications.some(m => m.id === message.id && m.accountId === message.accountId))
                notifications = [Object.assign({}, message, {unread:true})].concat(notifications);
        }
    }
    function clean(value, limit) { return String(value || "").replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim().slice(0, limit); }
    function refresh() {
        if (!active) return;
        if (busy) { refreshPending = true; return; }
        received = false; reader.running = true;
    }
    function refreshIfStale() { if (Date.now() - lastUpdated > 60000) refresh(); }
    function failed(text) {
        var response;
        try { response = JSON.parse(text); } catch (e) { response = {}; }
        if (response.code === "auth" || response.code === "auth_required") {
            authenticated = false; connected = false; notifications = []; watcher.running = false;
            lastError = "Sign in with hey auth login, then refresh.";
        } else lastError = "Could not refresh HEY. Try again.";
    }
    Process {
        id: reader
        command: ["timeout", "25s", "hey", "--account", "all", "box", "view", "imbox", "--limit", "50", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (text.length > 1048576) throw new Error("Response too large");
                    var response = JSON.parse(text);
                    if (response.ok === false) { root.failed(text); return; }
                    if (!response.data || !Array.isArray(response.data.postings)) throw new Error("Invalid response");
                    root.notifications = response.data.postings.slice(0, 50).map(function(p) {
                        var timestamp = p.active_at || p.updated_at || p.created_at || "";
                        return {id: String(p.id), accountId: String(p.account_id || ""), title: root.clean(p.name || "HEY email", 256),
                            creator: root.clean(p.alternative_sender_name || (p.creator || {}).name || (p.creator || {}).email_address || "HEY", 160),
                            excerpt: root.clean(p.summary || p.note, 512), url: String(p.app_url || ""),
                            unread: p.seen !== true, timestampMs: Date.parse(timestamp) || 0};
                    });
                    root.received = true; root.authenticated = true; root.installed = true;
                    root.lastError = ""; root.lastUpdated = Date.now();
                    if (!watcher.running) watcher.running = root.active;
                } catch (e) { root.lastError = "Could not read HEY’s response. Try refreshing."; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) root.failed(text) }
        onExited: function(code) {
            if (code === 127) { root.installed = false; root.lastError = "Install the HEY CLI to connect mail."; }
            else if (!root.received && !root.lastError) root.lastError = "Could not refresh HEY. Try again.";
            if (root.refreshPending && root.authenticated) { root.refreshPending = false; debounce.restart(); }
        }
    }
    Process {
        id: writer
        command: ["timeout", "70s", "python3", Qt.resolvedUrl("hey_mail.py").toString().replace("file://", "")]
        onStarted: {
            var change = root.pendingChange;
            write(JSON.stringify({id:change.message.id, account_id:change.message.accountId, seen:change.seen}) + "\n");
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var result = JSON.parse(text); root.changeReceived = true;
                    if (result.ok === true) root.applyChange();
                    else root.actionError = result.error || "Could not update HEY. Please retry.";
                } catch(e) { root.actionError = "Could not confirm the change. Refresh before retrying."; }
            }
        }
        onExited: function(code) {
            if (!root.changeReceived && !root.actionError) root.actionError = "HEY did not respond. Refresh before retrying.";
            root.pendingChange = null;
            root.refresh();
        }
    }
    Process {
        id: watcher
        command: ["setpriv", "--pdeathsig", "TERM", "hey", "--account", "all", "watch", "--events", "added,updated,deleted,new,resync"]
        stdout: SplitParser {
            onRead: function(data) {
                if (data.length > 65536) return;
                try {
                    var event = JSON.parse(data);
                    if (event.change === "disconnected") { root.connected = false; return; }
                    if (event.change === "ready") root.connected = true;
                    if (["ready", "resync", "added", "updated", "deleted"].indexOf(event.change) >= 0) debounce.restart();
                } catch (e) {}
            }
        }
        stderr: SplitParser { onRead: function(data) { if (data.indexOf('"auth"') >= 0 || data.indexOf('"auth_required"') >= 0) root.failed(data); } }
        onExited: { root.connected = false; if (root.active && root.authenticated && root.installed) reconnect.restart(); }
    }
    Timer { id: debounce; interval: 500; onTriggered: root.refresh() }
    Timer { id: reconnect; interval: 30000; onTriggered: if (root.active && root.authenticated) { watcher.running = true; } }
    onActiveChanged: {
        if (active) refresh();
        else { reader.running = false; watcher.running = false; debounce.stop(); reconnect.stop(); }
    }
    Component.onCompleted: refresh()
}
