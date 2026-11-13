import AppKit
import Observation
import SimMonitorCore

enum SimAction: String, Identifiable {
    case boot, shutdown, restart, erase, delete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .boot: "Boot"
        case .shutdown: "Shut Down"
        case .restart: "Restart"
        case .erase: "Erase"
        case .delete: "Delete"
        }
    }

    var progressTitle: String {
        switch self {
        case .boot: "Booting…"
        case .shutdown: "Shutting down…"
        case .restart: "Restarting…"
        case .erase: "Erasing…"
        case .delete: "Deleting…"
        }
    }

    /// Destructive actions ask for confirmation first.
    var confirmation: String? {
        switch self {
        case .erase: "Erase all apps, data and settings? The simulator itself is kept."
        case .delete: "Delete this simulator and everything on it? This can't be undone."
        default: nil
        }
    }
}

@MainActor
@Observable
final class SimulatorStore {
    static let shared = SimulatorStore()

    private(set) var simulators: [Simulator] = []
    private(set) var usage: [String: ResourceUsage] = [:]
    /// Progress label per simulator that has an action in flight.
    private(set) var pending: [String: String] = [:]
    private(set) var hasLoaded = false
    var errorMessage: String?
    var expandedID: String?
    /// The row the keyboard or pointer is on.
    var highlightedID: String?
    /// Bumped when the highlight moves by keyboard, so the list can scroll to follow it.
    private(set) var keyboardMoveCount = 0
    var isSelecting = false {
        didSet { if !isSelecting { selection = [] } }
    }
    var selection: Set<String> = []
    /// The popover is on screen, so poll faster.
    var isVisible = false {
        didSet { if isVisible && !oldValue { wake() } }
    }

    private let sampler = Sampler()
    private var pollTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var lastListRefresh: ContinuousClock.Instant?
    /// Where the pointer was at the last key press. Rows scrolling under a pointer that
    /// hasn't moved shouldn't steal the highlight from the keyboard.
    @ObservationIgnored private var pointerAtLastKeyPress: CGPoint?

