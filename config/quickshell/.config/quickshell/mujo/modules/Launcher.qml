// The launcher: a panel that rises from the bottom edge. Three modes share
// one search field:
//   apps        applications, most used first (mujo launch list)
//   actions     every mujo menu entry; typing ">" in the apps mode gets here
//   clipboard   the clipboard history (mujo clip list); Enter copies an entry
//   keys        the keybindings (mujo keys); Enter does what one does
//   wifi        networks in range (mujo net scan); Enter connects, and a
//               new protected network asks for its password in the field
//   calc        a calculator (mujo calc); typing "=" in the apps mode gets
//               here, and Enter copies the result
//   emoji       emoji by name (mujo emoji list); Enter copies one
//   wallpapers  a strip of thumbnails (mujo wall list). Moving along the
//               strip shows the image on the desktop at once and applies it
//               a moment later; there is nothing to confirm
// Choosing something runs the mujo CLI; nothing is changed from here.
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
    property var clips: []
    property var binds: []
    property var nets: []
    property var emoji: []
    // The calculator's answer for the text in the field ("" = none yet).
    property string answer: ""
    // The network a password is being asked for ("" = not asking).
    property string passwordFor: ""
    property string query: ""
    readonly property var source: passwordFor !== "" ? [] : mode === "apps" ? apps : mode === "actions" ? actions : mode === "clipboard" ? clips : mode === "keys" ? binds : mode === "wifi" ? nets : mode === "emoji" ? emoji : mode === "calc" ? [] : walls
    readonly property var results: mode === "calc" ? (answer !== "" ? [{
                name: answer
            }] : []) : root.filter(source, query)

    // The calculator works the answer out a moment after typing stops.
    onQueryChanged: {
        if (root.mode !== "calc")
            return;
        if (root.query.trim() === "")
            root.answer = "";
        else
            calcDelay.restart();
    }

    Timer {
        id: calcDelay
        interval: 200
        onTriggered: {
            if (root.mode !== "calc" || root.query.trim() === "")
                return;
            calculator.running = false;
            calculator.asked = root.query;
            calculator.command = [Mujo.bin, "calc", root.query, "--json"];
            calculator.running = true;
        }
    }

    Process {
        id: calculator
        property string asked: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (calculator.asked !== root.query)
                    return;
                const data = root.parse(this.text);
                root.answer = data && data.result ? data.result : "";
            }
        }
    }

    Process {
        id: emojiLoader
        command: [Mujo.bin, "emoji", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const data = root.parse(this.text);
                if (data)
                    root.emoji = data.emoji;
            }
        }
    }

    implicitWidth: strip ? Tokens.thumbWidth * 4 : Tokens.launcherWidth
    implicitHeight: body.implicitHeight + Tokens.spaceMd + Tokens.spaceMd

    Behavior on implicitWidth {
        Anim {}
    }
    Behavior on implicitHeight {
        Anim {}
    }

    // The text an entry is searched and listed by.
    function label(entry: var): string {
        switch (root.mode) {
        case "actions":
            return entry.label ?? "";
        case "clipboard":
            return entry.preview ?? "";
        case "keys":
            return (entry.description ?? "") + "  " + (entry.keys ?? "");
        case "wifi":
            return entry.ssid ?? "";
        default:
            return entry.name ?? "";
        }
    }

    // The smaller second line of an entry.
    function detail(entry: var): string {
        switch (root.mode) {
        case "apps":
            return entry.comment ?? "";
        case "calc":
            return "Enter copies the result";
        case "actions":
            return "mujo " + (entry.command ?? "");
        case "keys":
            return entry.keys ?? "";
        case "wifi":
            return (entry.signal ?? 0) + "%  " + (entry.security ?? "") + (entry.in_use ? "  connected" : entry.saved ? "  saved" : "");
        default:
            return "";
        }
    }

    function title(entry: var): string {
        if (root.mode === "emoji")
            return (entry.emoji ?? "") + "  " + (entry.name ?? "");
        return root.mode === "keys" ? (entry.description ?? "") : root.label(entry);
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

    // Fetch the list for the current mode from mujo.
    function reload(): void {
        switch (root.mode) {
        case "apps":
            appsLoader.running = true;
            break;
        case "actions":
            actionsLoader.running = true;
            break;
        case "clipboard":
            clipsLoader.running = true;
            break;
        case "keys":
            bindsLoader.running = true;
            break;
        case "calc":
            root.answer = "";
            break;
        case "emoji":
            if (root.emoji.length === 0)
                emojiLoader.running = true;
            break;
        case "wifi":
            // What NetworkManager already knows, at once; a fresh scan follows.
            netsLoader.command = [Mujo.bin, "net", "scan", "--no-rescan", "--json"];
            netsLoader.running = true;
            rescan.restart();
            break;
        default:
            wallsLoader.running = true;
            // Thumbnails and colour analysis for new images, in the background.
            indexer.running = true;
        }
    }

    Timer {
        id: rescan
        interval: Tokens.durationSlow
        onTriggered: {
            if (root.active && root.mode === "wifi" && !netsLoader.running) {
                netsLoader.command = [Mujo.bin, "net", "scan", "--json"];
                netsLoader.running = true;
            }
        }
    }

    onModeChanged: {
        root.passwordFor = "";
        if (root.active)
            root.reload();
    }

    function parse(text: string): var {
        try {
            return JSON.parse(text).data;
        } catch (error) {
            console.warn("mujo: unexpected output from the mujo CLI:", error);
            return null;
        }
    }

    function choose(): void {
        const view = root.strip ? thumbs : list;
        const entry = root.results[view.currentIndex];
        if (root.passwordFor !== "") {
            if (input.text === "")
                return;
            connector.command = [Mujo.bin, "net", "connect", root.passwordFor, "--password-stdin"];
            connector.secret = input.text;
            connector.running = true;
            Ui.closeAll();
            return;
        }
        if (!entry)
            return;
        if (root.mode === "calc") {
            Mujo.run(["calc", root.query, "--copy"]);
            Ui.closeAll();
        } else if (root.mode === "emoji") {
            Mujo.run(["emoji", "copy", entry.emoji]);
            Ui.closeAll();
        } else if (root.mode === "clipboard") {
            Mujo.run(["clip", "copy", entry.id]);
            Ui.closeAll();
        } else if (root.mode === "keys") {
            // Enter does what the binding does (those that can be run).
            Ui.closeAll();
            if (entry.action)
                Mujo.run(["keys", "run", entry.description]);
        } else if (root.mode === "wifi") {
            if (entry.in_use) {
                Ui.closeAll();
            } else if (entry.saved || entry.security === "open") {
                Mujo.run(["net", "connect", entry.ssid]);
                Ui.closeAll();
            } else {
                // A new protected network: the field becomes a password field.
                root.passwordFor = entry.ssid;
                input.text = "";
                root.query = "";
            }
        } else if (root.mode === "apps") {
            Mujo.run(["launch", "run", entry.id]);
            Ui.closeAll();
        } else if (root.mode === "actions") {
            if (entry.kind === "confirm") {
                Ui.toggleSession();
            } else if (entry.command === "wall pick") {
                root.setMode("wallpapers");
            } else if (entry.command === "launch") {
                root.setMode("apps");
            } else if (entry.command === "clip") {
                root.setMode("clipboard");
            } else if (entry.command === "keys tui") {
                root.setMode("keys");
            } else if (entry.command === "net tui") {
                root.setMode("wifi");
            } else if (entry.command === "calc") {
                root.setMode("calc");
            } else if (entry.command === "emoji") {
                root.setMode("emoji");
            } else {
                Mujo.run(["menu", "run", entry.label]);
                Ui.closeAll();
            }
        } else {
            // The wallpaper under the cursor is applied already (or about to be).
            root.applyWallpaper();
            Ui.closeAll();
        }
    }

    // Show the wallpaper on the desktop immediately, and tell mujo once
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
        Mujo.run(["wall", "set", entry.path]);
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
        root.passwordFor = "";
        root.reload();
        input.forceActiveFocus();
    }

    Process {
        id: clipsLoader
        command: [Mujo.bin, "clip", "list", "--limit", "200", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const data = root.parse(this.text);
                if (data)
                    root.clips = data.entries;
            }
        }
    }

    Process {
        id: bindsLoader
        command: [Mujo.bin, "keys", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const data = root.parse(this.text);
                if (data)
                    root.binds = data.binds;
            }
        }
    }

    Process {
        id: netsLoader
        command: [Mujo.bin, "net", "scan", "--no-rescan", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const data = root.parse(this.text);
                if (data)
                    root.nets = data.networks;
            }
        }
    }

    // Connects to a new network. The password goes to mujo on its standard
    // input, never on a command line.
    Process {
        id: connector
        property string secret: ""
        stdinEnabled: true
        onStarted: {
            connector.write(connector.secret + "\n");
            connector.secret = "";
            connector.stdinEnabled = false;
        }
        onExited: connector.stdinEnabled = true
    }

    Process {
        id: indexer
        command: [Mujo.bin, "wall", "index"]
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
        command: [Mujo.bin, "launch", "list", "--json"]
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
        command: [Mujo.bin, "menu", "list", "--json"]
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
        command: [Mujo.bin, "wall", "list", "--json"]
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
                    anchors.centerIn: appIcon
                    text: root.mode === "apps" ? "\uf009" : root.mode === "clipboard" ? "\uf0ea" : root.mode === "keys" ? "\uf11c" : root.mode === "wifi" ? "\uf1eb" : root.mode === "calc" ? "\uf1ec" : "\uf054"
                    visible: entryRow.iconSource === "" && root.mode !== "emoji"
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
                        text: root.title(entryRow.modelData)
                        color: Tokens.textPrimary
                        elide: Text.ElideRight
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontMd
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: root.detail(entryRow.modelData)
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
            visible: root.results.length === 0 && root.passwordFor === ""
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.strip && root.walls.length === 0 ? "No images in the wallpaper folder (~/Pictures/Wallpapers)" : root.mode === "calc" ? (root.query.trim() === "" ? "Type a sum, e.g. 12 * 7 or 5 km in miles" : "...") : root.mode === "emoji" && root.emoji.length === 0 ? "The emoji list is missing (package unicode-emoji)" : root.mode === "wifi" && root.query === "" ? "Looking for networks..." : root.mode === "clipboard" && root.query === "" ? "The clipboard history is empty" : "Nothing matches"
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
                text: root.passwordFor !== "" ? "\uf023" : root.mode === "apps" ? "\uf002" : root.mode === "actions" ? "\uf054" : root.mode === "clipboard" ? "\uf0ea" : root.mode === "keys" ? "\uf11c" : root.mode === "wifi" ? "\uf1eb" : root.mode === "calc" ? "\uf1ec" : root.mode === "emoji" ? "\uf118" : "\uf03e"
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
                echoMode: root.passwordFor !== "" ? TextInput.Password : TextInput.Normal
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontMd

                onTextEdited: {
                    if (root.passwordFor !== "")
                        return;
                    if (root.mode === "apps" && text.startsWith(">")) {
                        Ui.launcherMode = "actions";
                        text = text.slice(1);
                    } else if (root.mode === "apps" && text.startsWith("=")) {
                        Ui.launcherMode = "calc";
                        text = text.slice(1);
                    }
                    root.query = text;
                }

                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    if (event.key === Qt.Key_Escape && root.passwordFor !== "") {
                        root.passwordFor = "";
                        input.text = "";
                    } else if (event.key === Qt.Key_Escape) {
                        Ui.closeAll();
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.choose();
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Right && root.strip || ctrl && event.key === Qt.Key_N || ctrl && event.key === Qt.Key_J) {
                        root.move(1);
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left && root.strip || ctrl && event.key === Qt.Key_P || ctrl && event.key === Qt.Key_K) {
                        root.move(-1);
                    } else if (event.key === Qt.Key_Tab && root.passwordFor === "" && (root.mode === "apps" || root.mode === "actions")) {
                        // Tab switches between apps and mujo commands.
                        root.setMode(root.mode === "apps" ? "actions" : "apps");
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
                text: root.passwordFor !== "" ? "Password for " + root.passwordFor + ", then Enter" : root.mode === "apps" ? "Search apps; Tab or > for mujo commands" : root.mode === "actions" ? "Search commands; Tab for apps" : root.mode === "clipboard" ? "Search the clipboard; Enter copies" : root.mode === "keys" ? "Search keybindings; Enter runs one" : root.mode === "wifi" ? "Search networks; Enter connects" : root.mode === "calc" ? "Calculate; Enter copies the result" : root.mode === "emoji" ? "Search emoji; Enter copies" : "Left and right to choose; Escape closes"
                color: Tokens.textMuted
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontMd
            }
        }
    }
}
