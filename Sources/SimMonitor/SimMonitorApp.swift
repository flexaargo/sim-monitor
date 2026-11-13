import AppKit
import SwiftUI

@main
struct SimMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let store = SimulatorStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            MenuBarLabel(runningCount: store.runningCount)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let runningCount: Int

    var body: some View {
        // Image and text side by side is the only layout a menu bar item renders reliably.
        HStack(spacing: 3) {
            Image(systemName: runningCount > 0 ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3")
            if runningCount > 0 {
                Text("\(runningCount)")
            }
        }
        .accessibilityLabel("Sim Monitor, \(runningCount) running")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, also when run unbundled via `swift run`.
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        Snapshot.takeIfRequested()
        #endif
    }
}