    private init() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let delay: Duration = self.isVisible ? .seconds(2) : .seconds(5)
                let sleep = Task<Void, Never> { try? await Task.sleep(for: delay) }
                self.sleepTask = sleep
                await sleep.value
            }
        }
    }

    @ObservationIgnored private var isDemo = false

    #if DEBUG
    /// Stops polling and shows fixed data instead, for screenshots.
    func loadDemoData(simulators: [Simulator], usage: [String: ResourceUsage]) {
        isDemo = true
        pollTask?.cancel()
        self.simulators = simulators
        self.usage = usage
        hasLoaded = true
    }
    #endif

    // MARK: Derived

    /// Rows in the order the list shows them.
    var ordered: [Simulator] { running + stopped }
    var selected: [Simulator] { simulators.filter { selection.contains($0.udid) } }
    var running: [Simulator] { simulators.filter(\.isRunning) }
    var stopped: [Simulator] { simulators.filter { !$0.isRunning } }
    var runningCount: Int { simulators.count(where: \.isRunning) }
    var unavailableCount: Int { simulators.count { !$0.isAvailable } }
    var totalUsage: ResourceUsage { usage.values.reduce(ResourceUsage(), +) }
    var totalDiskBytes: Int64 { simulators.reduce(0) { $0 + $1.dataSize } }

    // MARK: Polling

    /// Cuts the current wait short so the next sample happens now.
    private func wake() {
        sleepTask?.cancel()
    }

    private func tick() async {
        guard !isDemo else { return }
        let sample = await sampler.sample()
        if sample != usage { usage = sample }

        // The process table is cheap to read, so use it to notice boots and shutdowns
        // right away and only re-run simctl when something changed or the list is stale.
        let knownRunning = Set(simulators.lazy.filter(\.isRunning).map(\.udid))
        let staleAfter: Duration = isVisible ? .seconds(6) : .seconds(30)
        let isStale = lastListRefresh.map { ContinuousClock.now - $0 > staleAfter } ?? true
        if isStale || Set(sample.keys) != knownRunning {
            await refreshList()
        }
    }

    func refreshList() async {
        guard !isDemo else { return }
        lastListRefresh = .now
        do {
            let list = try await Simctl.list()
            guard !isDemo else { return }
            if list != simulators {
                simulators = list
                let ids = Set(list.map(\.udid))
                if !selection.isSubset(of: ids) { selection.formIntersection(ids) }
                if let id = highlightedID, !ids.contains(id) { highlightedID = nil }
                if let id = expandedID, !ids.contains(id) { expandedID = nil }
            }
            hasLoaded = true
        } catch {
            if !hasLoaded {
                errorMessage = "Couldn't list simulators: \(error.localizedDescription)"
            }
        }
    }

    // MARK: Actions

    func perform(_ action: SimAction, on simulator: Simulator) {
        let udid = simulator.udid
        guard pending[udid] == nil else { return }
        pending[udid] = action.progressTitle
        Task {
            do {
                try await Self.run(action, on: simulator)
            } catch {
                errorMessage = "\(action.title) failed for “\(simulator.name)”: \(error.localizedDescription)"
            }
            await refreshList()
            pending[udid] = nil
            wake()
        }
    }

    /// The selected simulators this action would actually change.
    func targets(of action: SimAction) -> [Simulator] {
        selected.filter { simulator in
            guard pending[simulator.udid] == nil else { return false }
            switch action {
            case .boot: return !simulator.isRunning && simulator.isAvailable
            case .shutdown, .restart: return simulator.isRunning
            case .erase: return simulator.isAvailable
            case .delete: return true
            }
        }
    }

    /// Runs the action on every selected simulator it applies to, all at once.
    func performOnSelection(_ action: SimAction) {
        let targets = targets(of: action)
        guard !targets.isEmpty else { return }
        for simulator in targets { pending[simulator.udid] = action.progressTitle }
        Task {
            let failures = await withTaskGroup(of: String?.self) { group in
                for simulator in targets {
                    group.addTask {
                        do {
                            try await Self.run(action, on: simulator)
                            return nil
                        } catch {
                            return "“\(simulator.name)”: \(error.localizedDescription)"
                        }
                    }
                }
                var failures: [String] = []
                for await failure in group {
                    if let failure { failures.append(failure) }
                }
                return failures
            }
            if !failures.isEmpty {
                errorMessage = "\(action.title) failed for \(failures.count) of \(targets.count). "
                    + failures.prefix(3).joined(separator: " ")
            }
            await refreshList()
            for simulator in targets { pending[simulator.udid] = nil }
            if selection.isEmpty { isSelecting = false }
            wake()
        }
    }

    private nonisolated static func run(_ action: SimAction, on simulator: Simulator) async throws {
        let udid = simulator.udid
        switch action {
        case .boot:
            try await Simctl.boot(udid)
        case .shutdown:
            try await Simctl.shutdown(udid)
        case .restart:
            try? await Simctl.shutdown(udid)
            try await Simctl.boot(udid)
        case .erase:
            // simctl refuses to erase a booted device, so cycle it and put it back.
            if simulator.isRunning { try? await Simctl.shutdown(udid) }
            try await Simctl.erase(udid)
            if simulator.isRunning { try await Simctl.boot(udid) }
        case .delete:
            if simulator.isRunning { try? await Simctl.shutdown(udid) }
            try await Simctl.delete(udid)
        }
    }

    // MARK: Highlight and selection

    /// Moves the highlight up or down the list. With `extendingSelection`, also selects
    /// the rows it passes over, entering selection mode if needed.
    func moveHighlight(by offset: Int, extendingSelection: Bool = false) {
        let rows = ordered
        guard !rows.isEmpty else { return }
        pointerAtLastKeyPress = NSEvent.mouseLocation
        let current = highlightedID.flatMap { id in rows.firstIndex { $0.udid == id } }
        let next: Int
        if let current {
            next = min(max(current + offset, 0), rows.count - 1)
        } else {
            next = offset > 0 ? 0 : rows.count - 1
        }
        if extendingSelection {
            isSelecting = true
            if let current { selection.insert(rows[current].udid) }
            selection.insert(rows[next].udid)
        }
        highlightedID = rows[next].udid
        keyboardMoveCount += 1
    }

    func pointerEntered(_ udid: String) {
        if let anchor = pointerAtLastKeyPress, anchor == NSEvent.mouseLocation { return }
        pointerAtLastKeyPress = nil
        if highlightedID != udid { highlightedID = udid }
    }

    func toggleExpanded(_ udid: String) {
        expandedID = expandedID == udid ? nil : udid
    }

    func toggleSelection(_ udid: String) {
        if selection.contains(udid) {
            selection.remove(udid)
        } else {
            selection.insert(udid)
        }
    }

    func beginSelecting(with udid: String? = nil) {
        isSelecting = true
        expandedID = nil
        if let udid { selection.insert(udid) }
    }

    func setSelected(_ isSelected: Bool, for simulators: [Simulator]) {
        let ids = simulators.map(\.udid)
        if isSelected {
            isSelecting = true
            selection.formUnion(ids)
        } else {
            selection.subtract(ids)
        }
    }

    func shutdownAll() {
        let targets = running.map(\.udid).filter { pending[$0] == nil }
        guard !targets.isEmpty else { return }
        for udid in targets { pending[udid] = SimAction.shutdown.progressTitle }
        Task {
            do {
                try await Simctl.shutdownAll()
            } catch {
                errorMessage = "Shut Down All failed: \(error.localizedDescription)"
            }
            await refreshList()
            for udid in targets { pending[udid] = nil }
            wake()
        }
    }

    func deleteUnavailable() {
        Task {
            do {
                try await Simctl.deleteUnavailable()
            } catch {
                errorMessage = "Couldn't delete unavailable simulators: \(error.localizedDescription)"
            }
            await refreshList()
        }
    }

    /// Brings the device up in Simulator.app, booting it first if needed.
    func showInSimulator(_ simulator: Simulator) {
        let udid = simulator.udid
        Task {
            if !simulator.isRunning { try? await Simctl.boot(udid) }
            do {
                try await Simctl.runTool("/usr/bin/open", ["-a", "Simulator", "--args", "-CurrentDeviceUDID", udid])
            } catch {
                errorMessage = "Couldn't open Simulator: \(error.localizedDescription)"
            }
            await refreshList()
        }
    }

    func revealInFinder(_ simulator: Simulator) {
        let url = URL(fileURLWithPath: simulator.devicePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

private actor Sampler {
    private var sampler = ProcessSampler()

    func sample() -> [String: ResourceUsage] {
        sampler.sample()
    }
}
