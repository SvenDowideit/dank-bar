import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "dankSwampClub"

    StyledText {
        width: parent.width
        text: "Dank Swamp Club"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Shows your Swamp Club rank, tier, and streak. Set your API key and username below."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "SWAMP_API_KEY"
        label: "SWAMP_API_KEY"
        description: "Your Swamp Club API key (swamp_...). Create one at swamp-club.com Settings > Access Tokens."
        placeholder: "swamp_..."
        defaultValue: ""
    }

    StringSetting {
        settingKey: "username"
        label: "Username"
        description: "Your Swamp Club username (e.g. svendowideit)"
        placeholder: "username"
        defaultValue: ""
    }

    SliderSetting {
        settingKey: "updateInterval"
        label: "Update interval (seconds)"
        description: "How often the leaderboard API is polled"
        defaultValue: 300
        minimum: 30
        maximum: 3600
        unit: "sec"
    }
}
