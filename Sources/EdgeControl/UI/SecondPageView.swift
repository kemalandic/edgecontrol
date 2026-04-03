import AppKit
import SwiftUI

/// Second dashboard page: Network, Processes, Disk I/O
struct SecondPageView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            // LEFT: Network Monitor
            networkPanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            dividerLine()

            // CENTER: Top Processes
            processPanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            dividerLine()

            // RIGHT: Disk + extras
            diskPanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func dividerLine() -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.0), .white.opacity(0.08), .white.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1)
            .padding(.vertical, 20)
    }

    // MARK: - Network Panel

    private func networkPanel() -> some View {
        VStack(spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Circle().fill(Theme.accentGreen).frame(width: 10, height: 10)
                Text("NETWORK")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            // Download speed
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.accentGreen)
                    Text("DOWNLOAD")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }
                Text(NetworkMonitorService.formatSpeed(model.networkService.downloadSpeed))
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
            }
            .padding(16)
            .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
            )

            // Upload speed
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.accentCyan)
                    Text("UPLOAD")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }
                Text(NetworkMonitorService.formatSpeed(model.networkService.uploadSpeed))
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
            }
            .padding(16)
            .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
            )

            // Totals
            HStack(spacing: 10) {
                totalChip(icon: "arrow.down", label: "TOTAL DL", value: NetworkMonitorService.formatBytes(model.networkService.totalDownloaded), color: Theme.accentGreen)
                totalChip(icon: "arrow.up", label: "TOTAL UL", value: NetworkMonitorService.formatBytes(model.networkService.totalUploaded), color: Theme.accentCyan)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    // MARK: - Process Panel

    private func processPanel() -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accentPurple).frame(width: 10, height: 10)
                Text("TOP PROCESSES")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            VStack(spacing: 0) {
                // Header row
                HStack {
                    Text("APP")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("CPU")
                        .frame(width: 80, alignment: .trailing)
                    Text("MEM")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider().background(Theme.borderSubtle)

                // Process rows
                if model.processService.topProcesses.isEmpty {
                    Text("Loading...")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ForEach(model.processService.topProcesses) { proc in
                        processRow(proc)
                        if proc.id != model.processService.topProcesses.last?.id {
                            Divider().background(Theme.borderSubtle).padding(.leading, 50)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
            )
            .frame(maxHeight: .infinity)
        }
        .padding(16)
    }

    private func processRow(_ proc: ProcessInfo_EC) -> some View {
        HStack(spacing: 10) {
            // App icon
            if let icon = proc.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 30, height: 30)
            }

            Text(proc.name)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(format: "%.1f%%", proc.cpuPercent))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(proc.cpuPercent > 50 ? Theme.accentOrange : Theme.accentCyan)
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)

            Text(String(format: "%.0f MB", proc.memoryMB))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(proc.memoryMB > 1024 ? Theme.accentOrange : Theme.textSecondary)
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Disk Panel

    private func diskPanel() -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accentBlue).frame(width: 10, height: 10)
                Text("STORAGE")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            if let m = model.systemMetrics {
                // Disk usage visual
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .trim(from: 0, to: 1)
                            .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                            .rotationEffect(.degrees(-90))

                        Circle()
                            .trim(from: 0, to: m.storageUsedPercent / 100)
                            .stroke(
                                AngularGradient(
                                    colors: [Theme.accentBlue, Theme.accentPurple],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 16, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 2) {
                            Text(String(format: "%.0f%%", m.storageUsedPercent))
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("USED")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .frame(width: 180, height: 180)

                    HStack(spacing: 20) {
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f GB", m.storageUsedGB))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.accentBlue)
                            Text("USED")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f GB", m.storageTotalGB - m.storageUsedGB))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.accentGreen)
                            Text("FREE")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f GB", m.storageTotalGB))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.textSecondary)
                            Text("TOTAL")
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                        .strokeBorder(Theme.borderSubtle, lineWidth: 1)
                )
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func totalChip(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.borderSubtle, lineWidth: 1)
        )
    }
}
