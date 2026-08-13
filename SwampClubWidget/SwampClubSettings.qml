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

    SecretSetting {
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

    StringSetting {
        settingKey: "repoDir"
        label: "Swamp repo directory (optional)"
        description: "Path to your Swamp repository. Leave empty to use SWAMP_REPO_DIR env var or CWD."
        placeholder: "/home/user/src/swamp-project"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "serverUrl"
        label: "Swamp serve URL (optional)"
        description: "Remote swamp serve instance (ws:// or http://). Leave empty for local repo."
        placeholder: "http://127.0.0.1:7766"
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
