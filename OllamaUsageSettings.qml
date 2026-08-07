import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "dankOllamaUsage"

    StyledText {
        width: parent.width
        text: "Dank Ollama Usage"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Shows Ollama session & weekly usage percentages. Set your API key below."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "OLLAMA_API_KEY"
        label: "OLLAMA_API_KEY"
        description: "Authorization header value sent to https://ollama.com/api/usage"
        placeholder: "sk-..."
        defaultValue: ""
    }

    SliderSetting {
        settingKey: "updateInterval"
        label: "Update interval (seconds)"
        description: "How often the usage API is polled"
        defaultValue: 300
        minimum: 30
        maximum: 3600
        unit: "sec"
    }
}
