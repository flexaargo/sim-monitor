import Foundation

/// One simulator device as reported by `simctl list`.
public struct Simulator: Identifiable, Hashable, Sendable {
    public enum State: String, Sendable {
        case booted = "Booted"
        case shutdown = "Shutdown"
        case booting = "Booting"
        case shuttingDown = "Shutting Down"
        case creating = "Creating"
        case unknown

        public init(simctl value: String) {
            self = State(rawValue: value) ?? .unknown
        }
    }

    public enum Family: String, Sendable {
        case iPhone, iPad, watch, tv, vision, other

        public init(productFamily: String?, deviceTypeIdentifier: String) {
            let hint = (productFamily ?? deviceTypeIdentifier).lowercased()
            if hint.contains("iphone") { self = .iPhone }
            else if hint.contains("ipad") { self = .iPad }
            else if hint.contains("watch") { self = .watch }
            else if hint.contains("tv") { self = .tv }
            else if hint.contains("vision") || hint.contains("reality") { self = .vision }
            else { self = .other }
        }
    }

    public var udid: String
    public var name: String
    public var state: State
    public var isAvailable: Bool
    public var availabilityError: String?
    public var runtimeIdentifier: String
    public var runtimeName: String
    public var deviceTypeName: String
    public var family: Family
    /// The device's `data` directory.
    public var dataPath: String
    public var dataSize: Int64
    public var logPath: String?
    public var lastUsedAt: Date?

    public init(
        udid: String, name: String, state: State, isAvailable: Bool = true, availabilityError: String? = nil,
        runtimeIdentifier: String, runtimeName: String, deviceTypeName: String, family: Family,
        dataPath: String, dataSize: Int64, logPath: String? = nil, lastUsedAt: Date? = nil
    ) {
        self.udid = udid
        self.name = name
        self.state = state
        self.isAvailable = isAvailable
        self.availabilityError = availabilityError
        self.runtimeIdentifier = runtimeIdentifier
        self.runtimeName = runtimeName
        self.deviceTypeName = deviceTypeName
        self.family = family
        self.dataPath = dataPath
        self.dataSize = dataSize
        self.logPath = logPath
        self.lastUsedAt = lastUsedAt
    }

    public var id: String { udid }

    /// The device's root directory (the parent of `data`), which is what you'd want to open in Finder.
    public var devicePath: String {
        (dataPath as NSString).deletingLastPathComponent
    }

    public var isRunning: Bool {
        state == .booted || state == .booting || state == .shuttingDown
    }
}

/// CPU and memory used by every process inside one booted simulator.
public struct ResourceUsage: Hashable, Sendable {
    /// Percent of one core, like Activity Monitor (can exceed 100).
    public var cpuPercent: Double
    /// Sum of physical footprints, in bytes.
    public var memoryBytes: UInt64
    public var processCount: Int

    public init(cpuPercent: Double = 0, memoryBytes: UInt64 = 0, processCount: Int = 0) {
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.processCount = processCount
    }

    public static func + (a: ResourceUsage, b: ResourceUsage) -> ResourceUsage {
        ResourceUsage(
            cpuPercent: a.cpuPercent + b.cpuPercent,
            memoryBytes: a.memoryBytes + b.memoryBytes,
            processCount: a.processCount + b.processCount
        )
    }
}
