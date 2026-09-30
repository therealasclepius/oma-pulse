import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: mail
    Theme { id: theme }
    required property var store
    readonly property var service: store.mail
    spacing: 14
    function openMail(url) {
        mail.store.openMail(url);
    }
    component Copy: Text {
        color: theme.text; font.family: theme.font; font.pixelSize: 14
        textFormat: Text.PlainText; elide: Text.ElideRight
    }
    component Action: Button {
        id: action; focusPolicy: Qt.NoFocus; implicitHeight: 38
        background: Rectangle { color: action.hovered ? theme.hover : theme.raised; radius: 3; opacity: action.enabled ? 1 : 0.4 }
        contentItem: Copy { text: action.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
    }
    RowLayout {
        Copy { text: mail.store.mailSource === "off" ? "Mail" : mail.store.mailName + " mail"; font.pixelSize: 22; font.weight: Font.DemiBold; Layout.fillWidth: true }
        Action { text: "↻"; implicitWidth: 38; enabled: mail.store.mailSource !== "off" && !!mail.service && !mail.service.busy; onClicked: mail.service.refresh(); Accessible.name: "Refresh " + mail.store.mailName }
    }
    Copy { Layout.fillWidth: true; text: mail.service && mail.service.busy ? "Checking mail…" : (mail.store.mailSource === "hey" ? "New for You · " : "Unread · ") + mail.store.newMail.length; opacity: 0.7; font.pixelSize: 12 }
    ListView {
        id: messages; objectName: "hey-messages"
        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 10
        model: mail.store.newMail
        ScrollBar.vertical: ScrollBar {}
        delegate: SwipeDelegate {
            id: message
            required property var modelData
            width: ListView.view.width; height: 120
            hoverEnabled: true; focusPolicy: Qt.NoFocus
            enabled: !mail.service.changing
            swipe.right: Rectangle {
                width: message.width; height: message.height; color: theme.accent; radius: 3
                Copy { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter; text: "✓  Mark read"; color: theme.background }
            }
            swipe.onCompleted: { swipe.close(); mail.service.markRead(modelData); }
            onClicked: mail.openMail(modelData.url)
            Accessible.name: "Open email: " + modelData.title
            background: Rectangle { color: message.hovered ? theme.hover : theme.raised; radius: 3 }
            padding: 12
            contentItem: ColumnLayout {
                spacing: 6
                RowLayout {
                    Copy { Layout.fillWidth: true; text: message.modelData.creator || "HEY"; font.weight: Font.DemiBold; font.pixelSize: 12 }
                    Action {
                        text: "✓"; implicitWidth: 30; implicitHeight: 28
                        onClicked: mail.service.markRead(message.modelData)
                        Accessible.name: "Mark email as read: " + message.modelData.title
                        ToolTip.visible: hovered; ToolTip.text: "Mark read"; ToolTip.delay: 400
                    }
                    Copy { text: message.modelData.timestampMs ? Qt.formatDate(new Date(message.modelData.timestampMs), "d MMM") : ""; opacity: 0.6; font.pixelSize: 10 }
                }
                Copy { Layout.fillWidth: true; text: message.modelData.title; wrapMode: Text.Wrap; maximumLineCount: 2; font.weight: Font.Medium; font.pixelSize: 15 }
                Copy { Layout.fillWidth: true; text: message.modelData.excerpt || message.modelData.accountName || "Open in HEY"; font.pixelSize: 12; opacity: 0.7 }
                Item { Layout.fillHeight: true }
            }
        }
        Copy {
            anchors.centerIn: parent; width: parent.width; visible: messages.count === 0
            text: mail.store.mailSource === "off" ? "Mail is off. Choose a provider\nin Connections."
                : mail.store.mailSource !== "hey" && !mail.service.connected ? "Connect " + mail.store.mailName + "\nin Connections to see your mail."
                : !mail.service || !mail.service.installed ? "Install the HEY CLI\nto connect your Imbox."
                : !mail.service.authenticated ? "Sign in with hey auth login\nto see your mail."
                : mail.service.busy ? "Checking mail…"
                : mail.service.lastError ? "Mail is temporarily unavailable."
                : "You’re all caught up."
            wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; opacity: 0.7
        }
    }
    RowLayout {
        visible: mail.store.mailSource !== "off" && (mail.service.changing || mail.service.undoStack.length > 0)
        Layout.fillWidth: true
        Copy { Layout.fillWidth: true; text: mail.service.changing ? "Updating mail…" : "Marked as read"; font.pixelSize: 11 }
        Action { text: "Undo"; implicitHeight: 30; visible: mail.service.undoStack.length > 0; enabled: !mail.service.changing; onClicked: mail.service.undoRead() }
    }
    Copy { visible: mail.store.mailSource === "imap" && !mail.store.imap.webmailUrl; text: "Add a webmail URL in Connections to open your full inbox."; color: theme.muted; font.pixelSize: 11 }
    Copy { visible: !!mail.service.actionError; text: mail.service.actionError; color: theme.urgent; Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 11 }
    Copy {
        Layout.fillWidth: true; wrapMode: Text.Wrap; maximumLineCount: 2; font.pixelSize: 11; opacity: 0.7
        text: mail.store.mailSource === "off" ? "" : mail.service.lastError || (mail.store.mailSource === "hey" ? (mail.service.connected ? "Live · Imbox · Swipe left or ✓ to mark read" : "Live updates reconnecting…") : (mail.service.connected ? "Unread inbox · Refreshes every 2 min" : "Sign in through Connections"))
    }
    Action { Layout.fillWidth: true; visible: mail.store.mailSource !== "off"; text: mail.store.mailSource === "imap" ? "Open webmail" : "Open " + mail.store.mailName; enabled: mail.store.mailSource !== "imap" || !!mail.store.imap.webmailUrl; onClicked: mail.openMail("") }
}
