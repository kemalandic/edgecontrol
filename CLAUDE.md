# EdgeControl — CLAUDE.md

## Project
Native macOS dashboard for CORSAIR XENEON EDGE 14.5" touchscreen (2560×720).
Bundle ID: `ai.pakslab.edgecontrol` | Team: `CNRZ47Y629`

## Tech Stack
- Swift 6, SwiftUI + AppKit, macOS 14+
- Xcode project via xcodegen (`project.yml`)
- No backend, no database, no plugin system

## Build & Run
```bash
cd /Users/raven/projects/my-repo/edgecontrol
xcodebuild -project EdgeControl.xcodeproj -scheme EdgeControl -configuration Debug -allowProvisioningUpdates build
# Or: open EdgeControl.xcodeproj → Cmd+R
```

## Regenerate Xcode Project
```bash
xcodegen generate
# WARNING: If project.yml has 'entitlements:' block, it WILL overwrite EdgeControl.entitlements to empty!
# Keep entitlements only in build settings (CODE_SIGN_ENTITLEMENTS), not in entitlements: block.
```

## Anti-Assumption Protocol
- NEVER assume display resolution — detect via DisplayManager
- NEVER assume font sizes are readable — minimum 14pt labels, 20pt+ values (14.5" screen)
- NEVER add plugin/Node.js system — everything is native Swift
- NEVER manually edit .xcodeproj — edit project.yml and run xcodegen
- NEVER use Spotify/Apple Music APIs — user uses YouTube Music
- NEVER overflow 720px height — all UI must fit vertically

## Capabilities
WeatherKit, HealthKit, HomeKit, Push Notifications (APNs), App Groups (`group.ai.pakslab.edgecontrol`), Associated Domains (`pakslab.ai`)

## Hardware
- Display: CORSAIR XENEON EDGE 14.5" — 2560×720, USB-C, touch enabled
- Host: Mac Studio M3 Ultra, 256GB RAM

## File Structure
```
Sources/EdgeControl/
├── App/          # Entry point, window placement
├── Models/       # Data structs (SystemMetrics, AppSettings, DisplayDescriptor)
├── Services/     # AppModel, SystemMetricsService, DisplayManager, SettingsStore
└── UI/           # Theme (design tokens, gauges, clock), UnifiedDashboardView
```
