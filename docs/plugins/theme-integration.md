# Theme Integration

EdgeControl automatically injects CSS custom properties into every plugin. These update in real-time when the user changes theme settings.

## CSS Custom Properties

```css
:root {
  /* Global accent color */
  --ec-accent: #00E5FF;

  /* Background colors (from color scheme) */
  --ec-bg-1: #0A0305;
  --ec-bg-2: #1A0508;
  --ec-bg-3: #120305;
  --ec-card-bg: rgba(255,76,25,0.05);

  /* Text colors */
  --ec-text-primary: rgba(255,255,255,0.92);
  --ec-text-secondary: rgba(255,178,115,1);
  --ec-text-tertiary: rgba(255,140,89,0.7);

  /* Border */
  --ec-border: rgba(255,76,25,0.15);

  /* This widget's resolved colors */
  --ec-widget-primary: #00E5FF;
  --ec-widget-secondary: transparent;
  --ec-widget-tertiary: transparent;

  /* Font settings */
  --ec-font-scale: 1.0;
  --ec-font-family: -apple-system, BlinkMacSystemFont, sans-serif;

  /* Semantic font sizes (pre-scaled, ready to use) */
  --ec-font-title: 18px;    /* Widget headers */
  --ec-font-value: 28px;    /* Large displayed values */
  --ec-font-label: 14px;    /* Medium labels */
  --ec-font-caption: 11px;  /* Small labels */
  --ec-font-body: 16px;     /* Normal text */
  --ec-font-micro: 10px;    /* Smallest text */

  /* Widget appearance */
  --ec-corner-radius: 10px;
  --ec-widget-opacity: 0.04;  /* native card background opacity */
  --ec-widget-gap: 4px;
}
```

## Usage

Always use `var(--ec-*)` instead of hardcoded colors:

```css
body {
  background: transparent;
  color: var(--ec-text-primary);
  font-family: var(--ec-font-family);
}

.card {
  background: var(--ec-card-bg);
  border: 1px solid var(--ec-border);
  border-radius: var(--ec-corner-radius);
}

.value {
  color: var(--ec-widget-primary);
  font-size: var(--ec-font-value);
}

.label {
  color: var(--ec-text-secondary);
  font-size: var(--ec-font-label);
}

.caption {
  font-size: var(--ec-font-caption);
}

.accent-text {
  color: var(--ec-accent);
}
```

## Font Family Mapping

| User Setting | CSS Value |
|-------------|-----------|
| Rounded | `-apple-system, BlinkMacSystemFont, sans-serif` |
| Monospaced | `"SF Mono", "Menlo", monospace` |
| System | `-apple-system, BlinkMacSystemFont, sans-serif` |
| Serif | `"New York", "Georgia", serif` |

## Widget Colors

Each widget can have user-customized colors (primary, secondary, tertiary) set in EdgeControl Settings. Use `--ec-widget-primary` as your main accent color:

```css
.gauge-fill { stroke: var(--ec-widget-primary); }
.gauge-bg { stroke: var(--ec-widget-secondary, var(--ec-border)); }
```

## Listening for Theme Changes
CSS variables update automatically. For JavaScript-driven rendering:

```javascript
edgecontrol.on('themeChange', function(theme) {
  // theme.accent           "#FF6B36"
  // theme.widgetPrimary    "#00E5FF"
  // theme.textPrimary      "rgba(255,255,255,0.92)"
  // theme.fontScale        1.0
  // theme.fontFamily       "rounded"
  // theme.widgetCornerRadius  10
  // ... all theme properties
  updateCanvas(theme);
});
```

## Best Practices

1. **Always use CSS variables** — never hardcode colors
2. **Use semantic font sizes** — `var(--ec-font-label)` instead of `calc(14px * var(--ec-font-scale))`. These are pre-scaled and match native widget sizing.
3. **Use `transparent` background** on `<body>` — the widget card provides the background
4. **Use `--ec-widget-primary`** as your main visual accent, not `--ec-accent`
5. **Test with multiple themes** — try OLED Black, Ember, and Arctic to ensure readability
