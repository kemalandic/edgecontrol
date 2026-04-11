# Getting Started with EdgeControl Plugins

Build a custom dashboard widget in 5 minutes.

## 1. Create the Plugin Bundle

Create a folder named `my-plugin.ecplugin`:

```
my-plugin.ecplugin/
├── manifest.json
└── widget.html
```

## 2. Write manifest.json

```json
{
  "id": "com.example.my-plugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "author": "Your Name",
  "description": "A simple dashboard widget",
  "icon": "star.fill",
  "permissions": ["system-metrics"],
  "widgets": [
    {
      "id": "main",
      "name": "My Widget",
      "description": "Shows CPU usage",
      "icon": "cpu",
      "htmlFile": "widget.html",
      "supportedSizes": { "min": [2, 2], "max": [6, 4] },
      "defaultSize": [3, 2],
      "refreshInterval": 2.0
    }
  ]
}
```

## 3. Write widget.html

```html
<!DOCTYPE html>
<html>
<head>
<style>
  body {
    margin: 0;
    padding: 12px;
    background: transparent;
    font-family: var(--ec-font-family);
    color: var(--ec-text-primary);
  }
  .value {
    font-size: var(--ec-font-value);
    font-weight: bold;
    color: var(--ec-widget-primary);
  }
  .label {
    font-size: var(--ec-font-label);
    color: var(--ec-text-secondary);
    text-transform: uppercase;
    font-weight: 700;
  }
</style>
</head>
<body>
  <div class="label">CPU USAGE</div>
  <div class="value" id="cpu">--</div>

  <script>
    edgecontrol.on('update', function(data) {
      if (data.system) {
        document.getElementById('cpu').textContent =
          Math.round(data.system.cpuPercent) + '%';
      }
    });
  </script>
</body>
</html>
```

## 4. Install

1. Zip the `.ecplugin` folder (or keep it as-is)
2. Open EdgeControl Settings → Plugins
3. Click "Install Plugin" and select the zip or folder
4. The widget appears in the Widget Catalog under "Plugin"

## 5. Place on Dashboard

1. Click the pencil icon (edit mode)
2. Open Settings → Pages
3. Find your plugin widget in the catalog
4. Click "+" to place it on the current page
5. Drag to move, corner handles to resize

## What's Next

- [API Reference](api-reference.md) — all events, methods, and data accessors
- [Permissions](permissions.md) — what each permission grants
- [Theme Integration](theme-integration.md) — CSS variables and dynamic theming
- [Examples](examples.md) — 5 complete plugin examples
- [AI Guide](ai-guide.md) — generate plugins with AI
