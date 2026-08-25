import Foundation

enum CodexQuotaEvent: Equatable, Sendable {
    case rateLimitsUpdated
    case malformedResponse(String)
    case processExited(Int32)
}

enum CodexQuotaClientError: LocalizedError, Equatable, Sendable {
    case authenticationRequired
    case unsupportedMethod
    case malformedResponse
    case networkUnavailable(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Codex is not signed in. Run `codex login` in Terminal, then choose Retry."
        case .unsupportedMethod:
            return "This Codex CLI does not support quota reporting. Update Codex, then choose Retry."
        case .malformedResponse:
            return "Codex returned quota data AgentQuota could not understand. Update Codex or retry."
        case let .networkUnavailable(message):
            return "Codex could not reach the network: \(message)"
        case let .transport(message):
            return message
        }
    }
}

protocol CodexQuotaClienting: AnyObject, Sendable {
    var events: AsyncStream<CodexQuotaEvent> { get }
    func connect() async throws
    func readQuota() async throws -> QuotaSnapshot
    func disconnect()
}

final class CodexQuotaClient: CodexQuotaClienting, @unchecked Sendable {
    let events: AsyncStream<CodexQuotaEvent>

    private let transport: any AppServerTransporting
    private let now: @Sendable () -> Date
    private let eventContinuation: AsyncStream<CodexQuotaEvent>.Continuation
    private let stateLock = NSLock()
    private var initialized = false
    private var eventTask: Task<Void, Never>?

    init(
        transport: any AppServerTransporting,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.now = now
        let pair = AsyncStream<CodexQuotaEvent>.makeStream(bufferingPolicy: .bufferingNewest(50))
        events = pair.stream
        eventContinuation = pair.continuation

        let transportEvents = transport.events
        eventTask = Task { [weak self] in
            for await event in transportEvents {
                guard !Task.isCancelled else {
                    break
                }
                self?.handle(event)
            }
        }
    }

    deinit {
        eventTask?.cancel()
        transport.stop()
        eventContinuation.finish()
    }

    func connect() async throws {
        if isInitialized {
            return
        }

        do {
            try transport.start()
            _ = try await transport.request(
                method: "initialize",
                params: .object([
                    "clientInfo": .object([
                        "name": .string("agentquota"),
                        "title": .string("AgentQuota"),
                        "version": .string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    ]),
                    "capabilities": .object([
                        "experimentalApi": .bool(false)
                    ])
                ])
            )
            try transport.notify(method: "initialized", params: nil)
            setInitialized(true)
        } catch {
            setInitialized(false)
            transport.stop()
            throw map(error)
        }
    }

    func readQuota() async throws -> QuotaSnapshot {
        if !isInitialized {
            try await connect()
        }

        do {
            let response = try await transport.request(
                method: "account/rateLimits/read",
                params: .null
            )
            return try CodexQuotaTranslator.snapshot(from: response, updatedAt: now())
        } catch {
            throw map(error)
        }
    }

    func disconnect() {
        setInitialized(false)
        transport.stop()
    }

    private var isInitialized: Bool {
        stateLock.withLock { initialized }
    }

    private func setInitialized(_ value: Bool) {
        stateLock.withLock {
            initialized = value
        }
    }

    private func handle(_ event: AppServerEvent) {
        switch event {
        case let .notification(method, _):
            if method == "account/rateLimits/updated" {
                eventContinuation.yield(.rateLimitsUpdated)
            }
        case let .malformedResponse(message):
            eventContinuation.yield(.malformedResponse(message))
        case .unknownMessage:
            break
        case let .processExited(status):
            setInitialized(false)
            eventContinuation.yield(.processExited(status))
        }
    }

    private func map(_ error: Error) -> CodexQuotaClientError {
        if let clientError = error as? CodexQuotaClientError {
            return clientError
        }

        if let transportError = error as? AppServerTransportError {
            switch transportError {
            case let .rpc(code, message, _):
                if code == -32_601 {
                    return .unsupportedMethod
                }

                let lowercaseMessage = message.lowercased()
                if lowercaseMessage.contains("auth")
                    || lowercaseMessage.contains("login")
                    || lowercaseMessage.contains("logged in")
                    || lowercaseMessage.contains("unauthorized") {
                    return .authenticationRequired
                }
                if lowercaseMessage.contains("network")
                    || lowercaseMessage.contains("internet")
                    || lowercaseMessage.contains("connection") {
                    return .networkUnavailable(message)
                }
                return .transport(message)
            case .malformedResponse:
                return .malformedResponse
            default:
                return .transport(transportError.localizedDescription)
            }
        }

        if error is DecodingError || error is EncodingError {
            return .malformedResponse
        }
        return .transport(error.localizedDescription)
    }
}

enum CodexQuotaTranslator {
    static func snapshot(from value: JSONValue, updatedAt: Date) throws -> QuotaSnapshot {
        let data = try JSONEncoder().encode(value)
        let response: ProtocolRateLimitsResponse
        do {
            response = try JSONDecoder().decode(ProtocolRateLimitsResponse.self, from: data)
        } catch {
            throw CodexQuotaClientError.malformedResponse
        }

        let selected = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
        var windows: [QuotaWindow] = []

        if let primary = selected.primary {
            windows.append(primary.domainWindow(id: "primary"))
        }
        if let secondary = selected.secondary {
            windows.append(secondary.domainWindow(id: "secondary"))
        }

        return QuotaSnapshot(
            planName: selected.planType?.quotaPlanDisplayName ?? "Unknown plan",
            windows: windows,
            updatedAt: updatedAt
        )
    }
}

private struct ProtocolRateLimitsResponse: Decodable {
    let rateLimits: ProtocolRateLimitSnapshot
    let rateLimitsByLimitId: [String: ProtocolRateLimitSnapshot]?
}

private struct ProtocolRateLimitSnapshot: Decodable {
    let planType: String?
    let primary: ProtocolRateLimitWindow?
    let secondary: ProtocolRateLimitWindow?
}

private struct ProtocolRateLimitWindow: Decodable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int64?

    func domainWindow(id: String) -> QuotaWindow {
        QuotaWindow(
            id: id,
            usedPercent: usedPercent,
            durationMinutes: windowDurationMins,
            resetsAt: resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}
