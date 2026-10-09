# Manifest Reference

Every plugin requires a `manifest.json` in the root of its `.ecplugin` bundle.

## Full Example

```json
{
  "id": "com.example.my-plugin",
  "name": "My Plugin",
  "version": "1.2.0",
  "author": "John Doe",
  "description": "A cool dashboard widget",
  "homepage": "https://github.com/john/my-plugin",
  "icon": "bolt.fill",
  "minAppVersion": "2.0.0",
  "permissions": ["system-metrics", "temperature", "notifications", "network-access"],
  "allowedDomains": ["api.github.com"],
  "widgets": [
    {
      "id": "gauge",
      "name": "CPU Gauge",
      "description": "Displays CPU usage as a gauge",
      "icon": "gauge.high",
      "htmlFile": "gauge.html",
      "supportedSizes": { "min": [2, 2], "max": [6, 6] },
      "defaultSize": [3, 3],
      "refreshInterval": 1.0,
      "configSchema": [
        {
          "key": "showLabel",
          "label": "Show Label",
          "type": "boolean",
          "default": true
        }
      ]
    }
  ]
}
```

## Top-Level Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `id` | String | **Yes** | — | Unique reverse-domain ID (e.g. `com.example.my-plugin`) |
| `name` | String | **Yes** | — | Display name |
| `version` | String | **Yes** | — | Semantic version (e.g. `1.2.0`) |
| `author` | String | **Yes** | — | Author name |
| `description` | String | No | `null` | Short description |
| `homepage` | String | No | `null` | URL to plugin homepage or repo |
| `icon` | String | No | `null` | SF Symbol name for plugin list icon |
| `minAppVersion` | String | No | `null` | Minimum EdgeControl version required |
| `permissions` | [String] | No | `[]` | List of permission identifiers |
| `allowedDomains` | [String] | No | `null` | Whitelisted domains for `network-access` |
| `widgets` | [Object] | **Yes** | — | Array of widget definitions |
| `menuItems` | [Object] | No | `null` | Items added to EdgeControl's menu bar menu (below) |

## Menu Items

A plugin whose settings or companion app live outside the dashboard can add items to EdgeControl's menu bar menu, between Settings… and Quit. Each item opens one thing when chosen:

```json
"menuItems": [
  { "title": "Edit Decks…", "openApp": "com.example.my-plugin-helper" },
  { "title": "My Plugin Help", "openURL": "https://example.com/help" }
]
```

| Field | Type | Description |
|-------|------|-------------|
| `title` | String | The item's title, up to 60 characters |
| `openApp` | String | Bundle identifier of an app to open. It must be from the plugin's own developer: its first two parts must match the plugin `id`'s (`com.example.…` for `com.example.my-plugin`). If the app is already running it's asked to reopen, which is when an app shows its window. The item is dimmed while the app isn't installed. |
| `openURL` | String | An `http` or `https` page to open instead |

Items from disabled plugins, and items that ask for anything else, don't appear.

## Widget Definition Fields

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `id` | String | **Yes** | — | Widget ID within this plugin |
| `name` | String | **Yes** | — | Display name |
| `description` | String | No | `null` | Short description |
| `icon` | String | No | `"puzzlepiece.extension"` | SF Symbol name |
| `htmlFile` | String | **Yes** | — | Relative path to HTML file in bundle |
| `supportedSizes` | Object | **Yes** | — | `{ "min": [w, h], "max": [w, h] }` grid cells |
| `defaultSize` | [Int] | **Yes** | — | `[width, height]` in grid cells |
| `refreshInterval` | Number | No | `2.0` | Data push interval in seconds (minimum: 1.0) |
| `configSchema` | [Object] | No | `null` | User-configurable settings |

## Config Schema Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `key` | String | **Yes** | Config key name |
| `label` | String | **Yes** | Display label in Settings UI |
| `type` | String | **Yes** | `"boolean"`, `"number"`, `"string"`, `"color"`, `"select"`, `"button"` |
| `default` | Any | **Yes**, except for `"button"` | Default value |
| `options` | [String] | No | Options for `"select"` type |
| `openApp`, `openURL` | String | For `"button"` | What the button opens, by the same rules as a [menu item](#menu-items)'s. A button that asks for anything else isn't shown. |
| `showWhen` | Object | No | Shows the field only while another field has one of some values: `{ "key": "mode", "is": "Deck" }`, or `"is": ["Deck", "Manual"]`. A field that isn't set yet counts as its default. |

A button holds no value. It opens a companion app or a page from the widget's settings, such as an editor for something too fiddly for the dashboard's touch screen:

```json
{ "key": "editDecks", "label": "Edit Decks…", "type": "button",
  "openApp": "com.example.my-plugin-helper",
  "showWhen": { "key": "mode", "is": "Deck" } }
```

Versions of EdgeControl from before buttons show one as an empty text field, and refuse a manifest whose button has no `default`, so give it `"default": ""` if your plugin must load there too.

## Permission Identifiers

**Data:** `system-metrics`, `temperature`, `network`, `processes`, `media`, `bluetooth`, `audio`, `weather`, `disk-io`

**Actions:** `notifications`, `open-url`, `clipboard`, `storage`, `network-access`

## Grid Sizing

The dashboard uses a 20x6 grid (2560x720 pixels). Each cell is 128x120 pixels. Pixel values below include grid gaps and padding, so treat them as approximate.

| Size | Grid | Pixels |
|------|------|--------|
| Minimum | 2x2 | 256x240 |
| Small | 3x2 | 384x240 |
| Medium | 4x3 | 512x360 |
| Large | 6x4 | 768x480 |
| Full width | 20x6 | 2560x720 |

