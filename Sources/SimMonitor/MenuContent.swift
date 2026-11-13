import ServiceManagement
import SimMonitorCore
import SwiftUI

struct MenuContent: View {
    let store: SimulatorStore
    @FocusState private var isFocused: Bool

    var body: some View {
        SimulatorList(store: store)
            .safeAreaBar(edge: .top, spacing: 0) {
                VStack(spacing: 8) {
                    SummaryHeader(
                        runningCount: store.runningCount,
                        totalCount: store.simulators.count,
                        usage: store.totalUsage,
                        diskBytes: store.totalDiskBytes
                    )
                    if let message = store.errorMessage {
                        ErrorBanner(message: message) { store.errorMessage = nil }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                BottomBar(store: store)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
            }
            .frame(width: 440, height: 620)
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(phases: [.down, .repeat], action: handleKey)
            .onAppear {
                store.isVisible = true
                isFocused = true
            }
            .onDisappear { store.isVisible = false }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let highlighted = store.highlightedID
        switch press.key {
        case .upArrow:
            store.moveHighlight(by: -1, extendingSelection: press.modifiers.contains(.shift))
        case .downArrow:
            store.moveHighlight(by: 1, extendingSelection: press.modifiers.contains(.shift))
        case .space, .return:
            guard let highlighted else { return .ignored }
            if store.isSelecting {
                store.toggleSelection(highlighted)
            } else {
                withAnimation(.snappy(duration: 0.2)) { store.toggleExpanded(highlighted) }
            }
        case .rightArrow:
            guard let highlighted, !store.isSelecting else { return .ignored }
            withAnimation(.snappy(duration: 0.2)) { store.expandedID = highlighted }
        case .leftArrow:
            guard store.expandedID != nil else { return .ignored }
            withAnimation(.snappy(duration: 0.2)) { store.expandedID = nil }
        case .escape:
            if store.isSelecting {
                withAnimation(.snappy(duration: 0.2)) { store.isSelecting = false }
            } else if store.expandedID != nil {
                withAnimation(.snappy(duration: 0.2)) { store.expandedID = nil }
            } else {
                return .ignored
            }
        case "a" where press.modifiers.contains(.command):
            withAnimation(.snappy(duration: 0.2)) {
                store.setSelected(true, for: store.simulators)
            }
        default:
            return .ignored
        }
        return .handled
    }
}

// MARK: - Header

private struct SummaryHeader: View {
    let runningCount: Int
    let totalCount: Int
    let usage: ResourceUsage
    let diskBytes: Int64

    var body: some View {
        HStack(spacing: 0) {
            Stat(title: "Running", value: "\(runningCount)", detail: "of \(totalCount)")
            Stat(title: "CPU", value: Format.cpu(usage.cpuPercent))
            Stat(title: "Memory", value: Format.memory(usage.memoryBytes))
            Stat(title: "On Disk", value: Format.disk(diskBytes))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

private struct Stat: View {
    let title: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular.tint(.yellow.opacity(0.25)), in: .rect(cornerRadius: 14))
    }
}

// MARK: - List

private struct SimulatorList: View {
    let store: SimulatorStore

    var body: some View {
        if store.simulators.isEmpty {
            ContentUnavailableView {
                Label(store.hasLoaded ? "No Simulators" : "Loading…", systemImage: "iphone.gen3")
            } description: {
                if store.hasLoaded {
                    Text("Create one in Xcode under Window › Devices and Simulators.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        section("Running", store.running)
                        section("Shut Down", store.stopped)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                }
                .onChange(of: store.keyboardMoveCount) {
                    if let id = store.highlightedID {
                        proxy.scrollTo(id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ simulators: [Simulator]) -> some View {
        if !simulators.isEmpty {
            SectionHeader(
                title: title,
                count: simulators.count,
                isSelecting: store.isSelecting,
                allSelected: simulators.allSatisfy { store.selection.contains($0.udid) }
            ) { select in
                store.setSelected(select, for: simulators)
            }
            ForEach(simulators) { simulator in
                SimulatorRow(
                    simulator: simulator,
                    usage: store.usage[simulator.udid],
                    pendingLabel: store.pending[simulator.udid],
                    isExpanded: !store.isSelecting && store.expandedID == simulator.udid,
                    isHighlighted: store.highlightedID == simulator.udid,
                    isSelecting: store.isSelecting,
                    isSelected: store.selection.contains(simulator.udid),
                    store: store
                )
            }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let count: Int
    let isSelecting: Bool
    let allSelected: Bool
    let setSelected: (Bool) -> Void

    var body: some View {
        HStack {
            Text("\(title) · \(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if isSelecting {
                Button(allSelected ? "Deselect All" : "Select All") {
                    setSelected(!allSelected)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}

// MARK: - Bottom bar

private struct BottomBar: View {
    let store: SimulatorStore

    var body: some View {
        // One glass panel holding ordinary controls, mirroring the header, so the list
        // scrolling underneath never shows through the button labels.
        Group {
            if store.isSelecting {
                SelectionBar(store: store)
            } else {
                StandardBar(store: store)
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

private struct StandardBar: View {
    let store: SimulatorStore
    @State private var isConfirmingShutdownAll = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack(spacing: 8) {
            if isConfirmingShutdownAll {
                Text("Shut down \(store.runningCount) simulators?")
                    .font(.callout)
                    .padding(.leading, 6)
                Spacer()
                Button("Cancel") { isConfirmingShutdownAll = false }
                Button("Shut Down All", role: .destructive) {
                    isConfirmingShutdownAll = false
                    store.shutdownAll()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button("Select", systemImage: "checkmark.circle") {
                    withAnimation(.snappy(duration: 0.2)) {
                        store.beginSelecting()
                    }
                }
                .disabled(store.simulators.isEmpty)
                .help("Select several simulators to act on at once")
                Spacer()
                Button("Shut Down All", systemImage: "power") {
                    isConfirmingShutdownAll = true
                }
                .disabled(store.runningCount == 0)
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await store.refreshList() }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Refresh")
                Menu("More", systemImage: "ellipsis") {
                    Button("Delete Unavailable Simulators") { store.deleteUnavailable() }
                        .disabled(store.unavailableCount == 0)
                    Divider()
                    if Bundle.main.bundleIdentifier != nil {
                        Toggle("Launch at Login", isOn: $launchAtLogin)
                    }
                    Button("Quit Sim Monitor") { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                }
                .labelStyle(.iconOnly)
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.trailing, 6)
                .help("More")
            }
        }
        .onChange(of: launchAtLogin) { _, enabled in
            setLaunchAtLogin(enabled)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            store.errorMessage = "Couldn't change Launch at Login: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Shown in place of the standard bar while picking several simulators.
private struct SelectionBar: View {
    let store: SimulatorStore
    @State private var confirming: SimAction?

    var body: some View {
        VStack(spacing: 8) {
            if let confirming {
                let count = store.targets(of: confirming).count
                Text(question(for: confirming, count: count))
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                HStack(spacing: 8) {
                    Button { self.confirming = nil } label: {
                        Text("Cancel").frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(.cancelAction)
                    Button(role: .destructive) {
                        self.confirming = nil
                        store.performOnSelection(confirming)
                    } label: {
                        Text("\(confirming.title) \(count)").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else {
                HStack {
                    Text("\(store.selection.count) selected")
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .padding(.leading, 6)
                    Spacer()
                    Button("Done") {
                        withAnimation(.snappy(duration: 0.2)) { store.isSelecting = false }
                    }
                    .buttonStyle(.borderedProminent)
                }
                HStack(spacing: 8) {
                    bulkButton(.boot)
                    bulkButton(.shutdown)
                    bulkButton(.erase)
                    bulkButton(.delete)
                }
            }
        }
        .onChange(of: store.selection) {
            confirming = nil
        }
    }

    private func bulkButton(_ action: SimAction) -> some View {
        let count = store.targets(of: action).count
        return Button {
            if action.confirmation != nil {
                confirming = action
            } else {
                store.performOnSelection(action)
            }
        } label: {
            Text(action.title)
                .frame(maxWidth: .infinity)
        }
        .disabled(count == 0)
        .help(count == 0 ? "Nothing selected that this applies to" : "\(action.title) \(count) selected")
    }

    private func question(for action: SimAction, count: Int) -> String {
        let noun = count == 1 ? "simulator" : "simulators"
        switch action {
        case .erase:
            return "Erase all apps, data and settings on \(count) \(noun)?"
        default:
            return "Delete \(count) \(noun) and everything on them? This can't be undone."
        }
    }
}

// MARK: - Formatting

enum Format {
    static func cpu(_ percent: Double) -> String {
        percent.formatted(.number.precision(.fractionLength(percent < 10 ? 1 : 0))) + "%"
    }

    static func memory(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / 1_073_741_824
        if gigabytes >= 1 {
            return gigabytes.formatted(.number.precision(.fractionLength(gigabytes < 100 ? 1 : 0))) + " GB"
        }
        return (Double(bytes) / 1_048_576).formatted(.number.precision(.fractionLength(0))) + " MB"
    }

    static func disk(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }
}
