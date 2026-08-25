import AppKit
import Combine
import SwiftUI

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
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
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
        let symbolName = isStale ? "exclamationmark.triangle.fill" : "terminal.fill"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        button.title = store.menuBarText
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
