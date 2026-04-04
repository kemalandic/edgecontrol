import SwiftUI

/// Page 4: Disk I/O + Storage details
struct DiskIOPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            // LEFT: Disk I/O speeds + graphs
            diskIOPanel()
                .frame(maxWidth: .infinity)

            divider()

            // CENTER: Storage breakdown
            storagePanel()
                .frame(maxWidth: .infinity)

            divider()

            // RIGHT: Network (duplicate for quick view)
            networkPanel()
                .frame(maxWidth: .infinity)
        }
    }

    private func divider() -> some View {
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

    // MARK: - Disk I/O

    private func diskIOPanel() -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accentBlue).frame(width: 10, height: 10)
                Text("DISK I/O")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            // Read speed
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accentCyan)
                    Text("READ")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Text(DiskIOService.formatSpeed(model.diskIOService.readBytesPerSec))
                        .font(.system(size: 36, weight: .light, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                }

                HistoryGraphView(
                    history: normalizeHistory(model.diskIOService.readHistory),
                    color: Theme.accentCyan
                )
                .frame(height: 80)
            }
            .padding(14)
            .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
            )

            // Write speed
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "arrow.up.doc.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accentOrange)
                    Text("WRITE")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Text(DiskIOService.formatSpeed(model.diskIOService.writeBytesPerSec))
                        .font(.system(size: 36, weight: .light, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                }

                HistoryGraphView(
                    history: normalizeHistory(model.diskIOService.writeHistory),
                    color: Theme.accentOrange
                )
                .frame(height: 80)
            }
            .padding(14)
            .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
            )

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    // MARK: - Storage

    private func storagePanel() -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accentPurple).frame(width: 10, height: 10)
                Text("STORAGE")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            if let m = model.systemMetrics {
                // Big circular gauge
                ZStack {
                    Circle()
                        .trim(from: 0, to: 1)
                        .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 20, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Circle()
                        .trim(from: 0, to: m.storageUsedPercent / 100)
                        .stroke(
                            AngularGradient(colors: [Theme.accentBlue, Theme.accentPurple], center: .center),
                            style: StrokeStyle(lineWidth: 20, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 4) {
                        Text(String(format: "%.0f%%", m.storageUsedPercent))
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Text("USED")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(maxWidth: 240, maxHeight: 240)
                .frame(maxWidth: .infinity)

                // Stats
                HStack(spacing: 16) {
                    storageStatBox(label: "USED", value: String(format: "%.0f GB", m.storageUsedGB), color: Theme.accentBlue)
                    storageStatBox(label: "FREE", value: String(format: "%.0f GB", m.storageTotalGB - m.storageUsedGB), color: Theme.accentGreen)
                    storageStatBox(label: "TOTAL", value: String(format: "%.0f GB", m.storageTotalGB), color: Theme.textSecondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    // MARK: - Network

    private func networkPanel() -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accentGreen).frame(width: 10, height: 10)
                Text("NETWORK")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            // Download
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.accentGreen)
                    Text("DOWNLOAD")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }
                Text(NetworkMonitorService.formatSpeed(model.networkService.downloadSpeed))
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
            }
            .padding(14)
            .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
            )

            // Upload
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.accentCyan)
                    Text("UPLOAD")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }
                Text(NetworkMonitorService.formatSpeed(model.networkService.uploadSpeed))
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
            }
            .padding(14)
            .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
            )

            // Totals
            HStack(spacing: 8) {
                totalChip(label: "TOTAL DL", value: NetworkMonitorService.formatBytes(model.networkService.totalDownloaded), color: Theme.accentGreen)
                totalChip(label: "TOTAL UL", value: NetworkMonitorService.formatBytes(model.networkService.totalUploaded), color: Theme.accentCyan)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func storageStatBox(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.borderSubtle, lineWidth: 1)
        )
    }

    private func totalChip(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
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

    private func normalizeHistory(_ history: [Double]) -> [Double] {
        guard let maxVal = history.max(), maxVal > 0 else { return history.map { _ in 0.0 } }
        return history.map { $0 / maxVal }
    }
}
