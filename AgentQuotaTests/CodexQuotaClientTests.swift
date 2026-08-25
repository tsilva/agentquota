import Foundation
import XCTest
@testable import AgentQuota

final class CodexQuotaClientTests: XCTestCase {
    func testInitializationOrderingAndQuotaRead() async throws {
        let transport = FakeAppServerTransport(responses: [
            .success(.object(["userAgent": .string("Codex")])),
            .success(quotaResponse(codexUsed: 32, legacyUsed: 90))
        ])
        let now = Date(timeIntervalSince1970: 5_000)
        let client = CodexQuotaClient(transport: transport, now: { now })

        let snapshot = try await client.readQuota()

        XCTAssertEqual(transport.startedCount, 1)
        XCTAssertEqual(transport.requestedMethods, ["initialize", "account/rateLimits/read"])
        XCTAssertEqual(transport.notifications, ["initialized"])
        XCTAssertEqual(snapshot.lowestRemainingPercent, 68)
        XCTAssertEqual(snapshot.planName, "Pro")
        XCTAssertEqual(snapshot.updatedAt, now)
    }

    func testTranslatorFallsBackToLegacySnapshotAndAllowsMissingSecondary() throws {
        let snapshot = try CodexQuotaTranslator.snapshot(
            from: quotaResponse(codexUsed: nil, legacyUsed: 41),
            updatedAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(snapshot.windows.count, 1)
        XCTAssertEqual(snapshot.lowestRemainingPercent, 59)
    }

    func testUnknownPlanValueIsForwardCompatible() throws {
        let response: JSONValue = .object([
            "rateLimits": .object([
                "planType": .string("future_ultra"),
                "primary": protocolWindow(used: 5)
            ])
        ])

        let snapshot = try CodexQuotaTranslator.snapshot(from: response, updatedAt: Date())
        XCTAssertEqual(snapshot.planName, "Future Ultra")
    }

    func testUnsupportedMethodHasSpecificRecoveryError() async {
        let transport = FakeAppServerTransport(responses: [
            .success(.object([:])),
            .failure(AppServerTransportError.rpc(code: -32_601, message: "Method not found", data: nil))
        ])
        let client = CodexQuotaClient(transport: transport)

        do {
            _ = try await client.readQuota()
            XCTFail("Expected unsupported method")
        } catch {
            XCTAssertEqual(error as? CodexQuotaClientError, .unsupportedMethod)
        }
    }

    func testTimeoutIsSurfacedAsTransportFailure() async {
        let transport = FakeAppServerTransport(responses: [
            .failure(AppServerTransportError.timedOut(method: "initialize"))
        ])
        let client = CodexQuotaClient(transport: transport)

        do {
            try await client.connect()
            XCTFail("Expected timeout")
        } catch let error as CodexQuotaClientError {
            guard case let .transport(message) = error else {
                return XCTFail("Expected transport error")
            }
            XCTAssertTrue(message.contains("10 seconds"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRollingNotificationBecomesRefreshEvent() async throws {
        let transport = FakeAppServerTransport()
        let client = CodexQuotaClient(transport: transport)
        let eventTask = Task { () -> CodexQuotaEvent? in
            for await event in client.events {
                return event
            }
            return nil
        }

        transport.emit(.notification(method: "unknown/event", params: nil))
        transport.emit(.notification(method: "account/rateLimits/updated", params: .object([:])))

        let event = await eventTask.value
        XCTAssertEqual(event, .rateLimitsUpdated)
    }

    private func quotaResponse(codexUsed: Int?, legacyUsed: Int) -> JSONValue {
        var response: [String: JSONValue] = [
            "rateLimits": .object([
                "planType": .string("plus"),
                "primary": protocolWindow(used: legacyUsed)
            ])
        ]
        if let codexUsed {
            response["rateLimitsByLimitId"] = .object([
                "codex": .object([
                    "planType": .string("pro"),
                    "primary": protocolWindow(used: codexUsed)
                ])
            ])
        }
        return .object(response)
    }

    private func protocolWindow(used: Int) -> JSONValue {
        .object([
            "usedPercent": .integer(Int64(used)),
            "windowDurationMins": .integer(300),
            "resetsAt": .integer(10_000)
        ])
    }
}

final class FakeAppServerTransport: AppServerTransporting, @unchecked Sendable {
    let events: AsyncStream<AppServerEvent>

    private let continuation: AsyncStream<AppServerEvent>.Continuation
    private let lock = NSLock()
    private var responses: [Result<JSONValue, Error>]
    private var _startedCount = 0
    private var _requestedMethods: [String] = []
    private var _notifications: [String] = []

    init(responses: [Result<JSONValue, Error>] = []) {
        self.responses = responses
        let pair = AsyncStream<AppServerEvent>.makeStream(bufferingPolicy: .unbounded)
        events = pair.stream
        continuation = pair.continuation
    }

    var startedCount: Int { lock.withLock { _startedCount } }
    var requestedMethods: [String] { lock.withLock { _requestedMethods } }
    var notifications: [String] { lock.withLock { _notifications } }

    func start() throws {
        lock.withLock { _startedCount += 1 }
    }

    func request(method: String, params: JSONValue) async throws -> JSONValue {
        let result: Result<JSONValue, Error> = lock.withLock {
            _requestedMethods.append(method)
            return responses.isEmpty ? .success(.null) : responses.removeFirst()
        }
        return try result.get()
    }

    func notify(method: String, params: JSONValue?) throws {
        lock.withLock { _notifications.append(method) }
    }

    func stop() {}

    func emit(_ event: AppServerEvent) {
        continuation.yield(event)
    }
}
