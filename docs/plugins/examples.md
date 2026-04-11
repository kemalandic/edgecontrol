# Plugin Examples

Five complete plugin examples. Copy any of these to get started.

---

## 1. Hello World

Minimal plugin — shows system time, no permissions needed.

**manifest.json**
```json
{
  "id": "com.example.hello-world",
  "name": "Hello World",
  "version": "1.0.0",
  "author": "EdgeControl",
  "description": "Shows the current time",
  "icon": "clock",
  "permissions": [],
  "widgets": [{
    "id": "clock",
    "name": "Simple Clock",
    "icon": "clock",
    "htmlFile": "widget.html",
    "supportedSizes": { "min": [2, 2], "max": [4, 3] },
    "defaultSize": [2, 2],
    "refreshInterval": 1.0
  }]
}
```

**widget.html**
```html
<!DOCTYPE html>
<html>
<head>
<style>
  body {
    margin: 0; padding: 16px;
    background: transparent;
    font-family: var(--ec-font-family);
    display: flex; flex-direction: column;
    justify-content: center; height: 100vh;
    box-sizing: border-box;
  }
  .time {
    font-size: var(--ec-font-value);
    font-weight: bold;
    color: var(--ec-widget-primary);
  }
  .date {
    font-size: var(--ec-font-label);
    color: var(--ec-text-secondary);
    margin-top: 4px;
  }
</style>
</head>
<body>
  <div class="time" id="time">--:--</div>
  <div class="date" id="date"></div>
  <script>
    function tick() {
      var now = new Date();
      document.getElementById('time').textContent =
        now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
      document.getElementById('date').textContent =
        now.toLocaleDateString([], { weekday: 'long', month: 'short', day: 'numeric' });
    }
    setInterval(tick, 1000);
    tick();
  </script>
</body>
</html>
```

---

## 2. CPU Alert

Monitors CPU usage and sends a notification when it exceeds a threshold.

**manifest.json**
```json
{
  "id": "com.example.cpu-alert",
  "name": "CPU Alert",
  "version": "1.0.0",
  "author": "EdgeControl",
  "description": "Alerts when CPU is high",
  "icon": "exclamationmark.triangle",
  "permissions": ["system-metrics", "notifications"],
  "widgets": [{
    "id": "monitor",
    "name": "CPU Monitor",
    "icon": "cpu",
    "htmlFile": "widget.html",
    "supportedSizes": { "min": [2, 2], "max": [4, 3] },
    "defaultSize": [3, 2],
    "refreshInterval": 2.0,
    "configSchema": [
      { "key": "threshold", "label": "Alert Threshold (%)", "type": "number", "default": 90 }
    ]
  }]
}
```

**widget.html**
```html
<!DOCTYPE html>
<html>
<head>
<style>
  body {
    margin: 0; padding: 12px;
    background: transparent;
    font-family: var(--ec-font-family);
    color: var(--ec-text-primary);
  }
  .label { font-size: var(--ec-font-caption); font-weight: 700; color: var(--ec-text-tertiary); text-transform: uppercase; }
  .value { font-size: var(--ec-font-value); font-weight: bold; color: var(--ec-widget-primary); transition: color 0.3s; }
  .value.alert { color: #FF2E2E; }
  .status { font-size: var(--ec-font-caption); color: var(--ec-text-secondary); margin-top: 4px; }
</style>
</head>
<body>
  <div class="label">CPU USAGE</div>
  <div class="value" id="cpu">--</div>
  <div class="status" id="status">Monitoring...</div>
  <script>
    var lastAlertTime = 0;
    edgecontrol.on('update', function(data) {
      if (!data.system) return;
      var cpu = Math.round(data.system.cpuPercent);
      var threshold = edgecontrol.config.threshold || 90;
      var el = document.getElementById('cpu');
      el.textContent = cpu + '%';
      el.className = cpu >= threshold ? 'value alert' : 'value';

      if (cpu >= threshold && Date.now() - lastAlertTime > 60000) {
        edgecontrol.notify('CPU Alert', 'CPU usage is at ' + cpu + '%');
        lastAlertTime = Date.now();
        document.getElementById('status').textContent = 'Alert sent!';
      } else {
        document.getElementById('status').textContent =
          cpu >= threshold ? 'High usage!' : 'Normal';
      }
    });
  </script>
</body>
</html>
```

