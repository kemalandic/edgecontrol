# EdgeControl

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**A native macOS dashboard for the CORSAIR XENEON EDGE touchscreen display.**

Built from scratch in Swift & SwiftUI — no third-party dependencies. Designed specifically for the 2560x720 form factor with full touch support.

![EdgeControl Dashboard](screenshots/dashboard.png)

## Why I Built This

I got the XENEON EDGE because I loved the idea of a dedicated touchscreen dashboard on my desk. But on macOS, there's no software for it — it just shows up as another monitor. So I built my own.

What started as a basic system monitor has grown into a fully modular dashboard with 25 widgets, a dynamic grid layout system, complete theme customization, and plugin support. This isn't a concept or a demo; it's something I use every single day, and it keeps getting better.

## What It Does

EdgeControl turns any external display into a fully customizable system dashboard. You create pages, place widgets wherever you want on a 20x6 grid, resize them, and configure everything from colors to fonts.

### 25 Built-in Widgets

**System (9)** — CPU Gauge, Memory Gauge, CPU History, Memory History, Process List, Disk I/O, Storage Bars, Memory Pressure, CPU Cores (per-core usage)

**Temperature (5)** — CPU Temp, GPU Temp, SSD Temp, Temperature History, Per-Core Temp (P-core/E-core breakdown)

**Network (3)** — Network Stats (up/down speeds), WiFi Info (SSID, signal, channel), Bluetooth Devices

**Media (2)** — Now Playing (controls, artwork, progress), Audio Devices (output, volume)

**Info (5)** — Weather (current + 5-day forecast), Clock (10 visual themes), World Clocks, Day Progress, Moon Phase

**DevTools (1)** — CI/CD Runs (GitHub Actions across all repos)

### Dynamic Grid Layout

- 20x6 grid (2560x720) — drag to move, corner handles to resize
- Unlimited pages with swipe navigation
- Each widget adapts its layout to its size (compact, bar, chart, full)
- Edit mode with collision detection and visual guides

### Full Theme Customization

- **8 presets**: Default Dark, OLED Black, Midnight Blue, Neon Cyan, Neon Purple, Arctic, Ember, Terminal
- **Custom color scheme**: individually set all 8 scheme colors (backgrounds, text, borders)
- **Accent color**: 9 presets + native color picker for any color
- **Per-widget colors**: primary/secondary/tertiary color overrides with native color picker
- **Font system**: 4 font families, global scale, 6 individually adjustable font levels
- **Widget appearance**: opacity, corner radius, gap

### Clock Widget — 10 Themes

Digital, Analog, LCD Retro, Minimal, Split, Rings, Day Bar, Neon, Binary, Dot Matrix

### Plugin System

Extend EdgeControl with custom HTML/JS widgets:

- `.ecplugin` bundle format with manifest.json
- WKWebView rendering with full JavaScript SDK
- 14 permissions: 9 data (system metrics, temperature, network, etc.) + 5 actions (notifications, clipboard, storage, URL, network access)
- Dynamic theme integration — CSS custom properties (`--ec-*`) auto-injected and live-updated
- Persistent key-value storage per plugin
- Network sandbox with domain whitelisting
- Lifecycle events: resize, theme change, visibility
- Install from zip, enable/disable, hot reload
- [Plugin Developer Documentation](docs/plugins/getting-started.md)

## Screenshots

| System Monitor | Temperatures | Media Control |
|:-:|:-:|:-:|
| ![System](screenshots/dashboard.png) | ![Temps](screenshots/temps.png) | ![Media](screenshots/media.png) |

| Network | Clocks | Connectivity |
|:-:|:-:|:-:|
| ![Network](screenshots/network.png) | ![Clocks](screenshots/clocks.png) | ![Connectivity](screenshots/connectivity.png) |

## Install

Download the latest `.dmg` from [**Releases**](https://github.com/kemalandic/edgecontrol/releases), open it, and drag EdgeControl to Applications.

> Requires macOS 14.0 or later. Works on any display but optimized for the XENEON EDGE (2560x720).

## Build from Source

```bash
git clone https://github.com/kemalandic/edgecontrol.git
cd edgecontrol
xcodegen generate      # requires: brew install xcodegen
open EdgeControl.xcodeproj
# Cmd+R to run
```

## Touch Support

EdgeControl has native HID touch input support for the XENEON EDGE touchscreen. Every button and control works with both mouse clicks and direct touch taps. The touch system auto-calibrates to your display positioning.

## Architecture

```
Sources/EdgeControl/
├── App/            # Entry point, window placement
├── Models/         # WidgetProtocol, LayoutConfig, ThemeSettings, PluginManifest, SystemMetrics
├── Services/       # AppModel, LayoutEngine, WidgetRegistry, PluginManager, PluginDataBridge, PluginStorageService
├── UI/
│   ├── Components/ # RadialGauge, HistoryGraph, ThemeEnvironment, WidgetHeader
│   ├── Settings/   # 6-tab settings window (Pages, Widgets, Theme, Plugins, Display, General)
│   ├── DashboardShell.swift  # Main dashboard container
│   └── GridPageView.swift    # Widget grid renderer with edit mode
└── Widgets/
    ├── System/       # CPU, Memory, Storage, Pressure, Cores, DiskIO, ProcessList
    ├── Temperature/  # CPU/GPU/SSD Temp, TempHistory, PerCoreTemp
    ├── Network/      # NetworkStats, WiFiInfo, Bluetooth
    ├── Media/        # NowPlaying, AudioDevices
    ├── Info/         # Weather, Clock, WorldClocks, DayProgress, MoonPhase
    ├── DevTools/     # CICDRuns
    └── Plugin/       # PluginWebWidget (WKWebView renderer + JS SDK)
```

## Permissions

- **Location** — weather data (Open-Meteo, free API)
- **Bluetooth** — connected device list

## License

[MIT](LICENSE)

---

Built by [PaksLab](https://pakslab.ai)
