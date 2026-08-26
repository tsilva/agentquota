import AppKit
import Combine
import SwiftUI

@MainActor
enum MenuBarQuotaMeter {
    static let size = NSSize(width: 48, height: 19)

    private static let borderWidth: CGFloat = 1.3
    private static let trackInset: CGFloat = 2.5
    private static let outerCornerRadius: CGFloat = 2
    private static let innerCornerRadius: CGFloat = 1.5
    private static let promptValueSpacing: CGFloat = 1.5

    static func image(remainingPercent: Int?, isStale: Bool) -> NSImage {
        let percent = min(max(remainingPercent ?? 0, 0), 100)
        let value = remainingPercent.map { "\($0)%" } ?? "—"
        let image = NSImage(size: size, flipped: false) { _ in
            draw(percent: percent, value: value, isStale: isStale)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func draw(percent: Int, value: String, isStale: Bool) {
        NSGraphicsContext.current?.shouldAntialias = true

        let outerRect = NSRect(origin: .zero, size: size).insetBy(
            dx: borderWidth / 2,
            dy: borderWidth / 2
        )
        let outerPath = NSBezierPath(
            roundedRect: outerRect,
            xRadius: outerCornerRadius,
            yRadius: outerCornerRadius
        )
        outerPath.lineWidth = borderWidth
        (isStale ? NSColor.systemOrange : NSColor.labelColor).setStroke()
        outerPath.stroke()

        let trackRect = outerRect.insetBy(dx: trackInset, dy: trackInset)
        let trackPath = NSBezierPath(
            roundedRect: trackRect,
            xRadius: innerCornerRadius,
            yRadius: innerCornerRadius
        )
        NSColor.black.withAlphaComponent(0.48).setFill()
        trackPath.fill()

        if percent > 0 {
            NSGraphicsContext.saveGraphicsState()
            trackPath.addClip()
            let fillRect = NSRect(
                x: trackRect.minX,
                y: trackRect.minY,
                width: trackRect.width * CGFloat(percent) / 100,
                height: trackRect.height
            )
            (isStale ? NSColor.systemOrange : NSColor.systemBlue).setFill()
            fillRect.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        drawContent(value: value, isStale: isStale)
    }

    private static func drawContent(value: String, isStale: Bool) {
        let promptFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let textColor = NSColor.white
        let prompt = isStale ? "!" : ">_"

        let promptAttributes: [NSAttributedString.Key: Any] = [
            .font: promptFont,
            .foregroundColor: textColor,
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: valueFont,
            .foregroundColor: textColor,
        ]
        let promptSize = (">_" as NSString).size(withAttributes: promptAttributes)
        let maximumValueSize = ("100%" as NSString).size(withAttributes: valueAttributes)
        let valueSize = (value as NSString).size(withAttributes: valueAttributes)
        let contentWidth = promptSize.width + promptValueSpacing + maximumValueSize.width
        let contentX = floor((size.width - contentWidth) / 2)

        let promptRect = NSRect(
            x: contentX,
            y: floor((size.height - promptSize.height) / 2),
            width: promptSize.width,
            height: promptSize.height
        )
        (prompt as NSString).draw(in: promptRect, withAttributes: promptAttributes)

        let valueRect = NSRect(
            x: contentX + promptSize.width + promptValueSpacing
                + maximumValueSize.width - valueSize.width,
            y: floor((size.height - valueSize.height) / 2),
            width: valueSize.width,
            height: valueSize.height
        )
        (value as NSString).draw(in: valueRect, withAttributes: valueAttributes)
    }
}

@MainActor
final class AgentQuotaRuntime {
    static let shared = AgentQuotaRuntime()

    let store: QuotaStore

    private init() {
        store = QuotaStore {
            let executableURL = try CodexLocator().locate()
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

    static func main() {
        let application = NSApplication.shared
        let delegate = AgentQuotaApp()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configurePopover()
        observeStore()
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusObservation?.cancel()
        popover.performClose(nil)
        removeStatusItem()
        store.shutdown()
    }

    private var store: QuotaStore {
        AgentQuotaRuntime.shared.store
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
        let hostingController = NSHostingController(rootView: MenuBarContentView(store: store))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
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
        button.image = MenuBarQuotaMeter.image(
            remainingPercent: store.snapshot?.lowestRemainingPercent,
            isStale: isStale
        )
        button.title = ""
        button.toolTip = isStale
            ? "Codex quota is stale: \(store.menuBarText) remaining"
            : "Codex quota: \(store.menuBarText) remaining"
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