---

## 3. GitHub Status

Fetches a GitHub repository's status via the API.

**manifest.json**
```json
{
  "id": "com.example.github-status",
  "name": "GitHub Status",
  "version": "1.0.0",
  "author": "EdgeControl",
  "description": "Shows repo status from GitHub API",
  "icon": "chevron.left.forwardslash.chevron.right",
  "permissions": ["network-access"],
  "allowedDomains": ["api.github.com"],
  "widgets": [{
    "id": "repo",
    "name": "Repo Status",
    "icon": "chevron.left.forwardslash.chevron.right",
    "htmlFile": "widget.html",
    "supportedSizes": { "min": [3, 2], "max": [6, 4] },
    "defaultSize": [4, 2],
    "refreshInterval": 60.0,
    "configSchema": [
      { "key": "repo", "label": "Repository (owner/repo)", "type": "string", "default": "apple/swift" }
    ]
  }]
}
```

**widget.html**
```html
<!DOCTYPE html>
<html>
<head>
<style>
  body {
    margin: 0; padding: 12px;
    background: transparent;
    font-family: var(--ec-font-family);
    color: var(--ec-text-primary);
  }
  .label { font-size: var(--ec-font-caption); font-weight: 700; color: var(--ec-text-tertiary); text-transform: uppercase; }
  .repo-name { font-size: var(--ec-font-body); font-weight: bold; color: var(--ec-widget-primary); margin: 4px 0; }
  .stat { font-size: var(--ec-font-label); color: var(--ec-text-secondary); margin: 2px 0; }
  .stat span { color: var(--ec-text-primary); font-weight: 600; }
</style>
</head>
<body>
  <div class="label">GITHUB</div>
  <div class="repo-name" id="name">Loading...</div>
  <div class="stat">Stars: <span id="stars">-</span></div>
  <div class="stat">Forks: <span id="forks">-</span></div>
  <div class="stat">Issues: <span id="issues">-</span></div>
  <script>
    async function fetchRepo() {
      var repo = edgecontrol.config.repo || 'apple/swift';
      try {
        var res = await fetch('https://api.github.com/repos/' + repo);
        var data = await res.json();
        document.getElementById('name').textContent = data.full_name;
        document.getElementById('stars').textContent = data.stargazers_count.toLocaleString();
        document.getElementById('forks').textContent = data.forks_count.toLocaleString();
        document.getElementById('issues').textContent = data.open_issues_count.toLocaleString();
      } catch(e) {
        document.getElementById('name').textContent = 'Error: ' + e.message;
      }
    }
    edgecontrol.on('ready', fetchRepo);
    // refreshInterval is 60s — safe for GitHub's 60 req/hour unauthenticated limit
    edgecontrol.on('update', fetchRepo);
  </script>
</body>
</html>
```

---

## 4. Theme Mirror

Displays all current theme colors — demonstrates full theme integration.

**manifest.json**
```json
{
  "id": "com.example.theme-mirror",
  "name": "Theme Mirror",
  "version": "1.0.0",
  "author": "EdgeControl",
  "description": "Shows all current theme colors",
  "icon": "paintpalette",
  "permissions": [],
  "widgets": [{
    "id": "mirror",
    "name": "Theme Colors",
    "icon": "paintpalette",
    "htmlFile": "widget.html",
    "supportedSizes": { "min": [3, 2], "max": [6, 4] },
    "defaultSize": [4, 3]
  }]
}
```

