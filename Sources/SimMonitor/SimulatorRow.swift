import SimMonitorCore
import SwiftUI

struct SimulatorRow: View {
    let simulator: Simulator
    let usage: ResourceUsage?
    let pendingLabel: String?
    let isExpanded: Bool
    let isHighlighted: Bool
    let isSelecting: Bool
    let isSelected: Bool
    let store: SimulatorStore

    @State private var confirming: SimAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summary
            if isExpanded {
                details
            }
        }
        .background(backgroundStyle, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.tint.opacity(isSelected && isHighlighted ? 0.6 : 0), lineWidth: 1)
        }
        .onHover { if $0 { store.pointerEntered(simulator.udid) } }
        .id(simulator.udid)
        .contextMenu { contextMenu }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { confirming = nil }
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.tint.opacity(isHighlighted ? 0.26 : 0.18)) }
        if isHighlighted { return AnyShapeStyle(.primary.opacity(0.09)) }
        if isExpanded { return AnyShapeStyle(.primary.opacity(0.05)) }
        return AnyShapeStyle(.clear)
    }

    // MARK: Collapsed row

    private var summary: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    if isSelecting {
                        store.toggleSelection(simulator.udid)
                    } else {
                        store.toggleExpanded(simulator.udid)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                            .contentTransition(.symbolEffect(.replace))
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel(isSelected ? "Selected" : "Not selected")
                    }
                    DeviceIcon(family: simulator.family, deviceTypeName: simulator.deviceTypeName, isRunning: simulator.isRunning)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(simulator.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    trailingReadout
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isSelecting ? "Toggles selection" : isExpanded ? "Hides details" : "Shows details and actions")

            if !isSelecting {
                powerButton
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        simulator.name == simulator.deviceTypeName
            ? simulator.runtimeName
            : "\(simulator.deviceTypeName) · \(simulator.runtimeName)"
    }

    @ViewBuilder
    private var trailingReadout: some View {
        if let pendingLabel {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(pendingLabel)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if !simulator.isAvailable {
            Label("Unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if simulator.isRunning {
            HStack(spacing: 12) {
                Readout(label: "CPU", value: usage.map { Format.cpu($0.cpuPercent) } ?? "–")
                Readout(label: "MEM", value: usage.map { Format.memory($0.memoryBytes) } ?? "–")
            }
            .fixedSize()
        } else {
            Text(Format.disk(simulator.dataSize))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var powerButton: some View {
        Button(
            simulator.isRunning ? "Shut Down" : "Boot",
            systemImage: simulator.isRunning ? "power" : "play.fill"
        ) {
            store.perform(simulator.isRunning ? .shutdown : .boot, on: simulator)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .frame(width: 24, height: 24)
        .foregroundStyle(simulator.isRunning ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .disabled(pendingLabel != nil || (!simulator.isAvailable && !simulator.isRunning))
        .help(simulator.isRunning ? "Shut Down" : "Boot")
    }

    // MARK: Expanded details

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 5) {
                DetailRow(label: "Status") { Text(statusText) }
                DetailRow(label: "On Disk") { Text(Format.disk(simulator.dataSize)) }
                if let lastUsed = simulator.lastUsedAt {
                    DetailRow(label: "Last Used") {
                        Text(lastUsed.formatted(.relative(presentation: .named)))
                    }
                }
                DetailRow(label: "UDID") {
                    CopyableValue(text: simulator.udid, display: simulator.udid) {
                        store.copy(simulator.udid)
                    }
                }
                DetailRow(label: "Location") {
                    CopyableValue(
                        text: simulator.devicePath,
                        display: (simulator.devicePath as NSString).abbreviatingWithTildeInPath
                    ) {
                        store.copy(simulator.devicePath)
                    } extra: {
                        Button("Show in Finder", systemImage: "folder") {
                            store.revealInFinder(simulator)
                        }
                        .help("Show in Finder")
                    }
                }
            }
            .font(.caption)

            if let confirming, let question = confirming.confirmation {
                confirmation(confirming, question: question)
            } else {
                actionButtons
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 10)
        .transition(.opacity)
    }

    private var statusText: String {
        var parts = [simulator.state == .unknown ? "Unknown" : simulator.state.rawValue]
        if simulator.state == .shutdown { parts = ["Shut down"] }
        if let usage, simulator.isRunning {
            parts.append("\(usage.processCount) processes")
        }
        if let error = simulator.availabilityError, !simulator.isAvailable {
            parts.append(error)
        }
        return parts.joined(separator: " · ")
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            if simulator.isRunning {
                actionButton(.shutdown)
                actionButton(.restart)
            } else {
                actionButton(.boot)
                    .disabled(!simulator.isAvailable)
            }
            Button("Open") {
                store.showInSimulator(simulator)
            }
            .disabled(!simulator.isAvailable)
            .help("Show this device in the Simulator app")
            Spacer(minLength: 0)
            actionButton(.erase)
                .disabled(!simulator.isAvailable)
            actionButton(.delete)
        }
        .controlSize(.small)
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .disabled(pendingLabel != nil)
    }

    private func actionButton(_ action: SimAction) -> some View {
        Button(action.title) {
            if action.confirmation != nil {
                withAnimation(.snappy(duration: 0.15)) { confirming = action }
            } else {
                store.perform(action, on: simulator)
            }
        }
    }

    private func confirmation(_ action: SimAction, question: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button("Cancel") {
                    withAnimation(.snappy(duration: 0.15)) { confirming = nil }
                }
                .keyboardShortcut(.cancelAction)
                Button(action.title, role: .destructive) {
                    confirming = nil
                    store.perform(action, on: simulator)
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
            }
            .controlSize(.small)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
        }
        .padding(10)
        .background(.red.opacity(0.1), in: .rect(cornerRadius: 10))
    }

    // MARK: Context menu

    @ViewBuilder
    private var contextMenu: some View {
        if simulator.isRunning {
            Button("Shut Down") { store.perform(.shutdown, on: simulator) }
            Button("Restart") { store.perform(.restart, on: simulator) }
        } else {
            Button("Boot") { store.perform(.boot, on: simulator) }
                .disabled(!simulator.isAvailable)
        }
        Button("Open in Simulator") { store.showInSimulator(simulator) }
            .disabled(!simulator.isAvailable)
        Divider()
        Button("Select") {
            withAnimation(.snappy(duration: 0.2)) { store.beginSelecting(with: simulator.udid) }
        }
        Button("Show in Finder") { store.revealInFinder(simulator) }
        Button("Copy UDID") { store.copy(simulator.udid) }
        Button("Copy Path") { store.copy(simulator.devicePath) }
        Divider()
        // Destructive actions confirm inside the expanded row.
        Button("Erase All Content and Settings…") { askToConfirm(.erase) }
            .disabled(!simulator.isAvailable)
        Button("Delete…", role: .destructive) { askToConfirm(.delete) }
    }

    private func askToConfirm(_ action: SimAction) {
        withAnimation(.snappy(duration: 0.2)) {
            store.isSelecting = false
            store.expandedID = simulator.udid
            confirming = action
        }
    }
}

// MARK: - Pieces

private struct DeviceIcon: View {
    let family: Simulator.Family
    let deviceTypeName: String
    let isRunning: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17))
            .foregroundStyle(isRunning ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .frame(width: 26, height: 26)
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    .opacity(isRunning ? 1 : 0)
            }
            .accessibilityLabel(isRunning ? "Running" : "Shut down")
    }

    /// The foldable has its own symbol, added in the 26.2 symbol set.
    private var isDuo: Bool {
        deviceTypeName.localizedCaseInsensitiveContains("iPhone Duo")
            && NSImage(systemSymbolName: "iphone.duo", accessibilityDescription: nil) != nil
    }

    private var symbol: String {
        switch family {
        case .iPhone: isDuo ? "iphone.duo" : "iphone.gen3"
        case .iPad: "ipad.gen2"
        case .watch: "applewatch"
        case .tv: "appletv"
        case .vision: "visionpro"
        case .other: "desktopcomputer"
        }
    }
}

private struct Readout: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.callout)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DetailRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            value
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CopyableValue<Extra: View>: View {
    let text: String
    let display: String
    let copy: () -> Void
    @ViewBuilder var extra: Extra

    @State private var didCopy = false

    init(text: String, display: String, copy: @escaping () -> Void, @ViewBuilder extra: () -> Extra = { EmptyView() }) {
        self.text = text
        self.display = display
        self.copy = copy
        self.extra = extra()
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(display)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(text)
            Spacer(minLength: 0)
            Button(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                copy()
                didCopy = true
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    didCopy = false
                }
            }
            .help("Copy")
            extra
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}
