import AppKit
import Combine
import SwiftUI

@MainActor
enum MenuBarQuotaMeter {
    private static let iconRect = NSRect(x: 1, y: 5, width: 26, height: 9)
    private static let valueX: CGFloat = 32
    private static let height: CGFloat = 19
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    // Match the popover's fixed scale and reserve the last fifth for overflow.
    private static let scaleMaximum = 125.0

    static var maximumSize: NSSize { size(value: "100%") }

    static func image(
        remainingPercent: Int?,
        isStale: Bool,
        projection: QuotaUsageProjection? = nil
    ) -> NSImage {
        let percent = remainingPercent.map { min(max($0, 0), 100) }
        let value = percent.map { "\($0)%" } ?? "—"
        let size = percent == nil ? maximumSize : size(value: value)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width * scale),
                pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            return NSImage(size: size)
        }

        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        context.shouldAntialias = true
        if isStale {
            // A clock identifies cached data without implying a current forecast.
            let symbol = NSImage(systemSymbolName: "clock", accessibilityDescription: "Cached quota")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.secondaryLabelColor])))
            symbol?.draw(in: NSRect(x: 7, y: 3, width: 13, height: 13))
        } else {
            drawUsage(remainingPercent: percent, projection: projection)
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: isStale ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let textSize = (value as NSString).size(withAttributes: attributes)
        (value as NSString).draw(
            at: NSPoint(x: valueX, y: floor((height - textSize.height) / 2)),
            withAttributes: attributes
        )
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        image.isTemplate = false
        return image
    }

    private static func drawUsage(remainingPercent: Int?, projection: QuotaUsageProjection?) {
        let outline = NSBezierPath(roundedRect: iconRect, xRadius: 3, yRadius: 3)
        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        outline.fill()
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        if let remainingPercent {
            let used = Double(100 - remainingPercent)
            let actual = NSRect(x: iconRect.minX, y: iconRect.minY,
                                width: iconRect.width * used / scaleMaximum, height: iconRect.height)
            (remainingPercent == 0 ? NSColor.systemRed : NSColor.systemBlue).setFill()
            actual.fill()
            if let projection {
                let start = iconRect.minX + actual.width
                let end = iconRect.minX + iconRect.width * min(projection.projectedUsedPercent, 100) / scaleMaximum
                drawForecast(in: NSRect(x: start, y: iconRect.minY,
                                        width: max(end - start, 0), height: iconRect.height), color: .systemBlue)
                if projection.overQuotaPercent > 0 {
                    let limitX = iconRect.minX + iconRect.width * 100 / scaleMaximum
                    let endpoint = iconRect.minX + iconRect.width * min(projection.projectedUsedPercent, scaleMaximum) / scaleMaximum
                    drawForecast(in: NSRect(x: limitX, y: iconRect.minY,
                                            width: max(endpoint - limitX, 0), height: iconRect.height), color: .systemRed)
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.labelColor.withAlphaComponent(0.3).setStroke()
        outline.lineWidth = 0.5
        outline.stroke()

        let limitX = iconRect.minX + iconRect.width * 100 / scaleMaximum
        let limit = NSBezierPath()
        limit.move(to: NSPoint(x: limitX, y: iconRect.minY - 1.5))
        limit.line(to: NSPoint(x: limitX, y: iconRect.maxY + 1.5))
        limit.lineWidth = 1
        NSColor.labelColor.withAlphaComponent(0.8).setStroke()
        limit.stroke()
    }

    private static func drawForecast(in rect: NSRect, color: NSColor) {
        guard rect.width > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        color.withAlphaComponent(0.4).setFill()
        rect.fill()
        NSColor.white.withAlphaComponent(0.35).setFill()
        rect.fill()
        color.withAlphaComponent(0.85).setStroke()
        let stripes = NSBezierPath()
        for x in stride(from: iconRect.minX - rect.height, through: rect.maxX, by: 3) {
            stripes.move(to: NSPoint(x: x, y: rect.minY))
            stripes.line(to: NSPoint(x: x + rect.height, y: rect.maxY))
        }
        stripes.lineWidth = 0.75
        stripes.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func size(value: String) -> NSSize {
        let valueWidth = (value as NSString).size(withAttributes: [.font: valueFont]).width
        return NSSize(width: ceil(valueX + valueWidth + 1), height: height)
    }
}

@MainActor
final class CodexExecutableSettings: ObservableObject {
    @Published private(set) var selectedExecutableURL: URL?
    @Published private(set) var errorMessage: String?

    private let locator: CodexLocator

    init(locator: CodexLocator = CodexLocator()) {
        self.locator = locator
        do {
            selectedExecutableURL = try locator.configuredExecutable()
        } catch {
            selectedExecutableURL = nil
            errorMessage = error.localizedDescription
        }
    }

    func locateExecutable() throws -> URL {
        do {
            let executableURL = try locator.locate()
            selectedExecutableURL = executableURL
            errorMessage = nil
            return executableURL
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func selectExecutable(_ executableURL: URL) throws {
        do {
            try locator.selectExecutable(executableURL)
            selectedExecutableURL = executableURL.standardizedFileURL
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}

@MainActor
final class AgentQuotaRuntime {
    static let shared = AgentQuotaRuntime()

    let executableSettings: CodexExecutableSettings
    let store: QuotaStore

    private init() {
        let executableSettings = CodexExecutableSettings()
        self.executableSettings = executableSettings
        store = QuotaStore {
            let executableURL = try executableSettings.locateExecutable()
            let transport = AppServerTransport(executableURL: executableURL)
            return CodexQuotaClient(transport: transport)
        }
    }
}

@MainActor
@main
final class AgentQuotaApp: NSObject, NSApplicationDelegate {
    static let statusItemAutosaveName = "AgentQuota"
    static let statusItemPreferredPositionKey =
        "NSStatusItem Preferred Position \(statusItemAutosaveName)"

    private(set) var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var statusObservation: AnyCancellable?
    private var settingsWindow: NSWindow?

    static func main() {
        let application = NSApplication.shared
        let delegate = AgentQuotaApp()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        configureStatusItem()
        configurePopover()
        observeStore()
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusObservation?.cancel()
        popover.performClose(nil)
        settingsWindow?.close()
        removeStatusItem()
        store.shutdown()
    }

    private var store: QuotaStore {
        AgentQuotaRuntime.shared.store
    }

    private var executableSettings: CodexExecutableSettings {
        AgentQuotaRuntime.shared.executableSettings
    }

    func configureStatusItem() {
        guard statusItem == nil else {
            return
        }

        // AppKit otherwise adds a new third-party item at the far left, where a
        // crowded MacBook menu bar can place it behind the camera housing.
        // A user-dragged saved position overrides this registration default.
        UserDefaults.standard.register(defaults: [
            Self.statusItemPreferredPositionKey: 0,
        ])
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.statusItemAutosaveName
        item.isVisible = true
        guard let button = item.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        statusItem = item
        updateStatusItem()
    }

    func removeStatusItem() {
        guard let statusItem else {
            return
        }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        let hostingController = NSHostingController(
            rootView: MenuBarContentView(
                store: store,
                openSettings: { [weak self] in
                    self?.showSettings()
                }
            )
        )
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    private func showSettings() {
        popover.performClose(nil)
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = CodexSettingsView(
            settings: executableSettings,
            didSelectExecutable: { [weak self] in
                self?.store.retry()
            }
        )
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AgentQuota Settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func observeStore() {
        statusObservation = Publishers.CombineLatest3(
            store.$snapshot,
            store.$currentDate,
            store.$connectionState
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.updateStatusItem()
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else {
            return
        }

        let isStale = store.isSnapshotStale
        let warning = store.menuBarForecastWarning
        let window = store.snapshot?.tightestWindow
        let projection = store.connectionState.isConnected && !isStale
            ? window?.usageProjection(relativeTo: store.currentDate) : nil
        button.image = MenuBarQuotaMeter.image(
            remainingPercent: window?.remainingPercent,
            isStale: isStale,
            projection: projection
        )
        button.title = ""
        button.toolTip = isStale
            ? "Codex quota is stale: \(store.menuBarText) remaining"
            : "Codex quota: \(store.menuBarText) remaining"
        if let window {
            button.toolTip? += "\n\(window.durationLabel) quota · solid: used so far · striped: expected use · tick: quota limit"
        }
        if let projection {
            button.toolTip? += "\n\(QuotaUsageProjection.percentDescription(projection.projectedUsedPercent)) expected usage by reset"
        }
        if let warning {
            button.toolTip? += "\n\(warning.window.durationLabel) quota: \(warning.forecast.title)"
            button.toolTip? += "\n\(warning.forecast.detailDescription(relativeTo: store.currentDate))"
        }
        button.setAccessibilityLabel(button.toolTip)
    }

    @objc
    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(
                relativeTo: sender.bounds,
                of: sender,
                preferredEdge: .minY
            )
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
