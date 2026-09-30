import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    id: pane; objectName: "connections-pane"
    required property var store
    signal todoistSetupRequested()
    property string setupProvider: "gmail"
    readonly property var controller: setupProvider === "gmail" ? store.gmail : setupProvider === "outlook" ? store.outlook : setupProvider === "imap" ? store.imap : store.googleCalendar
    Theme { id: theme }
    clip: true
    contentWidth: availableWidth
    component Copy: Label {
        color: theme.text; font.family: theme.font; font.pixelSize: 15
        textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth: true
    }
    component Action: Button {
        id: button
        property bool selected: false
        implicitHeight: 38
        background: Rectangle { color: button.selected ? theme.accent : button.hovered ? theme.hover : theme.raised; radius: 3; opacity: button.enabled ? 1 : 0.4 }
        contentItem: Copy { text: button.text; color: button.selected ? theme.background : theme.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; leftPadding: 12; rightPadding: 12 }
    }
    component Entry: TextField {
        Layout.fillWidth: true; color: theme.text; font.family: theme.font; padding: 12
        placeholderTextColor: theme.muted; maximumLength: 512
        background: Rectangle { color: theme.raised; border.color: parent.activeFocus ? theme.accent : theme.border; radius: 3 }
    }
    ColumnLayout {
        width: pane.availableWidth; spacing: 14
        Copy { text: "Your apps. Your choice."; font.pixelSize: 25; font.bold: true }
        Copy { text: "Choose what appears in your workspace. Switching keeps your accounts and local tasks saved."; color: theme.muted }
        Copy { text: "Tasks"; font.bold: true }
        Flow {
            Layout.fillWidth: true; spacing: 8
            Action { text: "Local · no account"; selected: pane.store.taskSource === "local"; onClicked: pane.store.setTaskSource("local") }
            Action { text: "Todoist"; selected: pane.store.taskSource === "todoist"; onClicked: pane.store.setTaskSource("todoist") }
            Action { text: "Set up Todoist"; onClicked: { pane.store.setTaskSource("todoist"); pane.todoistSetupRequested(); } }
        }
        Copy { text: "Mail"; font.bold: true }
        Flow {
            Layout.fillWidth: true; spacing: 8
            Repeater {
                model: [{key:"hey",name:"HEY"},{key:"gmail",name:"Gmail"},{key:"outlook",name:"Outlook"},{key:"imap",name:"IMAP"},{key:"off",name:"Off"}]
                delegate: Action {
                    required property var modelData
                    text: modelData.name; selected: pane.store.mailSource === modelData.key
                    onClicked: { pane.store.setMailSource(modelData.key); if(modelData.key === "gmail" || modelData.key === "outlook" || modelData.key === "imap") pane.setupProvider=modelData.key; }
                }
            }
        }
        Copy { visible: pane.store.mailSource === "hey"; text: "HEY uses your existing HEY CLI login. Run hey auth login to connect."; color: theme.muted }
        Copy { text: "Calendar"; font.bold: true }
        Flow {
            Layout.fillWidth: true; spacing: 8
            Action { text: "OmaCal"; selected: pane.store.calendarSource === "omacal"; onClicked: pane.store.setCalendarSource("omacal") }
            Action { text: "Google Calendar"; selected: pane.store.calendarSource === "google"; onClicked: { pane.store.setCalendarSource("google"); pane.setupProvider="google-calendar"; } }
            Action { text: "Off"; selected: pane.store.calendarSource === "off"; onClicked: pane.store.setCalendarSource("off") }
        }
        Copy { visible: pane.store.calendarSource === "omacal"; text: "OmaCal supplies the calendars you connect there. Google Calendar can also connect directly below."; color: theme.muted }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.border }
        Copy { text: "Account setup"; font.pixelSize: 21; font.bold: true }
        Flow {
            Layout.fillWidth: true; spacing: 8
            Action { text: "Gmail"; selected: pane.setupProvider === "gmail"; onClicked: pane.setupProvider="gmail" }
            Action { text: "Outlook"; selected: pane.setupProvider === "outlook"; onClicked: pane.setupProvider="outlook" }
            Action { text: "IMAP"; selected: pane.setupProvider === "imap"; onClicked: pane.setupProvider="imap" }
            Action { text: "Google Calendar"; selected: pane.setupProvider === "google-calendar"; onClicked: pane.setupProvider="google-calendar" }
        }
        Copy { text: pane.controller.connected ? "Account connected" : "Account not connected"; color: pane.controller.connected ? theme.accent : theme.muted }
        Copy {
            text: pane.setupProvider === "imap" ? "Connect an IMAP account using your provider’s TLS server and app password. Usually port 993. This reads sender/subject headers without marking messages read. OAuth-only accounts should use Gmail or Outlook above."
                : pane.setupProvider === "outlook"
                ? "Use your Microsoft app registration’s client ID with public client flows enabled. Sign in with the device code shown here. Work accounts may need administrator consent."
                : "Use your Google OAuth Desktop app client ID and client secret. Enable the Gmail API or Calendar API for this connection and add yourself as a test user if needed. Sign-in opens in your browser."
            color: theme.muted
        }
        Action { text: "Open setup guide"; onClicked: Qt.openUrlExternally("https://github.com/therealasclepius/oma-pulse/blob/main/CONNECTIONS.md") }
        Entry { id: client; visible: pane.setupProvider !== "imap"; placeholderText: "OAuth client ID"; enabled: !pane.controller.busy; Accessible.name: "OAuth client ID" }
        Entry { id: secret; visible: pane.setupProvider !== "outlook" && pane.setupProvider !== "imap"; placeholderText: "Google client secret"; echoMode: TextInput.Password; enabled: !pane.controller.busy; Accessible.name: "Google client secret" }
        Entry { id: calendar; visible: pane.setupProvider === "google-calendar"; placeholderText: "Calendar ID (leave blank for primary)"; enabled: !pane.controller.busy; Accessible.name: "Google Calendar ID" }
        ColumnLayout {
            visible: pane.setupProvider === "imap"; Layout.fillWidth: true; spacing: 8
            Entry { id: imapHost; placeholderText: "IMAP server (for example, imap.example.com)"; enabled: !pane.controller.busy }
            Entry { id: imapPort; text: "993"; placeholderText: "TLS port"; validator: IntValidator { bottom: 1; top: 65535 } enabled: !pane.controller.busy }
            Entry { id: imapUser; placeholderText: "Username / email address"; enabled: !pane.controller.busy }
            Entry { id: imapPassword; placeholderText: "App password"; echoMode: TextInput.Password; enabled: !pane.controller.busy }
            Entry { id: imapFolder; text: "INBOX"; placeholderText: "Mailbox"; enabled: !pane.controller.busy }
            Entry { id: imapWebmail; placeholderText: "Webmail URL (optional, https://…)"; enabled: !pane.controller.busy }
            Action { text: "Connect IMAP"; enabled: !pane.controller.busy && !!imapHost.text.trim() && !!imapUser.text.trim() && !!imapPassword.text && imapPort.acceptableInput; onClicked: { pane.controller.connectImap(imapHost.text.trim(),Number(imapPort.text),imapUser.text.trim(),imapPassword.text,imapFolder.text.trim(),imapWebmail.text.trim()); imapPassword.clear(); } }
        }
        Flow {
            Layout.fillWidth: true; spacing: 8
            Action { visible: pane.setupProvider !== "imap"; text: pane.controller.connected ? "Reconnect in browser" : "Connect in browser"; enabled: !pane.controller.busy && !!client.text.trim(); onClicked: { pane.controller.connectAccount(client.text.trim(),secret.text.trim(),calendar.text.trim()); secret.clear(); } }
            Action { text: "Cancel sign-in"; visible: pane.controller.busy && pane.controller.operation === "connect"; onClicked: pane.controller.cancelLogin() }
            Action { text: "Disconnect"; enabled: pane.controller.connected && !pane.controller.busy; onClicked: pane.controller.disconnectAccount() }
        }
        Copy { visible: !!pane.controller.userCode; text: "Enter this code at Microsoft: " + pane.controller.userCode; font.pixelSize: 22; color: theme.accent }
        Action { text: "Reopen sign-in page"; visible: !!pane.controller.authUrl; onClicked: Qt.openUrlExternally(pane.controller.authUrl) }
        Copy { visible: pane.controller.busy; text: pane.controller.operation === "connect" ? "Connecting account…" : "Checking connection…"; color: theme.muted }
        Copy { visible: !!pane.controller.lastError; text: pane.controller.lastError; color: theme.urgent }
        Copy { text: "Gmail, Outlook and IMAP show up to 20 unread inbox messages and supports Mark read / Undo. Google Calendar is read only, showing eight days from one calendar. Disconnect removes local tokens; manage app consent with your provider."; color: theme.muted }
        Item { implicitHeight: 16 }
    }
    onSetupProviderChanged: { client.clear(); secret.clear(); calendar.clear(); imapPassword.clear(); }
}
