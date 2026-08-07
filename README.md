# Dank Ollama Usage — DankMaterialShell bar widget

A single-config DankBar widget that shows the Ollama icon, then your
**session** and **weekly** usage percentages. It polls:

```
curl -H "Authorization: $OLLAMA_API_KEY" https://ollama.com/api/usage
```

and renders `limits.session.usage` and `limits.weekly.usage` as percentages
(usage values are fractions of 1.0, so `0.079` → `7.9%`).

## Files
- `plugin.json` — DMS widget manifest
- `OllamaUsageWidget.qml` — bar pill (horizontal + vertical)
- `OllamaUsageSettings.qml` — settings UI
- `ollama.svg` — llama glyph for the bar

## Single config value
`OLLAMA_API_KEY` — the Authorization header value sent to the API. Set it in
the plugin's settings panel (DMS Settings → Plugins → Dank Ollama Usage).
Optional `updateInterval` (seconds, default 300).

## Install
1. Copy this directory into DMS's plugin dir (e.g. `~/.config/DankMaterialShell/plugins/dank-ollama-usage/`)
```
mkdir -p ~/.config/DankMaterialShell/plugins/dank-ollama-usage/
cp * ~/.config/DankMaterialShell/plugins/dank-ollama-usage/
journalctl --user -fu dms.service
```
2. In DMS Settings → Plugins, **Scan for Plugins**, toggle it on
3. Add the pill to your DankBar layout
4. Set `OLLAMA_API_KEY` in its settings

## From the commandline, you can do the following:

see more info in https://danklinux.com/docs/dankmaterialshell/plugin-development

```
sven@x1yoga:~/src/claude-test/dank-bar$ dms ipc call plugins list
dankOllamaUsage [disabled]
sven@x1yoga:~/src/claude-test/dank-bar$ dms ipc call plugins reload dankOllamaUsage
PLUGIN_RELOAD_FAILED: dankOllamaUsage
```

## Sample output (from the API)
Given `{"limits":{"session":{"usage":0},"weekly":{"usage":0.079}}}`:
`🦙 0.0%  7.9%`
