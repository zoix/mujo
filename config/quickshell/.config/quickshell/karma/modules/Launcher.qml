// The launcher: a panel that rises from the bottom edge. Three modes share
// one search field:
//   apps        applications, most used first (karma launch list)
//   actions     every karma menu entry; typing ">" in the apps mode gets here
//   wallpapers  a strip of thumbnails (karma wall list). Moving along the
//               strip shows the image on the desktop at once and applies it
//               a moment later; there is nothing to confirm
// Choosing something runs the karma CLI; nothing is changed from here.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.theme
import qs.components
import qs.services

Item {
    id: root

    // True while this is the screen's open launcher.
    property bool active: false

    readonly property string mode: Ui.launcherMode
    readonly property bool strip: mode === "wallpapers"
    property var apps: []
    property var actions: []
    property var walls: []
    property string wallCurrent: ""
    property string query: ""
    readonly property var source: mode === "apps" ? apps : mode === "actions" ? actions : walls
    readonly property var results: root.filter(source, query)

    implicitWidth: strip ? Tokens.thumbWidth * 4 : Tokens.launcherWidth
    implicitHeight: body.implicitHeight + Tokens.spaceMd + Tokens.spaceMd

    Behavior on implicitWidth {
        Anim {}
    }
    Behavior on implicitHeight {
        Anim {}
    }

    function label(entry: var): string {
        return (root.mode === "actions" ? entry.label : entry.name) ?? "";
    }

    // 0 = no match. A match at the start of the text or of a word ranks
    // above one in the middle, and that above scattered letters.
    function score(needle: string, text: string): real {
        const hay = text.toLowerCase();
        const at = hay.indexOf(needle);
        if (at === 0)
            return 4;
        if (at > 0)
            return hay[at - 1] === " " || hay[at - 1] === ":" ? 3 : 2;
        let next = 0;
        for (const letter of hay) {
            if (letter === needle[next])
                next++;
            if (next === needle.length)
                return 1;
        }
        return 0;
    }

    function filter(list: var, text: string): var {
        const needle = text.trim().toLowerCase();
        if (needle === "")
            return list;
        return list.map(entry => ({
                    entry: entry,
                    rank: root.score(needle, root.label(entry))
                })).filter(item => item.rank > 0).sort((a, b) => b.rank - a.rank).map(item => item.entry);
    }

    function reload(): void {
        appsLoader.running = true;
        actionsLoader.running = true;
        wallsLoader.running = true;
    }

    function parse(text: string): var {
        try {
            return JSON.parse(text).data;
        } catch (error) {
            console.warn("karma: unexpected output from the karma CLI:", error);
            return null;
        }
    }

    function choose(): void {
        const view = root.strip ? thumbs : list;
        const entry = root.results[view.currentIndex];
        if (!entry)
            return;
        if (root.mode === "apps") {
            Karma.run(["launch", "run", entry.id]);
            Ui.closeAll();
        } else if (root.mode === "actions") {
            if (entry.kind === "confirm") {
                Ui.toggleSession();
            } else if (entry.command === "wall pick") {
                root.setMode("wallpapers");
            } else if (entry.command === "launch") {
                root.setMode("apps");
            } else {
                Karma.run(["menu", "run", entry.label]);
                Ui.closeAll();
            }
        } else {
            // The wallpaper under the cursor is applied already (or about to be).
            root.applyWallpaper();
            Ui.closeAll();
        }
    }

    // Show the wallpaper on the desktop immediately, and tell karma once
    // the selection has rested for a moment.
    function previewWallpaper(): void {
        const entry = root.results[thumbs.currentIndex];
        if (!root.strip || !entry || entry.path === root.wallCurrent)
            return;
        Ui.wallPreview = entry.path;
        settle.restart();
    }

    function applyWallpaper(): void {
        settle.stop();
        const entry = root.results[thumbs.currentIndex];
        if (!entry || entry.path === root.wallCurrent)
            return;
        root.wallCurrent = entry.path;
        Karma.run(["wall", "set", entry.path]);
    }

    Timer {
        id: settle
        interval: Tokens.durationSlow
        onTriggered: root.applyWallpaper()
    }

    function setMode(mode: string): void {
        Ui.launcherMode = mode;
        input.text = "";
        root.query = "";
    }

    function move(step: int): void {
        const view = root.strip ? thumbs : list;
        if (view.count === 0)
            return;
        view.currentIndex = Math.max(0, Math.min(view.count - 1, view.currentIndex + step));
    }

    onActiveChanged: {
        if (!active) {
            if (settle.running)
                root.applyWallpaper();
            return;
        }
        input.text = "";
        root.query = "";
        root.reload();
        input.forceActiveFocus();
        // Thumbnails and colour analysis for new images, in the background.
        indexer.running = true;
    }

    Process {
        id: indexer
        command: [Karma.bin, "wall", "index"]
        onExited: wallsLoader.running = true
    }

    onResultsChanged: {
        list.currentIndex = 0;
        if (root.strip) {
            const at = root.results.findIndex(entry => entry.path === root.wallCurrent);
            thumbs.currentIndex = Math.max(0, at);
        }
    }

    Process {
        id: appsLoader
        command: [Karma.bin, "launch", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const data = root.parse(this.text);
                if (data)
                    root.apps = data.apps;
            }
        }
    }

    Process {
        id: actionsLoader
        command: [Karma.bin, "menu", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const data = root.parse(this.text);
                if (data)
                    root.actions = data.entries;
            }
        }
    }

    Process {
        id: wallsLoader
        command: [Karma.bin, "wall", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const data = root.parse(this.text);
                if (!data)
                    return;
                root.wallCurrent = data.current ?? "";
                root.walls = data.images;
            }
        }
    }

    Column {
        id: body

        x: Tokens.spaceMd
        y: Tokens.spaceMd
        width: root.width - Tokens.spaceMd - Tokens.spaceMd
        spacing: Tokens.spaceSm

        // Apps and actions: a list, at most seven rows tall.
        ListView {
            id: list

            visible: !root.strip
            width: parent.width
            height: Math.min(count, 7) * Tokens.row
            clip: true
            model: root.strip ? [] : root.results
            highlightMoveDuration: Tokens.durationFast
            highlightResizeDuration: 0
            boundsBehavior: Flickable.StopAtBounds

            Behavior on height {
                Anim {}
            }

            highlight: Rectangle {
                radius: Tokens.radiusMd
                color: Tokens.bgControl
            }

            delegate: Item {
                id: entryRow

                required property var modelData
                required property int index

                width: list.width
                height: Tokens.row

                // The app's icon; an entry without one in the icon theme gets a
                // plain symbol instead.
                readonly property string iconSource: {
                    const name = root.mode === "apps" ? (entryRow.modelData.icon ?? "") : "";
                    if (name === "")
                        return "";
                    return name.startsWith("/") ? "file://" + name : Quickshell.iconPath(name, true);
                }

                IconImage {
                    id: appIcon
                    visible: entryRow.iconSource !== ""
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spaceMd
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: Tokens.icon
                    source: entryRow.iconSource
                }

                Glyph {
                    visible: entryRow.iconSource === ""
                    anchors.centerIn: appIcon
                    text: root.mode === "apps" ? "\uf009" : "\uf054"
                    font.pixelSize: Tokens.fontMd
                    color: list.currentIndex === entryRow.index ? Tokens.accent : Tokens.textMuted
                }

                Column {
                    anchors.left: appIcon.right
                    anchors.leftMargin: Tokens.spaceMd
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.spaceMd
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Text {
                        width: parent.width
                        text: root.label(entryRow.modelData)
                        color: Tokens.textPrimary
                        elide: Text.ElideRight
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontMd
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: root.mode === "apps" ? (entryRow.modelData.comment ?? "") : "karma " + (entryRow.modelData.command ?? "")
                        color: Tokens.textMuted
                        elide: Text.ElideRight
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontXs
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: list.currentIndex = entryRow.index
                    onClicked: root.choose()
                }
            }
        }

        // Wallpapers: a strip of thumbnails; the chosen one stays in the middle.
        ListView {
            id: thumbs

            visible: root.strip
            width: parent.width
            height: Tokens.thumbHeight
            clip: true
            orientation: ListView.Horizontal
            onCurrentIndexChanged: root.previewWallpaper()
            spacing: Tokens.spaceSm
            model: root.strip ? root.results : []
            highlightMoveDuration: Tokens.durationNormal
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: (width - Tokens.thumbWidth) / 2
            preferredHighlightEnd: (width + Tokens.thumbWidth) / 2

            delegate: Item {
                id: thumb

                required property var modelData
                required property int index
                readonly property bool current: thumbs.currentIndex === index

                width: Tokens.thumbWidth
                height: thumbs.height

                ClippingRectangle {
                    id: picture
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    height: Tokens.thumbHeight
                    radius: Tokens.radiusMd
                    color: Tokens.bgControl
                    scale: thumb.current ? 1 : 0.84
                    opacity: thumb.current ? 1 : 0.6
                    border.width: thumb.modelData.path === root.wallCurrent ? Tokens.borderFocus : 0
                    border.color: Tokens.accent

                    Behavior on scale {
                        Anim {}
                    }
                    Behavior on opacity {
                        Anim {}
                    }

                    Image {
                        anchors.fill: parent
                        source: thumb.modelData.path ? "file://" + (thumb.modelData.thumb ?? thumb.modelData.path) : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: Tokens.thumbWidth + Tokens.thumbWidth
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: thumbs.currentIndex = thumb.index
                }
            }
        }

        Text {
            visible: root.results.length === 0
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.strip && root.walls.length === 0 ? "No images in the wallpaper folder (~/Pictures/Wallpapers)" : "Nothing matches"
            color: Tokens.textMuted
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontSm
        }

        // Search field
        Rectangle {
            width: parent.width
            height: Tokens.row - Tokens.spaceSm
            radius: Tokens.radiusFull
            color: Tokens.bgBase

            Glyph {
                id: prompt
                anchors.left: parent.left
                anchors.leftMargin: Tokens.spaceLg
                anchors.verticalCenter: parent.verticalCenter
                text: root.mode === "apps" ? "" : root.mode === "actions" ? "" : ""
                font.pixelSize: Tokens.fontMd
                color: Tokens.accent
            }

            TextInput {
                id: input

                anchors.left: prompt.right
                anchors.leftMargin: Tokens.spaceMd
                anchors.right: parent.right
                anchors.rightMargin: Tokens.spaceLg
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                color: Tokens.textPrimary
                selectionColor: Tokens.accent
                selectedTextColor: Tokens.textOnAccent
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontMd

                onTextEdited: {
                    if (root.mode === "apps" && text.startsWith(">")) {
                        Ui.launcherMode = "actions";
                        text = text.slice(1);
                    }
                    root.query = text;
                }

                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    if (event.key === Qt.Key_Escape) {
                        Ui.closeAll();
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.choose();
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right && root.strip || ctrl && event.key === Qt.Key_N || ctrl && event.key === Qt.Key_J) {
                        root.move(1);
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left && root.strip || ctrl && event.key === Qt.Key_P || ctrl && event.key === Qt.Key_K) {
                        root.move(-1);
                    } else if (event.key === Qt.Key_Backspace && input.text === "" && root.mode !== "apps") {
                        root.setMode("apps");
                    } else {
                        return;
                    }
                    event.accepted = true;
                }
            }

            Text {
                anchors.left: input.left
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === ""
                text: root.mode === "apps" ? "Search apps, or type > for commands" : root.mode === "actions" ? "Search commands" : "Left and right to choose; Escape closes"
                color: Tokens.textMuted
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontMd
            }
        }
    }
}
