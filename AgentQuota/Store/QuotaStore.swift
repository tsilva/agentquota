import Combine
import Foundation

enum QuotaConnectionState: Equatable, Sendable {
    case idle
    case locating
    case connecting
    case connected
    case retrying(seconds: Int)
    case codexMissing(String)
    case authenticationRequired(String)
    case unsupported(String)
    case failed(String)
    case stopped

    var label: String {
        switch self {
        case .idle:
            return "Waiting"
        case .locating:
            return "Finding Codex"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case let .retrying(seconds):
            return "Retrying in \(seconds)s"
        case .codexMissing:
            return "Codex not found"
        case .authenticationRequired:
            return "Sign-in required"
        case .unsupported:
            return "Update required"
        case .failed:
            return "Connection issue"
        case .stopped:
            return "Stopped"
        }
    }

    var recoveryMessage: String? {
        switch self {
        case let .codexMissing(message),
             let .authenticationRequired(message),
             let .unsupported(message),
             let .failed(message):
            return message
        default:
            return nil
        }
    }

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

@MainActor
final class QuotaStore: ObservableObject {
    typealias ClientFactory = @MainActor () throws -> any CodexQuotaClienting

    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var connectionState: QuotaConnectionState = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var currentDate: Date

    private let clientFactory: ClientFactory
    private let now: @MainActor () -> Date
    private var client: (any CodexQuotaClienting)?
    private var eventTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var staleClockTask: Task<Void, Never>?
    private var rollingRefreshTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var quotaValuesUpdatedAt: Date?
    private var hasStarted = false

    init(
        clientFactory: @escaping ClientFactory,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.clientFactory = clientFactory
        self.now = now
        currentDate = now()
    }

    deinit {
        eventTask?.cancel()
        reconnectTask?.cancel()
        pollTask?.cancel()
        staleClockTask?.cancel()
        rollingRefreshTask?.cancel()
        refreshTask?.cancel()
        client?.disconnect()
    }

    var menuBarText: String {
        snapshot?.lowestRemainingPercent.map { "\($0)%" } ?? "—"
    }

    var isSnapshotStale: Bool {
        guard let snapshot else {
            return false
        }
        return currentDate.timeIntervalSince(snapshot.updatedAt) >= 120
    }

