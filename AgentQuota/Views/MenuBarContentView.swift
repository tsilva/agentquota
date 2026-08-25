import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: QuotaStore

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
        .frame(width: 350)
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

private struct QuotaWindowView: View {
    let window: QuotaWindow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(window.durationLabel) quota")
                    .font(.headline)
                Spacer()
                Text("\(window.remainingPercent)% remaining")
                    .font(.headline)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.10))
                    Capsule()
                        .fill(progressColor)
                        .frame(
                            width: geometry.size.width
                                * CGFloat(window.remainingPercent) / 100
                        )
                }
            }
                .frame(height: 8)
                .accessibilityLabel("\(window.durationLabel) quota")
                .accessibilityValue("\(window.remainingPercent) percent remaining")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(window.resetCountdown(relativeTo: now))
                Spacer(minLength: 8)
                Text(window.localResetDescription())
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(forecast.statusDescription(relativeTo: now))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let localRunOutDescription = forecast.localRunOutDescription() {
                    Text(localRunOutDescription)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.caption)
            .foregroundStyle(forecastColor)
            .monospacedDigit()
            .accessibilityElement(children: .combine)
        }
    }

    private var forecast: QuotaExhaustionForecast {
        window.exhaustionForecast(relativeTo: now)
    }

    private var forecastColor: Color {
        switch forecast {
        case .runsOut:
            return .orange
        case .exhausted:
            return .red
        case .lastsUntilReset, .unavailable:
            return .secondary
        }
    }

    private var progressColor: Color {
        switch window.remainingPercent {
        case 0..<20:
            return .red
        case 20..<40:
            return .orange
        default:
            return .blue
        }
    }
}
