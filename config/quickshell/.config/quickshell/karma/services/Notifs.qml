pragma Singleton

// The notification server. While do-not-disturb is on, only critical
// notifications are shown.
import QtQuick
import Quickshell
import Quickshell.Hyprland
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

    // Clicking a notification: do what the app meant by a click (its
    // "default" action, if it sent one) and bring the app's window forward,
    // on whatever workspace it is. Then the card goes away.
    function open(notification: var): void {
        const action = notification.actions.find(a => a.identifier === "default");
        const wanted = [notification.desktopEntry, notification.appName].filter(n => n).map(n => n.toLowerCase());
        const target = Hyprland.toplevels.values.find(t => {
            const name = t.lastIpcObject && t.lastIpcObject.class ? t.lastIpcObject.class.toLowerCase() : "";
            return name !== "" && wanted.some(w => w === name || w.endsWith("." + name) || name.endsWith("." + w));
        });
        if (target) {
            if (target.workspace)
                target.workspace.activate();
            if (target.wayland)
                target.wayland.activate();
        }
        if (action)
            action.invoke();
        else
            notification.dismiss();
    }

    // The newest notification still on screen, for the keyboard.
    function openNewest(): void {
        if (root.list.length > 0)
            root.open(root.list[root.list.length - 1]);
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
            // So that the window list is fresh if this one is clicked.
            Hyprland.refreshToplevels();
            if (Settings.dnd && notification.urgency !== NotificationUrgency.Critical) {
                notification.expire();
                return;
            }
            notification.tracked = true;
        }
    }
}
