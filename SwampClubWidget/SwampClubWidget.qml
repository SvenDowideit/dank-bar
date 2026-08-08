import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property string apiKey: pluginData.SWAMP_API_KEY || ""
    property string username: pluginData.username || ""
    property string repoDir: pluginData.repoDir || ""
    property string serverUrl: pluginData.serverUrl || ""
    property int updateInterval: pluginData.updateInterval || 300

    property string tierName: ""
    property int tierOrdinal: 0
    property int tierVisual: 0
    property int streak: 0
    property int alltimeRank: 0
    property int score: 0
    property string status: ""

    property string nameStyleTextColor: Theme.primary
    property string nameStyleGlowColor: ""
    property int nameStyleGlowPx: 0

    function tierTextColor() {
        if (root.nameStyleGlowColor !== "") return root.nameStyleGlowColor
        return Theme.primary
    }

    property var workflows: []
    property var workflowRuns: ({})

    Timer {
        id: pollTimer
        interval: root.updateInterval * 1000
        running: root.apiKey !== "" && root.username !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Component {
        id: fetchCard
        Process {
            property string apiKey: ""
            property string username: ""
            command: ["curl", "-s", "-H", "Authorization: Bearer " + apiKey,
                      "https://swamp-club.com/api/v1/u/" + username + "/card"]
            stdout: SplitParser {
                onRead: line => root.cardBuffer += line
            }
            stderr: SplitParser {
                onRead: line => {
                    if (line.trim() !== "")
                        root.status = "card err: " + line.trim()
                }
            }
            onExited: exitCode => {
                if (exitCode !== 0) {
                    root.status = "card failed (exit " + exitCode + ")"
                } else {
                    try {
                        var obj = JSON.parse(root.cardBuffer)
                        root.tierName = obj.tierName || ""
                        root.tierOrdinal = obj.ordinal || 0
                        root.tierVisual = obj.tier || 0
                        root.score = obj.score || 0
                        root.status = ""
                        if (obj.nameStyle) {
                            root.nameStyleTextColor = obj.nameStyle.textClass || Theme.primary
                            root.nameStyleGlowColor = obj.nameStyle.glowColor || ""
                            root.nameStyleGlowPx = obj.nameStyle.glowPx || 0
                        } else {
                            root.nameStyleTextColor = Theme.primary
                            root.nameStyleGlowColor = ""
                            root.nameStyleGlowPx = 0
                        }
                    } catch (e) {
                        root.status = "card bad json"
                    }
                }
                root.cardBuffer = ""
                destroy()
            }
        }
    }

    Component {
        id: fetchLocate
        Process {
            property string apiKey: ""
            property string username: ""
            command: ["curl", "-s", "-H", "Authorization: Bearer " + apiKey,
                      "https://swamp-club.com/api/v1/leaderboard/locate?q=" + username]
            stdout: SplitParser {
                onRead: line => root.locateBuffer += line
            }
            stderr: SplitParser {
                onRead: line => {
                    if (line.trim() !== "")
                        root.status = "locate err: " + line.trim()
                }
            }
            onExited: exitCode => {
                if (exitCode !== 0) {
                    root.status = "locate failed (exit " + exitCode + ")"
                } else {
                    try {
                        var obj = JSON.parse(root.locateBuffer)
                        if (obj.boards) {
                            if (obj.boards.streaks) {
                                for (var i = 0; i < obj.boards.streaks.rows.length; i++) {
                                    var r = obj.boards.streaks.rows[i]
                                    if (r.isMatch) {
                                        root.streak = r.streak || 0
                                        break
                                    }
                                }
                            }
                            if (obj.boards.alltime) {
                                for (var j = 0; j < obj.boards.alltime.rows.length; j++) {
                                    var ar = obj.boards.alltime.rows[j]
                                    if (ar.isMatch) {
                                        root.alltimeRank = ar.rank || 0
                                        break
                                    }
                                }
                            }
                        }
                    } catch (e) {
                        root.status = "locate bad json"
                    }
                }
                root.locateBuffer = ""
                destroy()
            }
        }
    }

    function swampArgs() {
        var args = []
        if (root.repoDir !== "") {
            args.push("--repo-dir")
            args.push(root.repoDir)
        }
        if (root.serverUrl !== "") {
            args.push("--server")
            args.push(root.serverUrl)
        }
        return args
    }

    Component {
        id: fetchWorkflows
        Process {
            command: {
                var a = ["swamp", "workflow", "search", "--json"]
                return a.concat(root.swampArgs())
            }
            stdout: SplitParser {
                onRead: line => root.workflowsBuffer += line
            }
            stderr: SplitParser {
                onRead: line => {
                    if (line.trim() !== "")
                        root.status = "wf err: " + line.trim()
                }
            }
            onExited: exitCode => {
                if (exitCode !== 0) {
                    root.status = "wf search failed (exit " + exitCode + ")"
                } else {
                    try {
                        var obj = JSON.parse(root.workflowsBuffer)
                        if (obj.results) {
                            root.workflows = obj.results
                            for (var i = 0; i < obj.results.length; i++) {
                                root.fetchWorkflowRun(obj.results[i].name)
                            }
                        }
                    } catch (e) {
                        root.status = "wf bad json"
                    }
                }
                root.workflowsBuffer = ""
                destroy()
            }
        }
    }

    Component {
        id: fetchWorkflowRun
        Process {
            property string wfName: ""
            command: {
                var a = ["swamp", "workflow", "history", "get", wfName, "--json"]
                return a.concat(root.swampArgs())
            }
            stdout: SplitParser {
                onRead: line => root.runBuffer += line
            }
            stderr: SplitParser {
                onRead: line => {}
            }
            onExited: exitCode => {
                if (exitCode === 0) {
                    try {
                        var obj = JSON.parse(root.runBuffer)
                        var runs = root.workflowRuns
                        runs[wfName] = obj
                        root.workflowRuns = runs
                    } catch (e) {}
                }
                root.runBuffer = ""
                destroy()
            }
        }
    }

    Component {
        id: runWorkflow
        Process {
            property string wfName: ""
            command: {
                var a = ["swamp", "workflow", "run", wfName]
                return a.concat(root.swampArgs())
            }
            onExited: exitCode => {
                root.fetchWorkflowRunSingle(wfName)
                destroy()
            }
        }
    }

    property string cardBuffer: ""
    property string locateBuffer: ""
    property string workflowsBuffer: ""
    property string runBuffer: ""

    function fetchWorkflowRun(wfName) {
        var p = fetchWorkflowRun.createObject(root, { wfName: wfName })
        p.running = true
    }

    function fetchWorkflowRunSingle(wfName) {
        var p = fetchWorkflowRun.createObject(root, { wfName: wfName })
        p.running = true
    }

    function triggerWorkflow(wfName) {
        var p = runWorkflow.createObject(root, { wfName: wfName })
        p.running = true
    }

    function toggleDialog(globalPos) {
        root.hideTooltip()
        if (dialogLoader.item) {
            if (dialogLoader.item.visible) {
                dialogLoader.item.hide()
            } else {
                dialogLoader.item.show(globalPos)
            }
        }
    }

    function hideDialog() {
        if (dialogLoader.item) dialogLoader.item.hide()
    }

    function showTooltip(text, globalPos) {
        tooltipLoader.active = true;
        if (tooltipLoader.item) {
            const currentScreen = parentScreen || Screen;
            const tooltipX = globalPos.x + 10;
            const tooltipY = globalPos.y + barThickness;
            tooltipLoader.item.show(text, tooltipX, tooltipY, currentScreen);
        }
    }

    function hideTooltip() {
        if (tooltipLoader.item) tooltipLoader.item.hide();
        tooltipLoader.active = false;
    }

    function buildTooltipText() {
        var lines = [];
        lines.push(root.tierName + " " + root.tierOrdinal + "/10");
        if (root.alltimeRank > 0) lines.push("All-time rank: #" + root.alltimeRank);
        if (root.score > 0) lines.push("Score: " + root.score.toLocaleString());
        if (root.streak > 0) lines.push("Streak: " + root.streak + " days");
        return lines.join("\n");
    }

    function statusColor(s) {
        if (s === "succeeded") return Theme.primary
        if (s === "failed") return Theme.error
        if (s === "running") return "#fbbf24"
        if (s === "suspended") return "#fbbf24"
        return Theme.surfaceVariantText
    }

    function statusIcon(s) {
        if (s === "succeeded") return "\u2713"
        if (s === "failed") return "\u2717"
        if (s === "running") return "\u25b6"
        if (s === "suspended") return "\u23f8"
        return "?"
    }

    function formatDuration(ms) {
        if (!ms || ms <= 0) return ""
        if (ms < 1000) return ms + "ms"
        if (ms < 60000) return (ms / 1000).toFixed(1) + "s"
        var mins = Math.floor(ms / 60000)
        var secs = Math.floor((ms % 60000) / 1000)
        return mins + "m " + secs + "s"
    }

    function formatTime(iso) {
        if (!iso) return ""
        var d = new Date(iso)
        return d.toLocaleString(Qt.locale(), "hh:mm")
    }

    Component {
        id: multiLineTooltip
        PanelWindow {
            id: tip
            WlrLayershell.namespace: "dms:tooltip"
            property string text: ""
            property real targetX: 0
            property real targetY: 0
            property var targetScreen: null

            function show(t, x, y, screen) {
                text = t;
                targetScreen = screen ?? null;
                targetX = x;
                targetY = y;
                visible = true;
            }

            function hide() { visible = false; }

            screen: targetScreen
            implicitWidth: Math.min(400, Math.max(160, textContent.implicitWidth + Theme.spacingM * 2))
            implicitHeight: textContent.implicitHeight + Theme.spacingS * 2
            color: "transparent"
            visible: false
            WlrLayershell.layer: WlrLayershell.Overlay
            WlrLayershell.exclusiveZone: -1

            anchors { top: true; left: true }

            margins {
                left: {
                    const sw = targetScreen?.width ?? Screen.width;
                    return Math.round(Math.max(Theme.spacingS, Math.min(sw - implicitWidth - Theme.spacingS, targetX)));
                }
                top: {
                    const sh = targetScreen?.height ?? Screen.height;
                    return Math.round(Math.max(Theme.spacingS, Math.min(sh - implicitHeight - Theme.spacingS, targetY)));
                }
            }

            WindowBlur {
                targetWindow: tip
                blurX: 0; blurY: 0
                blurWidth: tip.visible ? tip.width : 0
                blurHeight: tip.visible ? tip.height : 0
                blurRadius: Theme.cornerRadius
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
                radius: Theme.cornerRadius
                border.width: BlurService.borderWidth
                border.color: BlurService.borderColor

                StyledText {
                    id: textContent
                    anchors.centerIn: parent
                    text: tip.text
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    width: Math.min(implicitWidth, 400 - Theme.spacingM * 2)
                }
            }
        }
    }

    Loader {
        id: tooltipLoader
        active: false
        sourceComponent: multiLineTooltip
    }

    Component {
        id: dialogComponent
        PanelWindow {
            id: dialog
            WlrLayershell.namespace: "dms:dialog"
            color: "transparent"
            visible: false
            WlrLayershell.layer: WlrLayershell.Overlay
            WlrLayershell.exclusiveZone: -1

            property int dialogW: 420
            property int dialogH: 520
            property real anchorX: 0
            property real anchorY: 0

            function show(globalPos) {
                if (globalPos) {
                    anchorX = globalPos.x
                    anchorY = globalPos.y
                }
                visible = true
            }

            function hide() { visible = false }

            screen: parentScreen ?? Screen
            implicitWidth: dialogW
            implicitHeight: dialogH

            anchors { top: true; left: true }

            margins {
                left: {
                    const sw = screen?.width ?? Screen.width
                    return Math.round(Math.max(Theme.spacingS, Math.min(sw - dialogW - Theme.spacingS, anchorX - dialogW / 2)))
                }
                top: {
                    const sh = screen?.height ?? Screen.height
                    return Math.round(Math.max(Theme.spacingS, Math.min(sh - dialogH - Theme.spacingS, anchorY + barThickness + Theme.spacingS)))
                }
            }

            WindowBlur {
                targetWindow: dialog
                blurX: 0; blurY: 0
                blurWidth: dialog.visible ? dialog.width : 0
                blurHeight: dialog.visible ? dialog.height : 0
                blurRadius: Theme.cornerRadius
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.92)
                radius: Theme.cornerRadius
                border.width: BlurService.borderWidth
                border.color: BlurService.borderColor

                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingM
                    spacing: Theme.spacingS

                    Row {
                        spacing: Theme.spacingS
                        Image {
                            source: "https://swamp-club.com/favicon.svg"
                            width: Theme.iconSize
                            height: Theme.iconSize
                            fillMode: Image.PreserveAspectFit
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: root.username
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Item { width: 1; height: 1 }
                        StyledText {
                            text: "\u2715"
                            font.pixelSize: Theme.fontSizeLarge
                            color: Theme.surfaceVariantText
                            anchors.verticalCenter: parent.verticalCenter
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.hideDialog()
                            }
                        }
                    }

                    Rectangle { height: 1; width: parent.width; color: Theme.withAlpha(Theme.surfaceVariantText, 0.2) }

                    StyledText {
                        visible: root.tierName !== ""
                        text: root.tierName + " " + root.tierOrdinal + "/10  \u2022  #" + root.alltimeRank + " all-time  \u2022  " + root.score.toLocaleString() + " pts  \u2022  " + root.streak + "d streak"
                        font.pixelSize: Theme.fontSizeSmall
                        color: root.tierTextColor()
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }

                    Rectangle { height: 1; width: parent.width; color: Theme.withAlpha(Theme.surfaceVariantText, 0.2) }

                    StyledText {
                        text: "Workflows"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }

                    Flickable {
                        id: wfFlick
                        width: parent.width
                        height: dialog.dialogH - 160
                        contentHeight: wfColumn.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: wfColumn
                            width: parent.width
                            spacing: Theme.spacingXS

                            Repeater {
                                model: root.workflows
                                delegate: Rectangle {
                                    width: wfColumn.width
                                    height: 36
                                    color: "transparent"
                                    radius: 4

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.spacingXS
                                        anchors.rightMargin: Theme.spacingXS
                                        spacing: Theme.spacingS

                                        StyledText {
                                            text: {
                                                var run = root.workflowRuns[modelData.name]
                                                if (run) return statusIcon(run.status)
                                                return "?"
                                            }
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: {
                                                var run = root.workflowRuns[modelData.name]
                                                if (run) return statusColor(run.status)
                                                return Theme.surfaceVariantText
                                            }
                                            width: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: modelData.name
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceText
                                            width: 100
                                            elide: Text.ElideRight
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: {
                                                var run = root.workflowRuns[modelData.name]
                                                if (run) return formatDuration(run.duration)
                                                return ""
                                            }
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            width: 60
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            text: {
                                                var run = root.workflowRuns[modelData.name]
                                                if (run && run.startedAt) return formatTime(run.startedAt)
                                                return ""
                                            }
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            width: 50
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Item { width: 1; height: 1 }

                                        Rectangle {
                                            width: 40; height: 24
                                            radius: 4
                                            color: mouseArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.2) : Theme.withAlpha(Theme.surfaceVariantText, 0.1)
                                            anchors.verticalCenter: parent.verticalCenter

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: "Run"
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.primary
                                            }

                                            MouseArea {
                                                id: mouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.triggerWorkflow(modelData.name)
                                            }
                                        }
                                    }
                                }
                            }

                            StyledText {
                                visible: root.workflows.length === 0
                                text: "No workflows found"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }
                }
            }
        }
    }

    Loader {
        id: dialogLoader
        active: true
        sourceComponent: dialogComponent
    }

    function refresh() {
        if (root.apiKey === "") {
            root.status = "set SWAMP_API_KEY"
            return
        }
        if (root.username === "") {
            root.status = "set username"
            return
        }
        var c = fetchCard.createObject(root, { apiKey: root.apiKey, username: root.username })
        c.running = true
        var l = fetchLocate.createObject(root, { apiKey: root.apiKey, username: root.username })
        l.running = true
        var w = fetchWorkflows.createObject(root, {})
        w.running = true
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: row.implicitWidth
            implicitHeight: row.implicitHeight

            Row {
                id: row
                spacing: Theme.spacingS

                Image {
                    source: "https://swamp-club.com/favicon.svg"
                    width: Theme.iconSize
                    height: Theme.iconSize
                    fillMode: Image.PreserveAspectFit
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    id: hTierText
                    visible: root.apiKey !== "" && root.username !== "" && root.tierName !== ""
                    text: root.tierName + " " + root.tierOrdinal + "/10"
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.tierTextColor()
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.apiKey !== "" && root.username !== "" && root.streak > 0
                    text: root.streak + "d streak"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.apiKey === "" || root.username === ""
                    text: "set API key & username"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.status !== "" && root.apiKey !== "" && root.username !== ""
                    text: "⚠"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.error
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onClicked: {
                    const globalPos = mapToItem(null, width / 2, height / 2);
                    root.toggleDialog(globalPos);
                }
                onEntered: {
                    if (dialogLoader.item && dialogLoader.item.visible) return
                    const globalPos = mapToItem(null, width / 2, height / 2);
                    root.showTooltip(root.buildTooltipText(), globalPos);
                }
                onExited: root.hideTooltip()
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: col.implicitWidth
            implicitHeight: col.implicitHeight

            Column {
                id: col
                spacing: Theme.spacingXS

                Image {
                    source: "https://swamp-club.com/favicon.svg"
                    width: Theme.iconSize
                    height: Theme.iconSize
                    fillMode: Image.PreserveAspectFit
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.apiKey !== "" && root.username !== "" && root.tierName !== ""
                    text: root.tierName
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.tierTextColor()
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.apiKey !== "" && root.username !== "" && root.tierOrdinal > 0
                    text: root.tierOrdinal + "/10"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.apiKey !== "" && root.username !== "" && root.streak > 0
                    text: root.streak + "d"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.apiKey === "" || root.username === ""
                    text: "set API key"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onClicked: {
                    const globalPos = mapToItem(null, width / 2, height / 2);
                    root.toggleDialog(globalPos);
                }
                onEntered: {
                    if (dialogLoader.item && dialogLoader.item.visible) return
                    const globalPos = mapToItem(null, width / 2, height / 2);
                    root.showTooltip(root.buildTooltipText(), globalPos);
                }
                onExited: root.hideTooltip()
            }
        }
    }
}
