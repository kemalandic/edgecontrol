# AI-Assisted Plugin Development

Copy the prompt below into Claude, ChatGPT, or any AI assistant to generate a working EdgeControl plugin.

## The Prompt

```
I need you to create an EdgeControl plugin. EdgeControl is a macOS dashboard app for the CORSAIR XENEON EDGE (2560x720 touchscreen). Plugins are HTML/JS widgets rendered in WKWebView.

A plugin is a folder named {name}.ecplugin containing:
- manifest.json — plugin metadata, permissions, widget definitions
- One or more .html files — widget UI

MANIFEST FORMAT:
{
  "id": "com.example.{id}",
  "name": "{Name}",
  "version": "1.0.0",
  "author": "{Author}",
  "permissions": [...],
  "widgets": [{
    "id": "{widgetId}",
    "name": "{Widget Name}",
    "icon": "{sf-symbol}",
    "htmlFile": "{file}.html",
    "supportedSizes": { "min": [minW, minH], "max": [maxW, maxH] },
    "defaultSize": [w, h],
    "refreshInterval": 2.0
  }]
}

PERMISSIONS (data): system-metrics, temperature, network, processes, media, bluetooth, audio, weather, disk-io
PERMISSIONS (actions): notifications, open-url, clipboard, storage, network-access

JS SDK:
- edgecontrol.on('update', fn(data)) — periodic data push
- edgecontrol.on('ready', fn()) — DOM ready
- edgecontrol.on('resize', fn(size)) — widget resized
- edgecontrol.on('themeChange', fn(theme)) — theme changed
- edgecontrol.on('visibilityChange', fn(visible)) — widget shown/hidden on page swipe
- edgecontrol.notify(title, body) — macOS notification (needs "notifications")
- edgecontrol.openURL(url) — open browser (needs "open-url")
- edgecontrol.copyToClipboard(text) — clipboard (needs "clipboard")
- edgecontrol.storage.get/set/remove(key) — persistent storage, returns Promise (needs "storage")
- edgecontrol.getWidgetSize() — {width, height, pixelWidth, pixelHeight}

DATA ACCESSORS: edgecontrol.system, .temperature, .network, .processes, .media, .weather, .audio, .bluetooth, .diskIO, .theme, .config

CSS VARIABLES (auto-injected, live-updated):
--ec-accent, --ec-widget-primary, --ec-widget-secondary, --ec-widget-tertiary
--ec-bg-1, --ec-bg-2, --ec-bg-3, --ec-card-bg
--ec-text-primary, --ec-text-secondary, --ec-text-tertiary, --ec-border
--ec-font-family, --ec-font-scale, --ec-corner-radius, --ec-widget-gap
--ec-font-title (18px), --ec-font-value (28px), --ec-font-label (14px)
--ec-font-caption (11px), --ec-font-body (16px), --ec-font-micro (10px)

RULES:
- Body background must be transparent (widget card provides background)
- Always use var(--ec-*) for colors, never hardcode
- Use semantic font sizes: var(--ec-font-title), var(--ec-font-value), var(--ec-font-label), var(--ec-font-caption), var(--ec-font-body), var(--ec-font-micro)
- Grid is 20x6 cells, each ~128x120px. Min widget: 2x2
- refreshInterval minimum is 1.0 second

Now create a plugin that: [DESCRIBE YOUR PLUGIN HERE]
```

## Example Prompts

### System Dashboard
> Now create a plugin that shows CPU usage as a circular gauge with memory usage below it. Use the system-metrics permission. Make it work from 2x2 to 4x4. Use smooth CSS animations for the gauge.

### Network Monitor with Alerts
> Now create a plugin that shows download/upload speeds with a live sparkline chart. When download speed drops below 1 MB/s, send a notification. Needs network and notifications permissions. Default size 4x2.

### Pomodoro Timer with Persistence
> Now create a plugin that implements a pomodoro timer (25 min work, 5 min break). Store completed pomodoros count in persistent storage. Show a notification when each interval ends. Needs storage and notifications. Default size 3x2.

## Testing Your Plugin

1. Save the generated files in a folder named `your-plugin.ecplugin`
2. Open EdgeControl Settings → Plugins → Install Plugin
3. Select the folder or zip it first
4. The widget appears in the Widget Catalog under "Plugin"
5. Place it on a page and verify it works
6. Try changing the theme — colors should update automatically
7. Try resizing — check if layout adapts

## Tips

- Start with a simple plugin and iterate
- Test with different themes (OLED Black, Ember, Arctic)
- Test at different sizes (2x2 minimum, larger sizes)
- Check the browser console for errors (right-click → Inspect Element in dev builds)
- Use `edgecontrol.on('ready', ...)` to initialize — don't run code at top level
