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
// Pulls usage from:
//   curl -H "Authorization: $OLLAMA_API_KEY" https://ollama.com/api/usage
// and renders it as a percentage (usage values are fractions of 1.0).
//
// Supports both plan shapes:
//   - Legacy Pro/Max: limits.session (5h) + limits.weekly (7d)
//   - New monthly Pro/Max: limits.monthly (single credit pool). The monthly
//     reset date is not exposed by the API (activity.period is a rolling
//     "last_4_weeks" cost window), so no reset countdown is shown for it.

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

    // Peak pricing for the deepseek models: 12:00-18:00 UTC, Monday-Friday.
    // Tracked live so the pill can show a $$ badge and the tooltip can render
    // the window in the user's local time.
    property bool peakPricing: false

    // Plan detection: "legacy" (session + weekly buckets) or "monthly"
    // (a single monthly bucket). The new monthly Pro/Max plans replace the
    // old 5h session + 7d weekly windows with a monthly credit pool.
    property string planType: "legacy"
    property real monthlyPct: 0
    property var monthlyModels: []
    property string activityCost: ""        // activity.cost (last 4 weeks)
    property string periodStartingAt: ""     // activity.period.starting_at
    property int monthlyResetDay: parseInt(pluginData.monthlyResetDay) || 0
    property string monthlyTimeUntilReset: ""

    // Poll the usage API every updateInterval seconds.
    Timer {
        id: pollTimer
        interval: root.updateInterval * 1000
        running: root.apiKey !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Re-evaluate peak pricing every minute so the badge flips at the exact
    // UTC boundary without waiting for the next API poll.
    Timer {
        id: peakTimer
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.peakPricing = root.isPeakPricing()
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
                            var lim = obj.limits
                            // New monthly plan: a "monthly" bucket replaces the
                            // legacy session/weekly windows.
                            if (lim.monthly) {
                                root.planType = "monthly"
                                root.monthlyPct = lim.monthly.usage * 100
                                root.monthlyModels = lim.monthly.models || []
                            } else {
                                root.planType = "legacy"
                            }
                            // Legacy buckets (read defensively if still present).
                            if (lim.session) {
                                root.sessionPct = lim.session.usage * 100
                                root.sessionModels = lim.session.models || []
                            }
                            if (lim.weekly) {
                                root.weeklyPct = lim.weekly.usage * 100
                                root.weeklyModels = lim.weekly.models || []
                            }
                            // Activity: cost of the last 4 weeks (informational),
                            // plus the period start, used as a heuristic for the
                            // monthly reset day when monthlyResetDay is unset.
                            if (obj.activity) {
                                root.activityCost = obj.activity.cost || ""
                                if (obj.activity.period) {
                                    root.periodStartingAt = obj.activity.period.starting_at || ""
                                }
                            }
                            root.status = ""
                            root.sessionTimeUntilReset = root.formatReset(root.secondsUntilSessionReset())
                            root.timeUntilReset = root.formatReset(root.secondsUntilWeeklyReset())
                            var msec = root.secondsUntilMonthlyReset()
                            root.monthlyTimeUntilReset = msec < 0 ? "" : root.formatReset(msec)
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

    // Peak pricing applies to the deepseek models between 12:00 and 18:00 UTC,
    // Monday to Friday. Compare in UTC regardless of the machine's timezone.
    function isPeakPricing() {
        var now = new Date()
        var day = now.getUTCDay()             // 0 = Sunday, 6 = Saturday
        if (day === 0 || day === 6) return false
        var hour = now.getUTCHours()
        return hour >= 12 && hour < 18
    }

    // Render a UTC time-of-day as the equivalent local "HH:MM" string, using
    // today's date so the local timezone offset (incl. DST) is reflected.
    function utcToLocalTime(utcHour) {
        var d = new Date()
        d.setUTCHours(utcHour, 0, 0, 0)
        return Qt.formatTime(d, "HH:mm")
    }

    // Tooltip line describing the peak window in the user's local time.
    function peakPricingLine() {
        var start = root.utcToLocalTime(12)
        var end = root.utcToLocalTime(18)
        var prefix = root.peakPricing ? "Peak pricing now ($$)" : "Peak pricing"
        return prefix + ": " + start + "–" + end + " local, Mon–Fri"
    }

    function buildTooltipText() {
        var lines = [];
        lines.push(root.peakPricingLine());
        if (root.planType === "monthly") {
            lines.push("Monthly: " + root.monthlyPct.toFixed(1) + "%");
            for (var i = 0; i < root.monthlyModels.length; i++) {
                var m = root.monthlyModels[i];
                lines.push("  " + m.name + " (" + m.request_count + " reqs)");
            }
            if (root.activityCost !== "") lines.push("Activity cost (4wk): $" + parseFloat(root.activityCost).toFixed(2));
            if (root.monthlyTimeUntilReset !== "") lines.push("Monthly resets in " + root.monthlyTimeUntilReset);
        } else {
            lines.push("Session: " + root.sessionPct.toFixed(1) + "%");
            for (var j = 0; j < root.sessionModels.length; j++) {
                var sm = root.sessionModels[j];
                lines.push("  " + sm.name + " (" + sm.request_count + " reqs)");
            }
            lines.push("Weekly: " + root.weeklyPct.toFixed(1) + "%");
            for (var k = 0; k < root.weeklyModels.length; k++) {
                var wm = root.weeklyModels[k];
                lines.push("  " + wm.name + " (" + wm.request_count + " reqs)");
            }
            lines.push("Session resets in " + root.formatReset(root.secondsUntilSessionReset()));
            lines.push("Weekly resets in " + root.formatReset(root.secondsUntilWeeklyReset()));
        }
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

    // Monthly reset countdown. The API doesn't expose the reset date, so the
    // day-of-month comes from the optional monthlyResetDay setting, falling
    // back to the day-of-month of activity.period.starting_at (a heuristic —
    // that field is a rolling "last_4_weeks" window, so it's only correct if
    // it happens to be billing-anchored). Returns -1 when no day is known.
    function secondsUntilMonthlyReset() {
        var day = root.monthlyResetDay
        if (day <= 0 || day > 31) day = root.derivedResetDay()
        if (day <= 0 || day > 31) return -1
        var now = new Date()
        var reset = new Date(now.getFullYear(), now.getMonth(), day)
        if (reset.getTime() <= now.getTime()) {
            reset = new Date(now.getFullYear(), now.getMonth() + 1, day)
        }
        return Math.max(0, (reset.getTime() - now.getTime()) / 1000)
    }

    // Day-of-month of activity.period.starting_at (UTC), used as a fallback
    // when monthlyResetDay is unset. Returns 0 when unavailable.
    function derivedResetDay() {
        if (root.periodStartingAt === "") return 0
        var d = new Date(root.periodStartingAt)
        if (isNaN(d.getTime())) return 0
        return d.getUTCDate()
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
                    visible: root.apiKey !== "" && root.planType === "legacy"
                    text: root.sessionPct.toFixed(1) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.apiKey !== "" && root.planType === "monthly"
                    text: root.monthlyPct.toFixed(1) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.apiKey !== "" && root.planType === "monthly" && root.monthlyTimeUntilReset !== ""
                    text: root.monthlyTimeUntilReset
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.apiKey !== "" && root.planType === "legacy"
                    text: root.weeklyPct.toFixed(1) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.apiKey !== "" && root.planType === "legacy" && root.sessionTimeUntilReset !== "" &&
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
                    visible: root.peakPricing
                    text: "$$"
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                    color: Theme.error
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
                    visible: root.apiKey !== "" && root.planType === "legacy"
                    text: root.sessionPct.toFixed(1) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.apiKey !== "" && root.planType === "monthly"
                    text: root.monthlyPct.toFixed(1) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.primary
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.apiKey !== "" && root.planType === "monthly" && root.monthlyTimeUntilReset !== ""
                    text: root.monthlyTimeUntilReset
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.apiKey !== "" && root.planType === "legacy"
                    text: root.weeklyPct.toFixed(1) + "%"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.apiKey !== "" && root.planType === "legacy" && root.sessionTimeUntilReset !== "" &&
                             root.sessionTimeUntilReset !== "reset" && root.sessionTimeUntilReset !== "now"
                    text: root.sessionTimeUntilReset
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.peakPricing
                    text: "$$"
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                    color: Theme.error
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