    var lastUpdatedDescription: String {
        guard let quotaValuesUpdatedAt else {
            return "Not updated yet"
        }

        let seconds = max(Int(currentDate.timeIntervalSince(quotaValuesUpdatedAt)), 0)
        switch seconds {
        case 0..<60:
            return "Updated now"
        case 60..<3_600:
            return "Updated \(seconds / 60)m ago"
        default:
            return "Updated \(seconds / 3_600)h ago"
        }
    }

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        staleClockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled else {
                    return
                }
                currentDate = now()
            }
        }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else {
                    return
                }
                await refresh()
            }
        }

        scheduleReconnect(immediate: true)
    }

    func popoverOpened() {
        Task { [weak self] in
            await self?.forceRefresh()
        }
    }

    func refresh() async {
        guard connectionState != .stopped else {
            return
        }

        if let refreshTask {
            await refreshTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await performRefresh()
            refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    func forceRefresh() async {
        if let refreshTask {
            await refreshTask.value
        }
        await refresh()
    }

    private func performRefresh() async {
        guard connectionState != .stopped else {
            return
        }

        do {
            if let client, connectionState.isConnected {
                try await readSnapshot(from: client)
                connectionState = .connected
            } else {
                try await connectAndRead()
            }
        } catch {
            if !apply(error) {
                scheduleReconnect(immediate: false)
            }
        }
    }

    func retry() {
        reconnectTask?.cancel()
        reconnectTask = nil
        discardClient()
        scheduleReconnect(immediate: true)
    }

    func shutdown() {
        guard connectionState != .stopped else {
            return
        }
        hasStarted = false
        eventTask?.cancel()
        reconnectTask?.cancel()
        pollTask?.cancel()
        staleClockTask?.cancel()
        rollingRefreshTask?.cancel()
        refreshTask?.cancel()
        eventTask = nil
        reconnectTask = nil
        pollTask = nil
        staleClockTask = nil
        rollingRefreshTask = nil
        refreshTask = nil
        client?.disconnect()
        client = nil
        connectionState = .stopped
    }

    private func scheduleReconnect(immediate: Bool) {
        guard reconnectTask == nil, connectionState != .stopped else {
            return
        }

        reconnectTask = Task { [weak self] in
            await self?.runReconnectLoop(immediate: immediate)
        }
    }

    private func runReconnectLoop(immediate: Bool) async {
        let initialDelays = immediate ? [0, 1, 2, 5] : [1, 2, 5]
        var attempt = 0

        while !Task.isCancelled {
            let delay = attempt < initialDelays.count ? initialDelays[attempt] : 30
            if delay > 0 {
                connectionState = .retrying(seconds: delay)
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    reconnectTask = nil
                    return
                }
            }

            do {
                try await connectAndRead()
                reconnectTask = nil
                return
            } catch {
                if apply(error) {
                    reconnectTask = nil
                    return
                }
                client?.disconnect()
                attempt += 1
            }
        }

        reconnectTask = nil
    }

    private func connectAndRead() async throws {
        connectionState = .locating

        let activeClient: any CodexQuotaClienting
        if let client {
            activeClient = client
        } else {
            let newClient = try clientFactory()
            client = newClient
            observeEvents(from: newClient)
            activeClient = newClient
        }

        connectionState = .connecting
        try await activeClient.connect()
        try await readSnapshot(from: activeClient)
        connectionState = .connected
    }

    private func readSnapshot(from client: any CodexQuotaClienting) async throws {
        isRefreshing = true
        currentDate = now()
        defer { isRefreshing = false }
        let newSnapshot = try await client.readQuota()
        if snapshot?.planName != newSnapshot.planName
            || snapshot?.windows != newSnapshot.windows {
            quotaValuesUpdatedAt = newSnapshot.updatedAt
        }
        snapshot = newSnapshot
        currentDate = now()
    }

    private func observeEvents(from client: any CodexQuotaClienting) {
        eventTask?.cancel()
        let events = client.events
        eventTask = Task { [weak self] in
            for await event in events {
                guard let self, !Task.isCancelled else {
                    return
                }
                handle(event)
            }
        }
    }

    private func handle(_ event: CodexQuotaEvent) {
        switch event {
        case .rateLimitsUpdated:
            rollingRefreshTask?.cancel()
            rollingRefreshTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch {
                    return
                }
                await self?.refresh()
            }
        case let .malformedResponse(message):
            connectionState = .failed("\(message) AgentQuota will reconnect.")
            client?.disconnect()
            scheduleReconnect(immediate: false)
        case let .processExited(status):
            connectionState = .failed(
                "The Codex app-server exited unexpectedly (status \(status)). AgentQuota will reconnect."
            )
            scheduleReconnect(immediate: false)
        }
    }

    @discardableResult
    private func apply(_ error: Error) -> Bool {
        if let locatorError = error as? CodexLocatorError {
            connectionState = .codexMissing(locatorError.localizedDescription)
            return true
        }

        if let clientError = error as? CodexQuotaClientError {
            switch clientError {
            case .authenticationRequired:
                connectionState = .authenticationRequired(clientError.localizedDescription)
                return true
            case .unsupportedMethod:
                connectionState = .unsupported(clientError.localizedDescription)
                return true
            case .malformedResponse, .networkUnavailable, .transport:
                connectionState = .failed(clientError.localizedDescription)
                return false
            }
        }

        connectionState = .failed(error.localizedDescription)
        return false
    }

    private func discardClient() {
        eventTask?.cancel()
        eventTask = nil
        client?.disconnect()
        client = nil
    }
}
