import AppKit
import XCTest
@testable import AgentQuota

@MainActor
final class AgentQuotaAppTests: XCTestCase {
    func testStatusItemRegistersVisibleNotchSafePlacement() async throws {
        let app = AgentQuotaApp()
        app.configureStatusItem()
        defer { app.removeStatusItem() }

        let statusItem = try XCTUnwrap(app.statusItem)
        let button = try XCTUnwrap(app.statusItem?.button)
        XCTAssertEqual(statusItem.autosaveName, AgentQuotaApp.statusItemAutosaveName)
        XCTAssertTrue(statusItem.isVisible)
        XCTAssertEqual(
            UserDefaults.standard.object(
                forKey: AgentQuotaApp.statusItemPreferredPositionKey
            ) as? Int,
            0
        )
        XCTAssertEqual(button.title, "")
        XCTAssertEqual(button.imageScaling, .scaleNone)
        XCTAssertEqual(button.image?.size, MenuBarQuotaMeter.size)
        XCTAssertFalse(try XCTUnwrap(button.image).isTemplate)
        XCTAssertGreaterThan(button.frame.height, 0)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while button.window?.frame.height == 0, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertTrue(button.window?.isVisible == true)
        XCTAssertGreaterThan(button.window?.frame.height ?? 0, 0)
    }

    func testMenuBarQuotaMeterKeepsAFixedFootprint() {
        let loading = MenuBarQuotaMeter.image(remainingPercent: nil, isStale: false)
        let partial = MenuBarQuotaMeter.image(remainingPercent: 91, isStale: false)
        let full = MenuBarQuotaMeter.image(remainingPercent: 100, isStale: false)
        let stale = MenuBarQuotaMeter.image(remainingPercent: 91, isStale: true)

        XCTAssertEqual(MenuBarQuotaMeter.size, NSSize(width: 44, height: 19))
        XCTAssertEqual(loading.size, MenuBarQuotaMeter.size)
        XCTAssertEqual(partial.size, MenuBarQuotaMeter.size)
        XCTAssertEqual(full.size, MenuBarQuotaMeter.size)
        XCTAssertEqual(stale.size, MenuBarQuotaMeter.size)
    }

    func testExecutableSettingsUpdatesSelectedPath() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "AgentQuotaSettingsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let bin = temporaryDirectory.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let executable = bin.appending(path: "codex", directoryHint: .notDirectory)
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )
        let configuration = CodexExecutableConfigurationStore(
            homeDirectory: temporaryDirectory
        )
        let settings = CodexExecutableSettings(
            locator: CodexLocator(
                environment: ["PATH": ""],
                homeDirectory: temporaryDirectory,
                systemDirectories: [],
                configurationStore: configuration
            )
        )

        try settings.selectExecutable(executable)

        XCTAssertEqual(settings.selectedExecutableURL?.path, executable.path)
        XCTAssertEqual(try configuration.load()?.path, executable.path)
        XCTAssertNil(settings.errorMessage)
    }
}
