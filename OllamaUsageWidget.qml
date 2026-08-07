import QtQuick
import Quickshell
import Quickshell.Io
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
    property string status: "" // error/status line

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
                            root.status = ""
                        }
                    } catch (e) {
                        root.status = "bad json"
                    }
                }
                root.buffer = ""
                root.status = root.status  // touch reactive status
                destroy()
            }
        }
    }

    property string buffer: ""

    function refresh() {
        if (root.apiKey === "") {
            root.status = "set OLLAMA_API_KEY"
            return
        }
        var p = fetchProcess.createObject(root, { apiKey: root.apiKey })
        p.running = true
    }

    // --- DankBar rendering -------------------------------------------------

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            Image {
                id: icon
                source: "https://ollama.com/public/ollama.png"
                width: Theme.iconSize
                height: Theme.iconSize
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.sessionPct.toFixed(1) + "%"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: root.weeklyPct.toFixed(1) + "%"
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
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS

            Image {
                id: vicon
                source: "https://ollama.com/public/ollama.png"
                width: Theme.iconSize
                height: Theme.iconSize
                fillMode: Image.PreserveAspectFit
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.sessionPct.toFixed(1) + "%"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.primary
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                text: root.weeklyPct.toFixed(1) + "%"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
