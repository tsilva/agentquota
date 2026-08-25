import Foundation
import XCTest
@testable import AgentQuota

final class CodexLocatorTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "AgentQuotaTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testFindsExecutableOnInheritedPath() throws {
        let bin = temporaryDirectory.appending(path: "custom-bin", directoryHint: .isDirectory)
        let codex = try createCodex(in: bin, executable: true)
        let locator = CodexLocator(
            environment: ["PATH": bin.path],
            homeDirectory: temporaryDirectory
        )

        XCTAssertEqual(try locator.locate().path, codex.path)
    }

    func testFindsExecutableInKnownSupersetLocation() throws {
        let bin = temporaryDirectory.appending(path: ".superset/bin", directoryHint: .isDirectory)
        let codex = try createCodex(in: bin, executable: true)
        let locator = CodexLocator(
            environment: ["PATH": ""],
            homeDirectory: temporaryDirectory,
            systemDirectories: []
        )

        XCTAssertEqual(try locator.locate().path, codex.path)
    }

    func testSkipsNonExecutableFiles() throws {
        let firstBin = temporaryDirectory.appending(path: "first", directoryHint: .isDirectory)
        _ = try createCodex(in: firstBin, executable: false)
        let secondBin = temporaryDirectory.appending(path: "second", directoryHint: .isDirectory)
        let executable = try createCodex(in: secondBin, executable: true)
        let locator = CodexLocator(
            environment: ["PATH": "\(firstBin.path):\(secondBin.path)"],
            homeDirectory: temporaryDirectory
        )

        XCTAssertEqual(try locator.locate().path, executable.path)
    }

    func testReportsAllSearchedPathsWhenMissing() {
        let locator = CodexLocator(
            environment: ["PATH": ""],
            homeDirectory: temporaryDirectory,
            systemDirectories: []
        )

        XCTAssertThrowsError(try locator.locate()) { error in
            guard case let CodexLocatorError.notFound(paths) = error else {
                return XCTFail("Expected CodexLocatorError.notFound")
            }
            XCTAssertTrue(paths.contains(temporaryDirectory.appending(path: ".local/bin/codex").path))
        }
    }

    private func createCodex(in directory: URL, executable: Bool) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "codex", directoryHint: .notDirectory)
        XCTAssertTrue(FileManager.default.createFile(atPath: file.path, contents: Data()))
        try FileManager.default.setAttributes(
            [.posixPermissions: executable ? 0o755 : 0o644],
            ofItemAtPath: file.path
        )
        return file
    }
}
