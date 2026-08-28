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
        XCTAssertEqual(
            button.image?.size,
            MenuBarQuotaMeter.image(remainingPercent: nil, isStale: false).size
        )
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

    func testMenuBarQuotaMeterReclaimsUnusedPercentageWidth() {
        let loading = MenuBarQuotaMeter.image(remainingPercent: nil, isStale: false)
        let singleDigit = MenuBarQuotaMeter.image(remainingPercent: 9, isStale: false)
        let partial = MenuBarQuotaMeter.image(remainingPercent: 91, isStale: false)
        let partialAtSameWidth = MenuBarQuotaMeter.image(remainingPercent: 10, isStale: false)
        let full = MenuBarQuotaMeter.image(remainingPercent: 100, isStale: false)
        let stale = MenuBarQuotaMeter.image(remainingPercent: 91, isStale: true)

        XCTAssertEqual(MenuBarQuotaMeter.maximumSize, NSSize(width: 44, height: 19))
        XCTAssertEqual(loading.size, MenuBarQuotaMeter.maximumSize)
        XCTAssertEqual(full.size, MenuBarQuotaMeter.maximumSize)
        XCTAssertLessThan(partial.size.width, full.size.width)
        XCTAssertLessThan(singleDigit.size.width, partial.size.width)
        XCTAssertEqual(partialAtSameWidth.size, partial.size)
        XCTAssertEqual(stale.size, partial.size)
        XCTAssertEqual(singleDigit.size.height, MenuBarQuotaMeter.maximumSize.height)
        XCTAssertEqual(partial.size.height, MenuBarQuotaMeter.maximumSize.height)
    }

    func testVariableStatusItemUsesAdaptiveImageWidth() throws {
        let app = AgentQuotaApp()
        app.configureStatusItem()
        defer { app.removeStatusItem() }
        let button = try XCTUnwrap(app.statusItem?.button)

        button.image = MenuBarQuotaMeter.image(remainingPercent: 100, isStale: false)
        let fullWidth = button.intrinsicContentSize.width
        button.image = MenuBarQuotaMeter.image(remainingPercent: 94, isStale: false)

        XCTAssertLessThan(button.intrinsicContentSize.width, fullWidth)
    }

    func testMenuBarQuotaMeterCanRenderRepeatedly() {
        let samples: [(remainingPercent: Int?, isStale: Bool)] = [
            (nil, false),
            (0, false),
            (91, false),
            (100, false),
            (91, true),
        ]

        for iteration in 0..<2_000 {
            autoreleasepool {
                let sample = samples[iteration % samples.count]
                let image = MenuBarQuotaMeter.image(
                    remainingPercent: sample.remainingPercent,
                    isStale: sample.isStale
                )
                var proposedRect = NSRect(origin: .zero, size: image.size)

                XCTAssertNotNil(
                    image.cgImage(
                        forProposedRect: &proposedRect,
                        context: nil,
                        hints: nil
                    )
                )
            }
        }
    }

    func testMenuBarQuotaMeterDoesNotDeferDrawingToAppKit() throws {
        let image = MenuBarQuotaMeter.image(remainingPercent: 91, isStale: false)

        XCTAssertFalse(image.representations.contains { $0 is NSCustomImageRep })
        let bitmap = try XCTUnwrap(
            image.representations.first { $0 is NSBitmapImageRep } as? NSBitmapImageRep
        )

        var visiblePixelBounds = NSRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide
            where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                visiblePixelBounds = visiblePixelBounds.union(
                    NSRect(x: x, y: y, width: 1, height: 1)
                )
            }
        }

        XCTAssertGreaterThan(visiblePixelBounds.width, 30)
        XCTAssertGreaterThan(visiblePixelBounds.height, 8)
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
