#if DEBUG
import AppKit
import SimMonitorCore
import SwiftUI

/// Shows the popover content in a standalone panel over a backdrop and prints the backdrop's
/// screen frame, so the UI can be captured with `screencapture -R` without clicking the
/// menu bar. This is how the README images are made; see `scripts/screenshots.sh`.
///
/// - `SIMMONITOR_DEBUG_WINDOW=1` turns it on.
/// - `SIMMONITOR_DEMO=1` replaces the real simulators with sample data.
/// - `SIMMONITOR_EXPAND=<n>` expands the nth row, `SIMMONITOR_SELECT=<n>` selects the first n.
/// - `SIMMONITOR_KEYS` types keys into it: `d`/`u` arrows, `S` shift-down, `s` space.
@MainActor
enum Snapshot {
    private static var windows: [NSWindow] = []

    static func takeIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SIMMONITOR_DEBUG_WINDOW"] != nil else { return }
        let store = SimulatorStore.shared
        setlinebuf(stdout)

        Task {
            if environment["SIMMONITOR_DEMO"] != nil {
                store.loadDemoData(simulators: DemoData.simulators, usage: DemoData.usage)
            } else {
                try? await Task.sleep(for: .seconds(2))
            }
            if let row = environment["SIMMONITOR_EXPAND"].flatMap(Int.init), store.ordered.indices.contains(row) {
                store.expandedID = store.ordered[row].udid
            }
            if let count = environment["SIMMONITOR_SELECT"].flatMap(Int.init) {
                store.beginSelecting()
                store.selection = Set(store.ordered.prefix(count).map(\.udid))
            }

            let margin: CGFloat = 48
            let content = NSSize(width: 440, height: 620)
            let backdrop = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: content.width + margin * 2, height: content.height + margin * 2),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            backdrop.contentView = NSHostingView(rootView: Backdrop())
            backdrop.level = .floating
            backdrop.center()
            backdrop.orderFront(nil)

            let panel = KeyablePanel(
                contentRect: NSRect(x: 0, y: 0, width: content.width + margin * 2, height: content.height + margin * 2),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.contentView = NSHostingView(
                rootView: MenuContent(store: store)
                    .background(.regularMaterial, in: .rect(cornerRadius: 26))
                    .clipShape(.rect(cornerRadius: 26))
                    .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
                    .padding(margin)
            )
            panel.setFrameOrigin(backdrop.frame.origin)
            NSApp.activate()
            // A child window always stays above its parent; two separate floating windows
            // can come up in either order.
            backdrop.addChildWindow(panel, ordered: .above)
            panel.makeKeyAndOrderFront(nil)
            windows = [backdrop, panel]

            try? await Task.sleep(for: .seconds(2))
            for key in environment["SIMMONITOR_KEYS"] ?? "" {
                let (code, characters, flags): (UInt16, String, NSEvent.ModifierFlags) = switch key {
                case "u": (126, "\u{F700}", [.function, .numericPad])
                case "S": (125, "\u{F701}", [.function, .numericPad, .shift])
                case "s": (49, " ", [])
                default: (125, "\u{F701}", [.function, .numericPad])
                }
                if let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: flags,
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                    context: nil, characters: characters, charactersIgnoringModifiers: characters,
                    isARepeat: false, keyCode: code
                ) {
                    panel.sendEvent(event)
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
            try? await Task.sleep(for: .seconds(1))
            let height = NSScreen.screens.first?.frame.height ?? 0
            let frame = backdrop.frame
            print("HIGHLIGHT \(store.highlightedID ?? "none") SELECTED \(store.selection.count)")
            print("FRAME \(Int(frame.minX)),\(Int(height - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))")
        }
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct Backdrop: View {
    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.6, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                Color(red: 0.13, green: 0.17, blue: 0.38), Color(red: 0.25, green: 0.22, blue: 0.52), Color(red: 0.45, green: 0.27, blue: 0.55),
                Color(red: 0.12, green: 0.30, blue: 0.55), Color(red: 0.33, green: 0.38, blue: 0.72), Color(red: 0.62, green: 0.40, blue: 0.62),
                Color(red: 0.10, green: 0.42, blue: 0.58), Color(red: 0.20, green: 0.38, blue: 0.68), Color(red: 0.30, green: 0.28, blue: 0.60),
            ]
        )
        .ignoresSafeArea()
    }
}

private enum DemoData {
    private static let devices: [(String, String, Simulator.Family, String, Bool, Int64, Double, UInt64)] = [
        ("Checkout flow", "iPhone 18 Pro", .iPhone, "iOS 27.2", true, 3_780_000_000, 18.4, 3_650_000_000),
        ("iPhone Duo", "iPhone Duo", .iPhone, "iOS 27.2", true, 4_120_000_000, 6.2, 4_210_000_000),
        ("UI Tests", "iPad Pro 13-inch (M5)", .iPad, "iOS 27.2", true, 2_940_000_000, 41.0, 3_980_000_000),
        ("Apple Watch Series 12 (46mm)", "Apple Watch Series 12 (46mm)", .watch, "watchOS 27.2", true, 587_000_000, 1.3, 1_420_000_000),
        ("Apple TV 4K", "Apple TV 4K (3rd generation)", .tv, "tvOS 27.2", false, 412_000_000, 0, 0),
        ("Apple Vision Pro", "Apple Vision Pro", .vision, "visionOS 27.2", false, 6_310_000_000, 0, 0),
        ("iPad mini (A20 Pro)", "iPad mini (A20 Pro)", .iPad, "iOS 27.2", false, 18_300_000, 0, 0),
        ("iPhone 17", "iPhone 17", .iPhone, "iOS 26.4", false, 2_210_000_000, 0, 0),
        ("iPhone 18 Pro Max", "iPhone 18 Pro Max", .iPhone, "iOS 27.2", false, 3_190_000_000, 0, 0),
        ("iPhone Air", "iPhone Air", .iPhone, "iOS 27.2", false, 18_300_000, 0, 0),
        ("Screenshots", "iPhone 18 Pro", .iPhone, "iOS 27.2", false, 1_870_000_000, 0, 0),
    ]

    private static func udid(_ index: Int) -> String {
        String(format: "4F2A91C%01X-7B3E-4D5A-9C0%01X-1E8D6A2B37%02X", index, index, index * 7 + 16)
    }

    static let simulators: [Simulator] = devices.enumerated().map { index, device in
        Simulator(
            udid: udid(index), name: device.0, state: device.4 ? .booted : .shutdown,
            runtimeIdentifier: device.3, runtimeName: device.3, deviceTypeName: device.1, family: device.2,
            dataPath: "/Users/you/Library/Developer/CoreSimulator/Devices/\(udid(index))/data",
            dataSize: device.5, lastUsedAt: Date.now.addingTimeInterval(-Double(index + 1) * 2_700)
        )
    }

    static let usage: [String: ResourceUsage] = Dictionary(
        uniqueKeysWithValues: devices.enumerated().filter { $0.element.4 }.map { index, device in
            (udid(index), ResourceUsage(cpuPercent: device.6, memoryBytes: device.7, processCount: 180 + index * 23))
        }
    )
}
#endif
