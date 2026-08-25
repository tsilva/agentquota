import AppKit
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
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AgentQuotaRuntime.shared.store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AgentQuotaRuntime.shared.store.shutdown()
    }
}

@main
struct AgentQuotaApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appDelegate
    @StateObject private var store = AgentQuotaRuntime.shared.store

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
