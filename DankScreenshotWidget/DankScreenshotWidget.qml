import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Dank Screenshot bar widget.
// Click to take a screenshot. It pushes the screenshot's filename into the
// clipboard stack first, then the screenshot image on top of it — so the
// image is what gets pasted, with the filename one entry back in history.

PluginComponent {
    id: root

    property string mode: pluginData.mode || "region"
    property string dir: pluginData.dir || ""
    property string status: ""

    function defaultDir() {
        if (root.dir !== "")
            return root.dir
        return Paths.strip(Paths.pictures) + "/Screenshots"
    }

    function timestamp() {
        var d = new Date()
        function pad(n) { return n < 10 ? "0" + n : "" + n }
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) +
               "_" + pad(d.getHours()) + "-" + pad(d.getMinutes()) + "-" + pad(d.getSeconds())
    }

    function trigger() {
        var name = "dms-screenshot-" + root.timestamp() + ".png"
        var fullPath = root.defaultDir() + "/" + name

        // 1. Push the filename into the clipboard stack first, then take the
        //    screenshot once that copy has finished (so the image lands on
        //    top of the filename).
        var copyName = copyNameProcess.createObject(root, {
            text: fullPath,
            mode: root.mode,
            name: name,
            dir: root.defaultDir()
        })
        copyName.running = true
    }

    Component {
        id: copyNameProcess
        Process {
            property string text: ""
            property string mode: "region"
            property string name: ""
            property string dir: ""
            command: ["dms", "clipboard", "copy", text]
            onExited: exitCode => {
                if (exitCode !== 0) {
                    root.status = "copy failed (exit " + exitCode + ")"
                } else {
                    var shot = shotProcess.createObject(root, { mode: mode, name: name, dir: dir })
                    shot.running = true
                }
                destroy()
            }
        }
    }

    Component {
        id: shotProcess
        Process {
            property string mode: "region"
            property string name: ""
            property string dir: ""
            command: ["dms", "screenshot", mode, "--filename", name, "--dir", dir]
            onExited: exitCode => {
                if (exitCode !== 0)
                    root.status = "screenshot failed (exit " + exitCode + ")"
                destroy()
            }
        }
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

    horizontalBarPill: Component {
        Item {
            implicitWidth: row.implicitWidth
            implicitHeight: row.implicitHeight

            Row {
                id: row
                spacing: Theme.spacingS

                DankIcon {
                    name: "screenshot"
                    size: Theme.iconSize
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "Screenshot"
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
                acceptedButtons: Qt.LeftButton
                onClicked: root.trigger()
                onEntered: {
                    const globalPos = mapToItem(null, width / 2, height / 2);
                    root.showTooltip("Take a " + root.mode + " screenshot\n(filename + image → clipboard)", globalPos);
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

                DankIcon {
                    name: "screenshot"
                    size: Theme.iconSize
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: "Shot"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton
                onClicked: root.trigger()
                onEntered: {
                    const globalPos = mapToItem(null, width / 2, height / 2);
                    root.showTooltip("Take a " + root.mode + " screenshot\n(filename + image → clipboard)", globalPos);
                }
                onExited: root.hideTooltip()
            }
        }
    }
}
