pragma Singleton

// The notification server. While do-not-disturb is on, only critical
// notifications are shown.
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    readonly property var list: server.trackedNotifications.values

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
            if (Settings.dnd && notification.urgency !== NotificationUrgency.Critical) {
                notification.expire();
                return;
            }
            notification.tracked = true;
        }
    }
}
