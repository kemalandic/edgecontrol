import Foundation
import SwiftUI

// MARK: - Shared Color Helpers

enum PluginColorHelpers {
    static func hexString(_ wc: WidgetColor) -> String {
        let r = Int(wc.red * 255)
        let g = Int(wc.green * 255)
        let b = Int(wc.blue * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    static func colorToCSS(_ color: Color) -> String {
        let resolved = color.resolve(in: EnvironmentValues())
        let r = Int(resolved.red * 255)
        let g = Int(resolved.green * 255)
        let b = Int(resolved.blue * 255)
        let a = resolved.opacity
        if a < 1.0 {
            return "rgba(\(r),\(g),\(b),\(String(format: "%.2f", a)))"
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Collects system data and serializes it for plugin JS bridge.
/// Only includes data the plugin has permission to access.
@MainActor
public final class PluginDataBridge {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    /// Build a JSON dictionary of system data based on granted permissions.
    public func buildDataPayload(
        permissions: [PluginPermission],
        widgetConfig: WidgetConfig,
        themeSettings: ThemeSettings,
        widgetId: String
    ) -> [String: Any] {
        var data: [String: Any] = [:]

        // Live theme data from ThemeSettings
        data["theme"] = liveThemeData(ts: themeSettings, widgetId: widgetId)

        // Always include widget config
        data["config"] = configToDict(widgetConfig)

        for permission in permissions {
            switch permission {
            case .systemMetrics:
                if let m = model.systemMetrics {
                    data["system"] = [
                        "cpuPercent": m.cpuLoadPercent,
                        "memoryPercent": m.memoryUsedPercent,
                        "memoryUsedGB": m.memoryUsedGB,
                        "memoryTotalGB": m.memoryTotalGB,
                        "memoryPressure": m.memoryPressurePercent,
                        "swapUsedMB": m.swapUsedMB,
                        "storagePercent": m.storageUsedPercent,
                        "storageUsedGB": m.storageUsedGB,
                        "storageTotalGB": m.storageTotalGB,
                        "uptimeSeconds": m.uptimeSeconds,
                        "cpuBrand": m.cpuBrand,
                        "gpuName": m.gpuName,
                        "performanceCores": m.performanceCoreCount,
                        "efficiencyCores": m.efficiencyCoreCount,
                        "thermalState": m.thermalState
                    ]
                }

            case .temperature:
                var temps: [String: Any] = [:]
                if let cpu = model.smcService.cpuTemperature { temps["cpu"] = cpu }
                if let gpu = model.smcService.gpuTemperature { temps["gpu"] = gpu }
                if let ssd = model.smcService.ssdTemperature { temps["ssd"] = ssd }
                if let mem = model.smcService.memoryTemperature { temps["memory"] = mem }
                temps["cpuHistory"] = model.smcService.cpuTempHistory
                temps["gpuHistory"] = model.smcService.gpuTempHistory
                data["temperature"] = temps

            case .network:
                data["network"] = [
                    "downloadSpeed": model.networkService.downloadSpeed,
                    "uploadSpeed": model.networkService.uploadSpeed,
                    "totalDownloaded": model.networkService.totalDownloaded,
                    "totalUploaded": model.networkService.totalUploaded,
                    "wifi": [
                        "connected": model.wifiService.isConnected,
                        "ssid": model.wifiService.ssid as Any,
                        "signalStrength": model.wifiService.signalStrength,
                        "channel": model.wifiService.channel,
                        "txRate": model.wifiService.txRate
                    ]
                ]

            case .processes:
                data["processes"] = model.processService.topProcesses.map { proc in
                    [
                        "pid": proc.id,
                        "name": proc.name,
                        "cpuPercent": proc.cpuPercent,
                        "memoryMB": proc.memoryMB
                    ] as [String: Any]
                }

            case .media:
                if let np = model.nowPlayingService.nowPlaying {
                    data["media"] = [
                        "title": np.title,
                        "artist": np.artist,
                        "album": np.album,
                        "source": np.sourceName,
                        "isPlaying": np.isPlaying,
                        "duration": np.duration,
                        "elapsed": np.elapsed,
                        "progress": np.progress
                    ]
                }

            case .bluetooth:
                data["bluetooth"] = [
                    "available": model.bluetoothService.isAvailable,
                    "devices": model.bluetoothService.devices.map { dev in
                        [
                            "id": dev.id,
                            "name": dev.name,
                            "connected": dev.isConnected,
                            "type": dev.deviceType,
                            "battery": dev.batteryLevel as Any
                        ] as [String: Any]
                    }
                ]

            case .audio:
                data["audio"] = [
                    "volume": model.audioService.volume,
                    "muted": model.audioService.isMuted,
                    "outputDevice": model.audioService.outputDeviceName
                ]

            case .weather:
                if let w = model.weatherService.current {
                    data["weather"] = [
                        "temperature": w.temperature,
                        "condition": w.conditionText,
                        "humidity": w.humidity,
                        "windSpeed": w.windSpeed,
                        "isDay": w.isDay
                    ]
                }

            case .diskIO:
                data["diskIO"] = [
                    "readBytesPerSec": model.diskIOService.readBytesPerSec,
                    "writeBytesPerSec": model.diskIOService.writeBytesPerSec
                ]

            // v2 action permissions — no data payload, handled via JS→native actions
            case .notifications, .openURL, .clipboard, .storage, .networkAccess:
                break
            }
        }

        return data
    }

    // MARK: - Live Theme Data (from ThemeSettings)

    /// Build the theme JS object from live ThemeSettings. Used by both data push and themeChange events.
    func liveThemeData(ts: ThemeSettings, widgetId: String) -> [String: Any] {
        let preset = ts.resolvedPreset
        let wp = ts.widgetColorOverrides[widgetId]?.primary ?? WidgetColor(ThemeColor.cyan)
        let ws = ts.widgetColorOverrides[widgetId]?.secondary
        let wt = ts.widgetColorOverrides[widgetId]?.tertiary

        var dict: [String: Any] = [:]
        dict["accent"] = PluginColorHelpers.hexString(ts.accentColor)
        dict["background1"] = PluginColorHelpers.colorToCSS(preset.backgroundColors.first ?? .black)
        dict["background2"] = PluginColorHelpers.colorToCSS(preset.backgroundColors.dropFirst().first ?? .black)
        dict["background3"] = PluginColorHelpers.colorToCSS(preset.backgroundColors.last ?? .black)
        dict["cardBackground"] = PluginColorHelpers.colorToCSS(preset.cardBackground)
        dict["textPrimary"] = PluginColorHelpers.colorToCSS(preset.textPrimary)
        dict["textSecondary"] = PluginColorHelpers.colorToCSS(preset.textSecondary)
        dict["textTertiary"] = PluginColorHelpers.colorToCSS(preset.textTertiary)
        dict["border"] = PluginColorHelpers.colorToCSS(preset.border)
        dict["widgetPrimary"] = PluginColorHelpers.hexString(wp)
        dict["widgetSecondary"] = ws.map { PluginColorHelpers.hexString($0) } as Any
        dict["widgetTertiary"] = wt.map { PluginColorHelpers.hexString($0) } as Any
        dict["fontScale"] = ts.fontScale
        dict["fontFamily"] = ts.fontFamily.rawValue
        dict["fontSizeTitle"] = ts.fontSizeTitle * ts.fontScale
        dict["fontSizeValue"] = ts.fontSizeValue * ts.fontScale
        dict["fontSizeLabel"] = ts.fontSizeLabel * ts.fontScale
        dict["fontSizeCaption"] = ts.fontSizeCaption * ts.fontScale
        dict["fontSizeBody"] = ts.fontSizeBody * ts.fontScale
        dict["fontSizeMicro"] = ts.fontSizeMicro * ts.fontScale
        dict["widgetOpacity"] = ts.widgetOpacity
        dict["widgetCornerRadius"] = ts.widgetCornerRadius
        dict["widgetGap"] = ts.widgetGap
        return dict
    }

    private func configToDict(_ config: WidgetConfig) -> [String: Any] {
        var dict: [String: Any] = [:]
        for key in config.keys {
            switch config[key] {
            case .bool(let v): dict[key] = v
            case .int(let v): dict[key] = v
            case .double(let v): dict[key] = v
            case .string(let v): dict[key] = v
            case .stringArray(let v): dict[key] = v
            case .none: break
            }
        }
        return dict
    }
}
