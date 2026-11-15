//@ pragma IconTheme breeze

// mujo's interface. It only presents: live state is read from Quickshell's
// services, and every change is made by running the mujo CLI (services/Mujo.qml).
// mujo in turn calls the IPC targets at the bottom of this file.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules
import qs.theme
import qs.services

ShellRoot {
    id: shell

    property bool barVisible: true

    Variants {
        model: Quickshell.screens

        Wallpaper {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    Variants {
        model: shell.barVisible ? Quickshell.screens : []

        Frame {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    Variants {
        model: Quickshell.screens

        Picker {}
    }

    Lock {
        id: lock
    }

    IpcHandler {
        target: "osd"

        function volume(percent: int, muted: bool): void {
            Ui.showOsd("volume", percent, muted);
        }

        function microphone(percent: int, muted: bool): void {
            Ui.showOsd("microphone", percent, muted);
        }

        function brightness(percent: int): void {
            Ui.showOsd("brightness", percent, false);
        }
    }

    IpcHandler {
        target: "launcher"

        function apps(): void {
            Ui.toggleLauncher("apps");
        }

        function actions(): void {
            Ui.toggleLauncher("actions");
        }

        function wallpapers(): void {
            Ui.toggleLauncher("wallpapers");
        }

        function clipboard(): void {
            Ui.toggleLauncher("clipboard");
        }

        function keys(): void {
            Ui.toggleLauncher("keys");
        }

        function wifi(): void {
            Ui.toggleLauncher("wifi");
        }

        function calc(): void {
            Ui.toggleLauncher("calc");
        }

        function emoji(): void {
            Ui.toggleLauncher("emoji");
        }

        function close(): void {
            Ui.closeAll();
        }
    }

    IpcHandler {
        target: "picker"

        function open(): void {
            Ui.openPicker();
        }

        function close(): void {
            Ui.picker = false;
        }
    }

    IpcHandler {
        target: "sidebar"

        function toggle(): void {
            Ui.toggleSidebar();
        }
    }

    IpcHandler {
        target: "dashboard"

        function toggle(): void {
            Ui.toggleDashboard("today");
        }

        function workspaces(): void {
            Ui.toggleDashboard("workspaces");
        }
    }

    IpcHandler {
        target: "session"

        function toggle(): void {
            Ui.toggleSession();
        }
    }

    IpcHandler {
        target: "wallpaper"

        function set(path: string): void {
            Settings.reload();
        }
    }

    IpcHandler {
        target: "notify"

        function reload(): void {
            Settings.reload();
        }

        function clear(): void {
            Notifs.clear();
        }

        function open(): void {
            Notifs.openNewest();
        }
    }

    IpcHandler {
        target: "theme"

        function reload(): void {
            Tokens.reload();
        }
    }

    IpcHandler {
        target: "record"

        function state(running: bool): void {
            Ui.recording = running;
        }
    }

    // A recording that outlived a restart of the interface is still shown.
    Process {
        running: true
        command: [Mujo.bin, "record", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    Ui.recording = JSON.parse(this.text).data.recording === true;
                } catch (error) {}
            }
        }
    }

    IpcHandler {
        target: "bar"

        function toggle(): void {
            shell.barVisible = !shell.barVisible;
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            lock.lock();
        }
    }
}
