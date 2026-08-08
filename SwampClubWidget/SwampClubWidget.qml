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
    property int updateInterval: pluginData.updateInterval || 300

    property string tierName: ""
    property int tierOrdinal: 0
    property int tierVisual: 0
    property int streak: 0
    property int alltimeRank: 0
    property int score: 0
    property string status: ""

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

    property string cardBuffer: ""
    property string locateBuffer: ""

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
                    visible: root.tierName !== ""
                    text: root.tierName + " " + root.tierOrdinal + "/10"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.streak > 0
                    text: root.streak + "d streak"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.status !== ""
                    text: "⚠"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.error
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: {
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
                    visible: root.tierName !== ""
                    text: root.tierName
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.tierOrdinal > 0
                    text: root.tierOrdinal + "/10"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.streak > 0
                    text: root.streak + "d"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: {
                    const globalPos = mapToItem(null, width / 2, height / 2);
                    root.showTooltip(root.buildTooltipText(), globalPos);
                }
                onExited: root.hideTooltip()
            }
        }
    }
}
