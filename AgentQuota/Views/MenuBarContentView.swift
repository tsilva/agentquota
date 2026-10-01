import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: QuotaStore
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let snapshot = store.snapshot, !snapshot.windows.isEmpty {
                quotaContent(snapshot)
            } else if store.connectionState.recoveryMessage == nil {
                loadingContent
            }

            if let message = store.connectionState.recoveryMessage {
                recoveryContent(message)
            } else if store.isSnapshotStale {
                staleContent
            }

            footer
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            store.popoverOpened()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 7, height: 7)
                    Text(planAndConnectionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Menu {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await store.forceRefresh() }
                }
                Divider()
                Button("Settings…", systemImage: "gearshape") {
                    openSettings()
                }
                Divider()
                Button("About AgentQuota", systemImage: "info.circle") {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                    NSApplication.shared.activate()
                }
                Divider()
                Button("Quit AgentQuota", systemImage: "power") {
                    store.shutdown()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("AgentQuota actions")
        }
    }

    private func quotaContent(_ snapshot: QuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            ForEach(Array(snapshot.windows.enumerated()), id: \.element.id) { index, window in
                if index > 0 {
                    Divider()
                }
                QuotaWindowView(window: window, now: store.currentDate)
            }
        }
    }

    private var loadingContent: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(store.connectionState.label)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private func recoveryContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message, systemImage: recoverySymbol)
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Retry") {
                    store.retry()
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button("Quit") {
                    store.shutdown()
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    private var staleContent: some View {
        Label(
            "Showing cached quota from more than two minutes ago.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.callout)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Divider()

            HStack(spacing: 8) {
                Button {
                    Task { await store.forceRefresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(
                            .rotate.clockwise,
                            options: .repeat(.continuous),
                            isActive: store.isRefreshing
                        )
                }
                .buttonStyle(.borderless)
                .help(store.isRefreshing ? "Refreshing quota" : "Force refresh quota")
                .accessibilityLabel(store.isRefreshing ? "Refreshing quota" : "Refresh quota")

                Text(store.lastUpdatedDescription)
                    .foregroundStyle(.secondary)
                    .font(.callout)

                Spacer()
            }
        }
    }

    private var planAndConnectionText: String {
        let planName = store.snapshot?.planName ?? "Plan unavailable"
        return "\(planName) · \(store.connectionState.label)"
    }

    private var connectionColor: Color {
        switch store.connectionState {
        case .connected:
            return .green
        case .connecting, .locating, .retrying:
            return .blue
        case .codexMissing, .authenticationRequired, .unsupported, .failed:
            return .orange
        case .idle, .stopped:
            return .secondary
        }
    }

    private var recoverySymbol: String {
        switch store.connectionState {
        case .codexMissing:
            return "terminal"
        case .authenticationRequired:
            return "person.crop.circle.badge.exclamationmark"
        case .unsupported:
            return "arrow.down.circle"
        default:
            return "wifi.exclamationmark"
        }
    }
}

struct CodexSettingsView: View {
    @ObservedObject var settings: CodexExecutableSettings
    let didSelectExecutable: () -> Void

    @State private var selectionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Codex executable")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("AgentQuota uses this executable for quota reporting.")
                    .foregroundStyle(.secondary)
                Text(settings.selectedExecutableURL?.path ?? "No executable selected")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            if let error = selectionError ?? settings.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Choose Codex…") {
                    chooseExecutable()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Choose the Codex executable"
        panel.message = "Select the Codex command AgentQuota should use."
        panel.prompt = "Use Codex"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.selectedExecutableURL?.deletingLastPathComponent()

        guard panel.runModal() == .OK, let executableURL = panel.url else {
            return
        }

        do {
            try settings.selectExecutable(executableURL)
            selectionError = nil
            didSelectExecutable()
        } catch {
            selectionError = error.localizedDescription
        }
    }
}

