# Dank Ollama Usage — DankMaterialShell bar widget

## Screenshot

![Ollama Usage widget in the DankBar](screenshot.png)

A single-config DankBar widget that shows the Ollama icon, then your
**session** and **weekly** usage percentages (legacy Pro/Max plans) or your
**monthly** usage percentage (new monthly Pro/Max plans). It polls:

```
curl -H "Authorization: $OLLAMA_API_KEY" https://ollama.com/api/usage
```

and renders `limits.session.usage` + `limits.weekly.usage` (legacy plans) or
`limits.monthly.usage` (new monthly plans) as percentages (usage values are
fractions of 1.0, so `0.079` → `7.9%`).

## Plan support

Ollama's `/api/usage` response shape depends on which plan the account is on:

- **Legacy Pro/Max** (subscribed before the Aug 2026 pricing change) return
  `limits.session` (5h window) and `limits.weekly` (7d window). The widget
  shows both percentages and their reset countdowns, exactly as before.
- **New monthly Pro/Max** return a single `limits.monthly` bucket (a monthly
  credit pool) plus an `activity` object with `cost` and a `period` of type
  `last_4_weeks`. The widget shows the monthly percentage and the per-model
  request counts, plus the 4-week activity cost in the tooltip. The monthly
  billing reset date is **not** exposed by the API (the `activity.period` is a
  rolling cost window ending now, not the billing period), so the reset
  countdown is derived from `monthlyResetDay`, falling back to a guess from
  `activity.period.starting_at` (see below).

The widget auto-detects the shape from the response, so the same build keeps
working for both old and new plans — no config change needed when you switch.

## Files
- `plugin.json` — DMS widget manifest
- `OllamaUsageWidget.qml` — bar pill (horizontal + vertical)
- `OllamaUsageSettings.qml` — settings UI
- `ollama.svg` — local llama glyph (fallback; not currently used)

## Single config value
`OLLAMA_API_KEY` — the Authorization header value sent to the API. Set it in
the plugin's settings panel (DMS Settings → Plugins → Dank Ollama Usage).
Optional `updateInterval` (seconds, default 300).

Optional `monthlyResetDay` (1–31, default 0 = auto) — the day of month your
monthly usage resets, shown on ollama.com → Settings → Billing. When set, the
widget shows a "resets in Xd Xh" countdown for monthly plans. When left at 0,
the widget guesses the day from `activity.period.starting_at` (a heuristic —
that field is a rolling "last_4_weeks" window, so set the day explicitly if the
countdown looks wrong).

## Icon
The bar icon loads a remote PNG from `https://ollama.com/public/ollama.png` in
`OllamaUsageWidget.qml` (`Image.source`). It needs network access (the `network`
permission) and will be blank until it loads. `ollama.svg` is kept as a local
fallback — to use it, swap `source:` back to `"ollama.svg"`. Note a trailing
comma after the `source:` value will break QML compile (`Expected token ','`).

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

## Reloading after editing QML

The Quickshell runtime (`qs`) caches the compiled QML component **in memory** and
does **not** invalidate it when you edit the file. `dms ipc call plugins reload`
can also fail because of an unrelated DMS registry issue (see below). After
fixing a compile error, the reliable way to force a fresh load is to restart the
whole shell service:

```
systemctl --user restart dms.service
```

Then watch it come up without a QML component error:

```
journalctl --user -fu dms.service
# expect: DankBar: Plugin loaded: dankOllamaUsage
```

If you see `Non-existent attached object` at some line, the QML uses an attached
property (`Foo.text`) of a type (`Foo`) that isn't a known type in this
Quickshell/DMS environment — e.g. `ToolTip.text` isn't supported here. Remove it
(or use a custom `MouseArea`/popup instead).

Note: `dms ipc call plugins reload` can return `PLUGIN_RELOAD_FAILED` because
DMS's own registry clone fails with `failed to re-clone registry: permission
denied` on `/tmp/dankdots-plugin-registry/.git/objects/pack/*` (pack files end
up `-r--r--r--`, owned by the user). That's unrelated to your plugin and blocks
plugin *listing* via IPC — a full `systemctl --user restart dms.service` still
loads plugins fine.


## Session reset estimate
The 5-hour **session** quota is a rolling window, and the `/api/usage` response
does **not** expose a session period/reset timestamp (`limits.session` carries
only `usage` and `models`). The widget therefore estimates the time until the
session resets:

- It records when it first observed the session active, capping the estimate at
  **5 hours** from that point.
- Once requests stop arriving, it measures the request-count expiry rate between
  polls and linearly extrapolates when the window drains to zero, refining the
  countdown.
- A full reset is detected when usage drops to ~0, which clears the timer.

The estimate appears as `~Xh Ym` (e.g. `~4h 12m`) in the bar pill and as
`Session resets in ~Xh Ym` in the tooltip. Lower `updateInterval` (min 30s)
improves the estimate's accuracy — at the default 300s it updates every 5 minutes.

# development docs:

https://danklinux.com/docs/dankmaterialshell/plugin-development
