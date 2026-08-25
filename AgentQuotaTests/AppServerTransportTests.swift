import Darwin
import Foundation
import XCTest
@testable import AgentQuota

final class AppServerTransportTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "AgentQuotaTransportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testCorrelatesOutOfOrderResponses() async throws {
        let script = try makeExecutable(named: "correlate", body: #"""
        first_id=""
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\1/')
          method=$(printf '%s' "$line" | sed -E 's/.*"method":"([^"]+)".*/\1/')
          if [ "$method" = "first" ]; then
            first_id="$id"
          elif [ "$method" = "second" ]; then
            printf '{"id":%s,"result":"second-result"}\n' "$id"
            printf '{"id":%s,"result":"first-result"}\n' "$first_id"
          fi
        done
        """#)
        let transport = AppServerTransport(executableURL: script)
        try transport.start()
        defer { transport.stop() }

        async let first = transport.request(method: "first", params: .null)
        try await Task.sleep(for: .milliseconds(20))
        async let second = transport.request(method: "second", params: .null)

        let values = try await (first, second)
        XCTAssertEqual(values.0, .string("first-result"))
        XCTAssertEqual(values.1, .string("second-result"))
    }

    func testRequestTimeout() async throws {
        let script = try makeExecutable(named: "timeout", body: #"""
        while IFS= read -r line; do
          :
        done
        """#)
        let transport = AppServerTransport(executableURL: script, timeout: .milliseconds(50))
        try transport.start()
        defer { transport.stop() }

        do {
            _ = try await transport.request(method: "never", params: .null)
            XCTFail("Expected request timeout")
        } catch let error as AppServerTransportError {
            guard case let .timedOut(method) = error else {
                return XCTFail("Expected timeout, got \(error)")
            }
            XCTAssertEqual(method, "never")
        }
    }

    func testMalformedLineFailsPendingRequest() async throws {
        let script = try makeExecutable(named: "malformed", body: #"""
        IFS= read -r line
        printf 'not-json\n'
        while IFS= read -r line; do :; done
        """#)
        let transport = AppServerTransport(executableURL: script)
        try transport.start()
        defer { transport.stop() }

        do {
            _ = try await transport.request(method: "malformed", params: .null)
            XCTFail("Expected malformed response")
        } catch let error as AppServerTransportError {
            guard case .malformedResponse = error else {
                return XCTFail("Expected malformed response, got \(error)")
            }
        }
    }

    func testUnknownResponseIsIgnoredAndReported() async throws {
        let script = try makeExecutable(named: "unknown", body: #"""
        IFS= read -r line
        id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\1/')
        printf '{"id":999,"result":null}\n'
        printf '{"id":%s,"result":{"ok":true}}\n' "$id"
        while IFS= read -r line; do :; done
        """#)
        let transport = AppServerTransport(executableURL: script)
        try transport.start()
        defer { transport.stop() }
        let eventTask = Task { () -> AppServerEvent? in
            for await event in transport.events {
                return event
            }
            return nil
        }

        let response = try await transport.request(method: "known", params: .null)
        XCTAssertEqual(response, .object(["ok": .bool(true)]))
        guard case .unknownMessage = await eventTask.value else {
            return XCTFail("Expected an unknown-message event")
        }
    }

    func testCanRestartAfterCleanStop() async throws {
        let script = try makeExecutable(named: "restart", body: #"""
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":([0-9]+).*/\1/')
          printf '{"id":%s,"result":{"ok":true}}\n' "$id"
        done
        """#)
        let transport = AppServerTransport(executableURL: script)

        try transport.start()
        let beforeStop = try await transport.request(method: "before-stop", params: .null)
        XCTAssertEqual(beforeStop, .object(["ok": .bool(true)]))
        transport.stop()

        try transport.start()
        let afterRestart = try await transport.request(method: "after-restart", params: .null)
        XCTAssertEqual(afterRestart, .object(["ok": .bool(true)]))
        transport.stop()
    }

    private func makeExecutable(named name: String, body: String) throws -> URL {
        let file = temporaryDirectory.appending(path: name, directoryHint: .notDirectory)
        let script = "#!/bin/sh\n\(body)\n"
        try Data(script.utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: file.path
        )
        return file
    }
}