private struct QuotaWindowView: View {
    let window: QuotaWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.durationLabel == "Quota window" ? "Quota window" : "\(window.durationLabel) quota")
                    .font(.headline)
                Spacer()
                Text("\(window.remainingPercent)% remaining now")
                    .font(.headline)
                    .monospacedDigit()
            }

            ZStack(alignment: .bottomLeading) {
                QuotaUsageBar(
                    usedPercent: Double(100 - window.remainingPercent),
                    projection: projection
                )
                usageLegend
                    .padding(.trailing, 100)
            }

            VStack(alignment: .leading, spacing: 4) {
                if projection != nil {
                    Text("At this pace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(forecastSummary)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(forecastColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .help(forecastHelp)
            .accessibilityElement(children: .combine)

            Text(window.resetCountdown(relativeTo: now))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .help(window.localResetDescription())
        }
    }

    private var forecast: QuotaExhaustionForecast {
        window.exhaustionForecast(relativeTo: now)
    }

    private var projection: QuotaUsageProjection? {
        window.usageProjection(relativeTo: now)
    }

    private var usageLegend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "square.fill")
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text("Used so far")
            }
            if let projection {
                HStack(spacing: 5) {
                    Canvas { context, size in
                        drawQuotaForecast(in: CGRect(origin: .zero, size: size), color: .blue, context: context)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .frame(width: 13, height: 13)
                    .accessibilityHidden(true)
                    Text("Expected use")
                }
                .help("\(QuotaUsageProjection.percentDescription(projection.projectedUsedPercent - projection.usedPercent)) more expected before reset")
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help("\(100 - window.remainingPercent)% used so far")
    }

    private var forecastSummary: String {
        guard let projection else { return forecast.title }
        if projection.overQuotaPercent > 0 {
            return "\(QuotaUsageProjection.percentDescription(projection.overQuotaPercent)) over quota by reset"
        }
        if case .unusedAtReset = forecast {
            return "\(QuotaUsageProjection.percentDescription(projection.unusedPercent)) unused at reset"
        }
        return "On track until reset"
    }

    private var forecastHelp: String {
        var text = "Based on average usage since this quota window began."
        if let projection {
            text += "\n\(QuotaUsageProjection.percentDescription(projection.projectedUsedPercent)) total usage expected by reset."
        }
        if let runOut = forecast.localRunOutDescription() {
            text += "\n\(forecast.statusDescription(relativeTo: now))\nEstimated run-out: \(runOut)"
        }
        if let projection, projection.projectedUsedPercent > QuotaUsageBar.scaleMaximum {
            text += "\nThe bar continues beyond its visible 125% scale."
        }
        return text
    }

    private var forecastColor: Color {
        switch forecast {
        case .unusedAtReset:
            return .orange
        case .runsOut, .exhausted:
            return .red
        case .lastsUntilReset, .unavailable:
            return .secondary
        }
    }
}

/// Fixed scale leaves room for projected demand beyond the quota without
/// moving the 100% marker as the forecast changes.
private struct QuotaUsageBar: View {
    static let scaleMaximum = 125.0

    let usedPercent: Double
    let projection: QuotaUsageProjection?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let limitX = width * 100 / Self.scaleMaximum
            let endpointX = width * min(projection?.projectedUsedPercent ?? usedPercent, Self.scaleMaximum)
                / Self.scaleMaximum

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let track = CGRect(x: 0, y: 5, width: size.width, height: 20)
                    let outline = RoundedRectangle(cornerRadius: 7).path(in: track)
                    context.fill(outline, with: .color(.primary.opacity(0.10)))
                    context.stroke(outline, with: .color(.primary.opacity(0.15)), lineWidth: 0.5)

                    var fills = context
                    fills.clip(to: outline)
                    fills.fill(
                        Path(CGRect(x: 0, y: track.minY,
                                    width: size.width * usedPercent / Self.scaleMaximum,
                                    height: track.height)),
                        with: .color(.blue)
                    )
                    if let projection {
                        let forecastStart = size.width * usedPercent / Self.scaleMaximum
                        let forecastEnd = size.width * min(projection.projectedUsedPercent, 100)
                            / Self.scaleMaximum
                        drawQuotaForecast(in: CGRect(x: forecastStart, y: track.minY,
                                                     width: max(forecastEnd - forecastStart, 0), height: track.height),
                                          color: .blue, context: fills)
                        if projection.overQuotaPercent > 0 {
                            drawQuotaForecast(in: CGRect(x: limitX, y: track.minY,
                                                         width: max(endpointX - limitX, 0), height: track.height),
                                              color: .red, context: fills)
                        }
                    }

                    var limit = Path()
                    limit.move(to: CGPoint(x: limitX, y: 0))
                    limit.addLine(to: CGPoint(x: limitX, y: 30))
                    context.stroke(limit, with: .color(.primary.opacity(0.85)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

                }

                if let projection, projection.projectedUsedPercent > Self.scaleMaximum {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .position(x: width - 9, y: 15)
                }

                Text("Quota limit")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: limitX, y: 41)
            }
        }
        .frame(height: 49)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quota usage and forecast")
        .accessibilityValue(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var text = "\(QuotaUsageProjection.percentDescription(usedPercent)) used. Quota limit 100%."
        if let projection {
            text += " Projected usage at reset: \(QuotaUsageProjection.percentDescription(projection.projectedUsedPercent))."
            if projection.overQuotaPercent > 0 {
                text += " \(QuotaUsageProjection.percentDescription(projection.overQuotaPercent)) over quota."
            } else {
                text += " \(QuotaUsageProjection.percentDescription(projection.unusedPercent)) unused at reset."
            }
        } else {
            text += " Forecast unavailable."
        }
        return text
    }

}

private func drawQuotaForecast(in rect: CGRect, color: Color, context: GraphicsContext) {
    guard rect.width > 0 else { return }
    var clipped = context
    clipped.clip(to: Path(rect))
    clipped.fill(Path(rect), with: .color(color.opacity(0.40)))
    clipped.fill(Path(rect), with: .color(.white.opacity(0.35)))
    var lines = Path()
    for x in stride(from: rect.minX - rect.height, through: rect.maxX, by: 6) {
        lines.move(to: CGPoint(x: x, y: rect.maxY))
        lines.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
    }
    clipped.stroke(lines, with: .color(color.opacity(0.85)), lineWidth: 1)
}