**widget.html**
```html
<!DOCTYPE html>
<html>
<head>
<style>
  body {
    margin: 0; padding: 12px;
    background: transparent;
    font-family: var(--ec-font-family);
    color: var(--ec-text-primary);
  }
  .label { font-size: var(--ec-font-caption); font-weight: 700; color: var(--ec-text-tertiary); text-transform: uppercase; margin-bottom: 8px; }
  .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; }
  .swatch {
    border-radius: 6px; padding: 6px; text-align: center;
    font-size: var(--ec-font-micro); font-weight: 600;
    border: 1px solid var(--ec-border);
  }
  .swatch .name { opacity: 0.7; }
</style>
</head>
<body>
  <div class="label">THEME COLORS</div>
  <div class="grid" id="grid"></div>
  <script>
    var colors = [
      { name: 'Accent', var: '--ec-accent' },
      { name: 'Widget 1', var: '--ec-widget-primary' },
      { name: 'Widget 2', var: '--ec-widget-secondary' },
      { name: 'BG 1', var: '--ec-bg-1' },
      { name: 'BG 2', var: '--ec-bg-2' },
      { name: 'Card', var: '--ec-card-bg' },
      { name: 'Text 1', var: '--ec-text-primary' },
      { name: 'Text 2', var: '--ec-text-secondary' },
      { name: 'Border', var: '--ec-border' },
    ];

    function render() {
      var style = getComputedStyle(document.documentElement);
      var grid = document.getElementById('grid');
      grid.innerHTML = '';
      colors.forEach(function(c) {
        var val = style.getPropertyValue(c.var).trim();
        var div = document.createElement('div');
        div.className = 'swatch';
        div.style.background = val;
        div.style.color = c.name.startsWith('BG') ? '#fff' : 'inherit';
        div.innerHTML = '<div class="name">' + c.name + '</div>';
        grid.appendChild(div);
      });
    }

    edgecontrol.on('ready', render);
    edgecontrol.on('themeChange', render);
  </script>
</body>
</html>
```

---

## 5. Persistent Counter

Click counter with storage — demonstrates the storage API.

**manifest.json**
```json
{
  "id": "com.example.counter",
  "name": "Persistent Counter",
  "version": "1.0.0",
  "author": "EdgeControl",
  "description": "Click counter that persists across restarts",
  "icon": "number",
  "permissions": ["storage"],
  "widgets": [{
    "id": "counter",
    "name": "Counter",
    "icon": "plus.circle",
    "htmlFile": "widget.html",
    "supportedSizes": { "min": [2, 2], "max": [4, 3] },
    "defaultSize": [2, 2]
  }]
}
```

**widget.html**
```html
<!DOCTYPE html>
<html>
<head>
<style>
  body {
    margin: 0; padding: 16px;
    background: transparent;
    font-family: var(--ec-font-family);
    display: flex; flex-direction: column;
    align-items: center; justify-content: center;
    height: 100vh; box-sizing: border-box;
    user-select: none;
  }
  .label { font-size: var(--ec-font-caption); font-weight: 700; color: var(--ec-text-tertiary); text-transform: uppercase; }
  .count {
    font-size: var(--ec-font-value); font-weight: bold;
    color: var(--ec-widget-primary);
    cursor: pointer; transition: transform 0.1s;
  }
  .count:active { transform: scale(0.95); }
  .hint { font-size: var(--ec-font-micro); color: var(--ec-text-tertiary); margin-top: 4px; }
</style>
</head>
<body>
  <div class="label">COUNTER</div>
  <div class="count" id="count" onclick="increment()">0</div>
  <div class="hint">tap to increment</div>
  <script>
    var count = 0;

    async function load() {
      var saved = await edgecontrol.storage.get('count');
      if (saved !== null) count = saved;
      render();
    }

    function render() {
      document.getElementById('count').textContent = count;
    }

    async function increment() {
      count++;
      render();
      await edgecontrol.storage.set('count', count);
    }

    edgecontrol.on('ready', load);
  </script>
</body>
</html>
```
