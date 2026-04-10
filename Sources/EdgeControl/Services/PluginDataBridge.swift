import Foundation

/// Collects system data and serializes it for plugin JS bridge.
/// Only includes data the plugin has permission to access.
@MainActor
public final class PluginDataBridge {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    /// Build a JSON dictionary of system data based on granted permissions.
    public func buildDataPayload(permissions: [PluginPermission], widgetConfig: WidgetConfig) -> [String: Any] {
        var data: [String: Any] = [:]

        // Always include theme colors
        data["theme"] = themeData()

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
            }
        }

        return data
    }

    private func themeData() -> [String: String] {
        [
            "cyan": "#00E5FF",
            "blue": "#3380FF",
            "purple": "#8C4DFF",
            "green": "#33E680",
            "yellow": "#F5C517",
            "orange": "#FF6B36",
            "red": "#FF2E2E",
            "textPrimary": "rgba(255,255,255,0.92)",
            "textSecondary": "rgba(255,255,255,0.58)",
            "textTertiary": "rgba(255,255,255,0.38)",
            "backgroundCard": "rgba(255,255,255,0.04)",
            "border": "rgba(255,255,255,0.08)"
        ]
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
