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
            homeDirectory: temporaryDirectory,
            systemDirectories: []
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
            homeDirectory: temporaryDirectory,
            systemDirectories: []
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

    func testPrefersDefaultExecutableOverWrapperAndPersistsIt() throws {
        let defaultBin = temporaryDirectory.appending(path: "default-bin", directoryHint: .isDirectory)
        let defaultCodex = try createCodex(in: defaultBin, executable: true)
        let wrapperBin = temporaryDirectory.appending(path: ".superset/bin", directoryHint: .isDirectory)
        _ = try createCodex(in: wrapperBin, executable: true)
        let configuration = CodexExecutableConfigurationStore(
            homeDirectory: temporaryDirectory
        )
        let locator = CodexLocator(
            environment: ["PATH": wrapperBin.path],
            homeDirectory: temporaryDirectory,
            systemDirectories: [defaultBin.path],
            configurationStore: configuration
        )

        let located = try locator.locate()

        XCTAssertEqual(located.path, defaultCodex.path)
        XCTAssertEqual(try configuration.load()?.path, defaultCodex.path)
    }

    func testSavedExecutableWinsOverDiscovery() throws {
        let selectedBin = temporaryDirectory.appending(path: "selected-bin", directoryHint: .isDirectory)
        let selectedCodex = try createCodex(in: selectedBin, executable: true)
        let defaultBin = temporaryDirectory.appending(path: "default-bin", directoryHint: .isDirectory)
        _ = try createCodex(in: defaultBin, executable: true)
        let configuration = CodexExecutableConfigurationStore(
            homeDirectory: temporaryDirectory
        )
        try configuration.save(executableURL: selectedCodex)
        let locator = CodexLocator(
            environment: ["PATH": ""],
            homeDirectory: temporaryDirectory,
            systemDirectories: [defaultBin.path],
            configurationStore: configuration
        )

        XCTAssertEqual(try locator.locate().path, selectedCodex.path)
    }

    func testPersistsStableSymlinkPath() throws {
        let versionedBin = temporaryDirectory.appending(path: "versions/1.0", directoryHint: .isDirectory)
        let realCodex = try createCodex(in: versionedBin, executable: true)
        let stableBin = temporaryDirectory.appending(path: "stable-bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stableBin, withIntermediateDirectories: true)
        let stableCodex = stableBin.appending(path: "codex", directoryHint: .notDirectory)
        try FileManager.default.createSymbolicLink(at: stableCodex, withDestinationURL: realCodex)
        let configuration = CodexExecutableConfigurationStore(
            homeDirectory: temporaryDirectory
        )
        let locator = CodexLocator(
            environment: ["PATH": ""],
            homeDirectory: temporaryDirectory,
            systemDirectories: [stableBin.path],
            configurationStore: configuration
        )

        XCTAssertEqual(try locator.locate().path, stableCodex.path)
        XCTAssertEqual(try configuration.load()?.path, stableCodex.path)
    }

    func testUnavailableSavedExecutableDoesNotSilentlySwitch() throws {
        let unavailable = temporaryDirectory.appending(path: "missing/codex")
        let defaultBin = temporaryDirectory.appending(path: "default-bin", directoryHint: .isDirectory)
        _ = try createCodex(in: defaultBin, executable: true)
        let configuration = CodexExecutableConfigurationStore(
            homeDirectory: temporaryDirectory
        )
        try configuration.save(executableURL: unavailable)
        let locator = CodexLocator(
            environment: ["PATH": ""],
            homeDirectory: temporaryDirectory,
            systemDirectories: [defaultBin.path],
            configurationStore: configuration
        )

        XCTAssertThrowsError(try locator.locate()) { error in
            XCTAssertEqual(
                error as? CodexLocatorError,
                .configuredExecutableUnavailable(path: unavailable.path)
            )
        }
    }

    func testUserSelectionIsValidatedAndPersisted() throws {
        let selectedBin = temporaryDirectory.appending(path: "selected-bin", directoryHint: .isDirectory)
        let selectedCodex = try createCodex(in: selectedBin, executable: true)
        let configuration = CodexExecutableConfigurationStore(
            homeDirectory: temporaryDirectory
        )
        let locator = CodexLocator(
            environment: ["PATH": ""],
            homeDirectory: temporaryDirectory,
            systemDirectories: [],
            configurationStore: configuration
        )

        try locator.selectExecutable(selectedCodex)

        XCTAssertEqual(try configuration.load()?.path, selectedCodex.path)
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
