pragma Singleton

// The notification server. While do-not-disturb is on, only critical
// notifications are shown.
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    readonly property var list: server.trackedNotifications.values

    // The last notifications, newest first, kept after their cards are gone
    // (and while do-not-disturb holds cards back). Lost when the interface
    // restarts.
    property var history: []

    function remember(notification: var): void {
        const entry = {
            app: notification.appName,
            summary: notification.summary,
            body: notification.body,
            time: new Date()
        };
        root.history = [entry].concat(root.history).slice(0, 40);
    }

    function forget(): void {
        root.history = [];
    }

    function clear(): void {
        for (const notification of root.list.slice())
            notification.dismiss();
    }

    NotificationServer {
        id: server
        keepOnReload: false
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        imageSupported: false

        onNotification: notification => {
            root.remember(notification);
            if (Settings.dnd && notification.urgency !== NotificationUrgency.Critical) {
                notification.expire();
                return;
            }
            notification.tracked = true;
        }
    }
}
