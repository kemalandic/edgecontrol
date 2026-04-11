# EdgeControl Plugin API Reference

## Events

### `update` — Periodic data push
```javascript
edgecontrol.on('update', function(data) {
  // data contains all permitted system data + theme + config
  console.log(data.system.cpuPercent);
});
```
Fires at the plugin's `refreshInterval` (default: 2 seconds, minimum: 1 second).

### `ready` — SDK initialized
```javascript
edgecontrol.on('ready', function() {
  // DOM loaded, SDK ready, safe to initialize
});
```

### `resize` — Widget size changed

```javascript
edgecontrol.on('resize', function(size) {
  // size: { width: 4, height: 3, pixelWidth: 512, pixelHeight: 360 }
  // width/height = grid cells, pixelWidth/pixelHeight = actual pixels
});
```

### `themeChange` — Theme settings changed

```javascript
edgecontrol.on('themeChange', function(theme) {
  // theme object with all resolved colors, fonts, and settings
  // CSS variables are also updated automatically
  console.log(theme.accent);         // "#00E5FF" (global accent)
  console.log(theme.widgetPrimary);  // "#00E5FF" (this widget's primary color)
  console.log(theme.fontSizeTitle);  // 18 (pre-scaled px)
  console.log(theme.fontSizeValue);  // 28
  console.log(theme.fontSizeLabel);  // 14
  console.log(theme.fontSizeCaption);// 11
  console.log(theme.fontSizeBody);   // 16
  console.log(theme.fontSizeMicro);  // 10
});
```

### `visibilityChange` — Widget became visible/hidden

```javascript
edgecontrol.on('visibilityChange', function(visible) {
  // visible: true when page is shown, false when user swipes away
  if (visible) startAnimation();
  else stopAnimation();
});
```

## Methods
### `edgecontrol.notify(title, body)`
Send a macOS notification. Requires `notifications` permission.
```javascript
edgecontrol.notify('CPU Alert', 'CPU usage exceeded 90%');
```

### `edgecontrol.openURL(url)`
Open a URL in the default browser. Requires `open-url` permission.
```javascript
edgecontrol.openURL('https://github.com');
```

### `edgecontrol.copyToClipboard(text)`
Copy text to the system clipboard. Requires `clipboard` permission.
```javascript
edgecontrol.copyToClipboard('192.168.1.1');
```

### `edgecontrol.getWidgetSize()`
Get current widget dimensions (synchronous, no permission needed).
```javascript
var size = edgecontrol.getWidgetSize();
// { width: 4, height: 3, pixelWidth: 512, pixelHeight: 360 }
```

## Persistent Storage
Requires `storage` permission. All methods return Promises.

### `edgecontrol.storage.get(key)`
```javascript
var value = await edgecontrol.storage.get('myKey');
// returns the stored value, or null if not found
```

### `edgecontrol.storage.set(key, value)`
```javascript
await edgecontrol.storage.set('counter', 42);
await edgecontrol.storage.set('prefs', { theme: 'dark', size: 'large' });
```

### `edgecontrol.storage.remove(key)`
```javascript
await edgecontrol.storage.remove('myKey');
```

Storage is persisted to disk at `~/Library/Application Support/EdgeControl/PluginData/{pluginId}/storage.json`. Values are stored as JSON.

## Data Accessors

Convenience getters for the latest data snapshot. Available based on permissions.

| Accessor | Permission | Type |
|----------|-----------|------|
| `edgecontrol.system` | `system-metrics` | Object |
| `edgecontrol.temperature` | `temperature` | Object |
| `edgecontrol.network` | `network` | Object |
| `edgecontrol.processes` | `processes` | Array |
| `edgecontrol.media` | `media` | Object or null |
| `edgecontrol.weather` | `weather` | Object or null |
| `edgecontrol.audio` | `audio` | Object |
| `edgecontrol.bluetooth` | `bluetooth` | Object |
| `edgecontrol.diskIO` | `disk-io` | Object |
| `edgecontrol.theme` | *(always)* | Object |
| `edgecontrol.config` | *(always)* | Object |

## Low-Level

### `edgecontrol.get(key)`
Get a value from the data snapshot. Without a key, returns the entire snapshot.
```javascript
var allData = edgecontrol.get();
var cpu = edgecontrol.get('system');
```

### `edgecontrol.on(event, callback)` / `edgecontrol.off(event, callback)`
Subscribe/unsubscribe to events.

### `edgecontrol.send(action, payload)`
Send a message to the native app. Used internally by SDK methods — you typically don't need to call this directly.
