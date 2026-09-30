import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    required property string provider
    property bool active: false
    property bool connected: false
    readonly property bool authenticated: connected
    readonly property bool installed: true
    readonly property bool busy: worker.running
    readonly property bool changing: busy && operation === "seen"
    property var notifications: []
    property var undoStack: []
    property var days: []
    property var events: []
    property var clocks: ({})
    property string today: ""
    property string timezone: ""
    property string accountEmail: ""
    property string webmailUrl: ""
    property string calendarId: "primary"
    property string lastError: ""
    property string actionError: ""
    property string authUrl: ""
    property string userCode: ""
    property double lastUpdated: 0
    property var payload: ({})
    property var pendingMessage: null
    property bool pendingSeen: true
    property string operation: ""
    property bool received: false
    property bool syncAfter: false
    signal feedChanged()
    function send(args) {
        if (busy) return false;
        operation = args.action; payload = Object.assign({provider: provider}, args); received = false;
        lastError = ""; actionError = ""; worker.stdinEnabled = true; worker.running = true; return true;
    }
    function connectAccount(client, secret, calendar) {
        authUrl = ""; userCode = "";
        return send({action:"connect", client_id:client, client_secret:secret, calendar_id:calendar || "primary"});
    }
    function connectImap(host,port,username,password,folder,webmail) {
        return send({action:"connect",host:host,port:port,username:username,password:password,folder:folder,webmail_url:webmail});
    }
    function cancelLogin() { if (busy && operation === "connect") { worker.running = false; authUrl = ""; userCode = ""; } }
    function disconnectAccount() { send({action:"disconnect"}); }
    function refresh() { if (active && connected && !busy) send({action:"sync"}); }
    function refreshIfStale() { if (Date.now() - lastUpdated > 60000) refresh(); }
    function markRead(message) { changeSeen(message,true); }
    function undoRead() { if (undoStack.length) changeSeen(undoStack[undoStack.length-1],false); }
    function changeSeen(message,seen) {
        if (busy || !connected || !message) return;
        pendingMessage = Object.assign({},message); pendingSeen = seen;
        send({action:"seen",id:message.id,uidvalidity:message.uidvalidity || "",seen:seen});
    }
    onActiveChanged: if (active) refreshIfStale()
    Process {
        id: worker
        command: ["timeout", "650s", "python3", Qt.resolvedUrl("providers.py").toString().replace("file://", "")]
        onStarted: { write(JSON.stringify(root.payload)+"\n"); stdinEnabled=false; root.payload=({}); }
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    var r=JSON.parse(line);
                    if (r.auth_url) {
                        if (/^https:\/\/accounts\.google\.com\/o\/oauth2\/v2\/auth\?/.test(r.auth_url) || r.auth_url === "https://microsoft.com/devicelogin") {
                            root.authUrl=r.auth_url; root.userCode=r.user_code || "";
                            Quickshell.execDetached(["xdg-open",root.authUrl]);
                        }
                        return;
                    }
                    root.received=true; root.authUrl=""; root.userCode="";
                    if (!r.ok) { if(root.operation === "seen") root.actionError=r.error; else root.lastError=r.error; return; }
                    if (r.connected !== undefined) root.connected=r.connected;
                    if (r.webmail_url !== undefined) root.webmailUrl=r.webmail_url;
                    if (r.calendar_id) root.calendarId=r.calendar_id;
                    if (root.operation === "disconnect") {
                        root.notifications=[]; root.undoStack=[]; root.days=[]; root.events=[]; root.clocks=({}); root.feedChanged();
                    }
                    if (root.operation === "connect") {
                        root.notifications=[]; root.undoStack=[]; root.days=[]; root.events=[]; root.clocks=({}); root.feedChanged();
                    }
                    if (r.notifications) root.notifications=r.notifications;
                    if (r.days) { root.days=r.days; root.events=r.events; root.clocks=r.clocks; root.today=r.today; root.timezone=r.timezone; root.accountEmail=r.account_email || ""; root.feedChanged(); }
                    if (root.operation === "sync") root.lastUpdated=Date.now();
                    if (root.operation === "seen") {
                        var m=root.pendingMessage;
                        root.notifications=root.notifications.map(n=>n.id === m.id ? Object.assign({},n,{unread:!root.pendingSeen}) : n);
                        if (root.pendingSeen) root.undoStack=root.undoStack.concat([m]).slice(-20);
                        else { root.undoStack=root.undoStack.slice(0,-1); if(!root.notifications.some(n=>n.id===m.id)) root.notifications=[Object.assign({},m,{unread:true})].concat(root.notifications); }
                    }
                    if (["status","connect"].indexOf(root.operation)>=0 && root.connected) root.syncAfter=true;
                } catch(e) { root.lastError="Could not read the provider response."; }
            }
        }
        onExited: function(code) {
            if (!root.received && !root.lastError) root.lastError=code === 124 ? "The request timed out. Try again." : "Request cancelled or provider unavailable.";
            root.payload=({}); root.pendingMessage=null; root.authUrl=""; root.userCode="";
            if (root.syncAfter) { root.syncAfter=false; later.restart(); }
        }
    }
    Timer { id: later; interval: 100; onTriggered: root.refresh() }
    Timer { interval: 120000; repeat: true; running: root.active && root.connected; onTriggered: root.refresh() }
    Component.onCompleted: send({action:"status"})
}
