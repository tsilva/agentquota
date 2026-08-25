import Foundation
import XCTest
@testable import AgentQuota

@MainActor
final class QuotaStoreTests: XCTestCase {
    func testSuccessfulManualRefreshUpdatesState() async {
        let client = FakeQuotaClient(readResults: [.success(snapshot(remaining: 59))])
        let store = QuotaStore(clientFactory: { client })

        await store.refresh()

        XCTAssertEqual(store.connectionState, .connected)
        XCTAssertEqual(store.menuBarText, "59%")
        XCTAssertEqual(client.connectCount, 1)
        XCTAssertEqual(client.readCount, 1)
    }

    func testRollingUpdateDebouncesIntoFreshRead() async throws {
        let client = FakeQuotaClient(readResults: [
            .success(snapshot(remaining: 75)),
            .success(snapshot(remaining: 62))
        ])
        let store = QuotaStore(clientFactory: { client })
        await store.refresh()

        client.emit(.rateLimitsUpdated)
        client.emit(.rateLimitsUpdated)
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(client.readCount, 2)
        XCTAssertEqual(store.menuBarText, "62%")
    }

    func testRetainsSnapshotAndMarksItStaleAfterFailure() async {
        let base = Date(timeIntervalSince1970: 10_000)
        var now = base
        let client = FakeQuotaClient(readResults: [
            .success(snapshot(remaining: 40, updatedAt: base)),
            .failure(CodexQuotaClientError.networkUnavailable("offline"))
        ])
        let store = QuotaStore(clientFactory: { client }, now: { now })
        await store.refresh()

        now = base.addingTimeInterval(121)
        await store.refresh()

        XCTAssertEqual(store.menuBarText, "40%")
        XCTAssertTrue(store.isSnapshotStale)
        guard case .failed = store.connectionState else {
            return XCTFail("Expected retained snapshot with failed state")
        }
    }

    func testAuthenticationFailureIsActionableAndDoesNotDiscardData() async {
        let client = FakeQuotaClient(
            connectResults: [.failure(CodexQuotaClientError.authenticationRequired)]
        )
        let store = QuotaStore(clientFactory: { client })

        await store.refresh()

        guard case let .authenticationRequired(message) = store.connectionState else {
            return XCTFail("Expected authentication state")
        }
        XCTAssertTrue(message.contains("codex login"))
        XCTAssertNil(store.snapshot)
    }

    func testUnexpectedProcessExitReconnectsAndRefreshes() async throws {
        let client = FakeQuotaClient(readResults: [
            .success(snapshot(remaining: 80)),
            .success(snapshot(remaining: 70))
        ])
        let store = QuotaStore(clientFactory: { client })
        await store.refresh()

        client.emit(.processExited(9))
        try await Task.sleep(for: .milliseconds(1_300))

        XCTAssertEqual(store.connectionState, .connected)
        XCTAssertGreaterThanOrEqual(client.connectCount, 2)
        XCTAssertEqual(store.menuBarText, "70%")
    }

    func testMissingCodexShowsRetryState() async {
        let store = QuotaStore {
            throw CodexLocatorError.notFound(searchedPaths: ["/missing/codex"])
        }

        await store.refresh()

        guard case let .codexMissing(message) = store.connectionState else {
            return XCTFail("Expected missing Codex state")
        }
        XCTAssertTrue(message.contains("not found"))
    }

    private func snapshot(
        remaining: Int,
        updatedAt: Date = Date(timeIntervalSince1970: 10_000)
    ) -> QuotaSnapshot {
        QuotaSnapshot(
            planName: "Pro",
            windows: [
                QuotaWindow(
                    id: "primary",
                    usedPercent: 100 - remaining,
                    durationMinutes: 300,
                    resetsAt: Date(timeIntervalSince1970: 20_000)
                )
            ],
            updatedAt: updatedAt
        )
    }
}

private final class FakeQuotaClient: CodexQuotaClienting, @unchecked Sendable {
    let events: AsyncStream<CodexQuotaEvent>

    private let continuation: AsyncStream<CodexQuotaEvent>.Continuation
    private let lock = NSLock()
    private var connectResults: [Result<Void, Error>]
    private var readResults: [Result<QuotaSnapshot, Error>]
    private var _connectCount = 0
    private var _readCount = 0

    init(
        connectResults: [Result<Void, Error>] = [.success(())],
        readResults: [Result<QuotaSnapshot, Error>] = []
    ) {
        self.connectResults = connectResults
        self.readResults = readResults
        let pair = AsyncStream<CodexQuotaEvent>.makeStream(bufferingPolicy: .unbounded)
        events = pair.stream
        continuation = pair.continuation
    }

    var connectCount: Int { lock.withLock { _connectCount } }
    var readCount: Int { lock.withLock { _readCount } }

    func connect() async throws {
        let result: Result<Void, Error> = lock.withLock {
            _connectCount += 1
            return connectResults.isEmpty ? .success(()) : connectResults.removeFirst()
        }
        try result.get()
    }

    func readQuota() async throws -> QuotaSnapshot {
        let result: Result<QuotaSnapshot, Error> = lock.withLock {
            _readCount += 1
            return readResults.isEmpty
                ? .failure(CodexQuotaClientError.transport("No fake snapshot"))
                : readResults.removeFirst()
        }
        return try result.get()
    }

    func disconnect() {}

    func emit(_ event: CodexQuotaEvent) {
        continuation.yield(event)
    }
}
