import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Dank Ollama Usage bar widget.
// Single config value: OLLAMA_API_KEY (the Authorization header sent to the API).
// Pulls limits.session.usage and limits.weekly.usage from
//   curl -H "Authorization: $OLLAMA_API_KEY" https://ollama.com/api/usage
// and renders them as percentages (usage values are fractions of 1.0).

PluginComponent {
    id: root

    property string apiKey: pluginData.OLLAMA_API_KEY || ""
    property int updateInterval: pluginData.updateInterval || 300

    property real sessionPct: 0
    property real weeklyPct: 0
    property string status: ""
    property var sessionModels: []
    property var weeklyModels: []
    property string timeUntilReset: ""
    property string sessionTimeUntilReset: ""

    // Poll the usage API every updateInterval seconds.
    Timer {
        id: pollTimer
        interval: root.updateInterval * 1000
        running: root.apiKey !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // One-shot curl for a single fetch.
    Component {
        id: fetchProcess
        Process {
            property string apiKey: ""
            command: ["curl", "-s", "-H", "Authorization: " + apiKey,
                      "https://ollama.com/api/usage"]
            stdout: SplitParser {
                onRead: line => root.buffer += line
            }
            stderr: SplitParser {
                onRead: line => {
                    if (line.trim() !== "")
                        root.status = "curl error: " + line.trim()
                }
            }
            onExited: exitCode => {
                if (exitCode !== 0) {
                    root.status = "curl failed (exit " + exitCode + ")"
                } else {
                    try {
                        var obj = JSON.parse(root.buffer)
                        if (obj.limits) {
                            root.sessionPct = obj.limits.session.usage * 100
                            root.weeklyPct = obj.limits.weekly.usage * 100
                            root.sessionModels = obj.limits.session.models || []
                            root.weeklyModels = obj.limits.weekly.models || []
                            root.status = ""
                            root.sessionTimeUntilReset = root.formatReset(root.secondsUntilSessionReset())
                            root.timeUntilReset = root.formatReset(root.secondsUntilWeeklyReset())
                        }
                    } catch (e) {
                        root.status = "bad json"
                    }
                }
                root.buffer = ""
                root.status = root.status
                destroy()
            }
        }
    }

    property string buffer: ""

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
        lines.push("Session: " + root.sessionPct.toFixed(1) + "%");
        for (var i = 0; i < root.sessionModels.length; i++) {
            var m = root.sessionModels[i];
            lines.push("  " + m.name + " (" + m.request_count + " reqs)");
        }
        lines.push("Weekly: " + root.weeklyPct.toFixed(1) + "%");
        for (var j = 0; j < root.weeklyModels.length; j++) {
            var wm = root.weeklyModels[j];
            lines.push("  " + wm.name + " (" + wm.request_count + " reqs)");
        }
        lines.push("Session resets in " + root.formatReset(root.secondsUntilSessionReset()));
        lines.push("Weekly resets in " + root.formatReset(root.secondsUntilWeeklyReset()));
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
            root.status = "set OLLAMA_API_KEY"
            return
        }
        var p = fetchProcess.createObject(root, { apiKey: root.apiKey })
        p.running = true
    }

    // Session resets happen at the same wall-clock time for everyone: every
    // 5h (18000s), aligned to the epoch. Weekly resets every 7d (604800s),
    // anchored 4 days into the week cycle. So both can be computed exactly.
    function secondsUntilSessionReset() {
        var epoch = Math.floor(Date.now() / 1000)
        return 18000 - (epoch % 18000)
    }

    function secondsUntilWeeklyReset() {
        var epoch = Math.floor(Date.now() / 1000)
        return 604800 - (((epoch - 4 * 86400) % 604800 + 604800) % 604800)
    }

    function formatReset(sec) {
        var s = Math.max(0, Math.ceil(sec))
        var d = Math.floor(s / 86400)
        var h = Math.floor((s % 86400) / 3600)
        var m = Math.floor((s % 3600) / 60)
        if (d >= 1) return d + "d " + h + "h " + m + "m"
        if (h >= 1) return h + "h " + m + "m"
        if (m >= 1) return m + "m"
        return "now"
    }

    // --- DankBar rendering -------------------------------------------------

    horizontalBarPill: Component {
        Item {
            implicitWidth: row.implicitWidth
            implicitHeight: row.implicitHeight

            Row {
                id: row
                spacing: Theme.spacingS

                Image {
                    id: icon
                    //source: "https://ollama.com/public/ollama.png"
                    source: "https://mintcdn.com/ollama-9269c548/XefrxzvUktkk84RL/images/logo-dark.png?fit=max&auto=format&n=XefrxzvUktkk84RL&q=85&s=c214b467f5623414c31d4e05c66110fb"
                    width: Theme.iconSize
                    height: Theme.iconSize
                    fillMode: Image.PreserveAspectFit
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.apiKey !== ""
                    text: root.sessionPct.toFixed(1) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.apiKey !== ""
                    text: root.weeklyPct.toFixed(1) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.apiKey !== "" && root.sessionTimeUntilReset !== "" &&
                             root.sessionTimeUntilReset !== "reset" && root.sessionTimeUntilReset !== "now"
                    text: root.sessionTimeUntilReset
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.apiKey === ""
                    text: "set OLLAMA_API_KEY"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.status !== "" && root.apiKey !== ""
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
                    id: vicon
                    //source: "https://ollama.com/public/ollama.png"
                    source: "https://mintcdn.com/ollama-9269c548/XefrxzvUktkk84RL/images/logo-dark.png?fit=max&auto=format&n=XefrxzvUktkk84RL&q=85&s=c214b467f5623414c31d4e05c66110fb"
                    width: Theme.iconSize
                    height: Theme.iconSize
                    fillMode: Image.PreserveAspectFit
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.apiKey !== ""
                    text: root.sessionPct.toFixed(1) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.apiKey !== ""
                    text: root.weeklyPct.toFixed(1) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.apiKey !== "" && root.sessionTimeUntilReset !== "" &&
                             root.sessionTimeUntilReset !== "reset" && root.sessionTimeUntilReset !== "now"
                    text: root.sessionTimeUntilReset
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.apiKey === ""
                    text: "set API key"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
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
