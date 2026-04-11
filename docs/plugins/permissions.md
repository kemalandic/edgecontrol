# EdgeControl Plugin Permissions

Plugins declare permissions in `manifest.json`. Each permission grants access to specific data or actions.

## Data Permissions

### `system-metrics`
CPU, memory, storage, and system info.
```json
{ "permissions": ["system-metrics"] }
```
```javascript
edgecontrol.on('update', function(data) {
  data.system.cpuPercent        // 45.2
  data.system.memoryPercent     // 67.8
  data.system.memoryUsedGB      // 21.7
  data.system.memoryTotalGB     // 32.0
  data.system.memoryPressure    // 35.0
  data.system.swapUsedMB        // 128.5
  data.system.storagePercent    // 54.3
  data.system.storageUsedGB     // 512.0
  data.system.storageTotalGB    // 1000.0
  data.system.uptimeSeconds     // 86400
  data.system.cpuBrand          // "Apple M3 Ultra"
  data.system.gpuName           // "Apple M3 Ultra"
  data.system.performanceCores  // 16
  data.system.efficiencyCores   // 8
  data.system.thermalState      // "nominal"
});
```

### `temperature`
CPU, GPU, SSD, and memory temperatures.
```json
{ "permissions": ["temperature"] }
```
```javascript
data.temperature.cpu        // 52.0
data.temperature.gpu        // 48.0
data.temperature.ssd        // 38.0
data.temperature.memory     // 42.0
data.temperature.cpuHistory // [50.1, 51.2, 52.0, ...]
data.temperature.gpuHistory // [47.5, 48.0, ...]
```

### `network`
Network speeds and WiFi info.
```json
{ "permissions": ["network"] }
```
```javascript
data.network.downloadSpeed    // 125000000 (bytes/sec)
data.network.uploadSpeed      // 25000000
data.network.totalDownloaded  // 1073741824 (bytes)
data.network.totalUploaded    // 268435456
data.network.wifi.connected   // true
data.network.wifi.ssid        // "MyNetwork"
data.network.wifi.signalStrength // -45 (dBm)
data.network.wifi.channel     // 36
data.network.wifi.txRate      // 866 (Mbps)
```

### `processes`
Top processes by CPU usage.
```json
{ "permissions": ["processes"] }
```
```javascript
data.processes // Array of:
// { pid: 1234, name: "Safari", cpuPercent: 12.5, memoryMB: 450.2 }
```

### `media`
Now playing info (current media).
```json
{ "permissions": ["media"] }
```
```javascript
data.media.title      // "Song Name"
data.media.artist     // "Artist"
data.media.album      // "Album"
data.media.source     // "YouTube Music"
data.media.isPlaying  // true
data.media.duration   // 240.0 (seconds)
data.media.elapsed    // 120.0
data.media.progress   // 0.5
```

### `bluetooth`
Connected Bluetooth devices.
```json
{ "permissions": ["bluetooth"] }
```
```javascript
data.bluetooth.available // true
data.bluetooth.devices   // Array of:
// { id: "...", name: "AirPods Pro", connected: true, type: "headphones", battery: 85 }
```

### `audio`
System audio output.
```json
{ "permissions": ["audio"] }
```
```javascript
data.audio.volume       // 0.65 (0.0 - 1.0)
data.audio.muted        // false
data.audio.outputDevice // "MacBook Pro Speakers"
```

### `weather`
Current weather data.
```json
{ "permissions": ["weather"] }
```
```javascript
data.weather.temperature // 22.5
data.weather.condition   // "Partly Cloudy"
data.weather.humidity    // 0.65
data.weather.windSpeed   // 12.0 (km/h)
data.weather.isDay       // true
```

### `disk-io`
Disk read/write speeds.
```json
{ "permissions": ["disk-io"] }
```
```javascript
data.diskIO.readBytesPerSec  // 50000000
data.diskIO.writeBytesPerSec // 25000000
```

## Action Permissions
### `notifications`
Send macOS notifications via `edgecontrol.notify(title, body)`.

### `open-url`
Open URLs in the default browser via `edgecontrol.openURL(url)`.

### `clipboard`
Write to the system clipboard via `edgecontrol.copyToClipboard(text)`.

### `storage`
Persistent key-value storage via `edgecontrol.storage.get/set/remove`.

### `network-access`
Allow `fetch()` and `XMLHttpRequest` to external domains. By default, plugins cannot make network requests.

Use with `allowedDomains` to restrict which domains are reachable:
```json
{
  "permissions": ["network-access"],
  "allowedDomains": ["api.github.com", "api.example.com"]
}
```

If `allowedDomains` is omitted or empty, all external domains are allowed.
