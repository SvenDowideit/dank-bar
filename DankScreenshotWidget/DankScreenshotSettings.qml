import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "dankScreenshot"

    StyledText {
        width: parent.width
        text: "Dank Screenshot"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Click the widget to take a screenshot. The filename is pushed to the clipboard first, then the image on top (so the image is what pastes)."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SelectionSetting {
        settingKey: "mode"
        label: "Screenshot mode"
        description: "What to capture when the widget is clicked."
        defaultValue: "region"
        options: [
            { value: "region", label: "Region (select interactively)" },
            { value: "full", label: "Full screen (focused output)" },
            { value: "all", label: "All outputs combined" },
            { value: "window", label: "Focused window" }
        ]
    }

    StringSetting {
        settingKey: "dir"
        label: "Output directory (optional)"
        description: "Where to save the screenshot. Leave empty to use ~/Pictures/Screenshots."
        placeholder: "/home/user/Pictures/Screenshots"
        defaultValue: ""
    }
}
