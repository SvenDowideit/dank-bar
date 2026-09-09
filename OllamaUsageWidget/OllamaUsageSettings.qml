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

    SliderSetting {
        settingKey: "monthlyResetDay"
        label: "Monthly reset day (optional)"
        description: "Day of month your monthly usage resets (see ollama.com Settings > Billing). 0 = guess from the API's activity period."
        defaultValue: 0
        minimum: 0
        maximum: 31
        unit: "day"
    }
}
