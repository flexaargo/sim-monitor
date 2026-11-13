import Foundation

public struct SimctlError: LocalizedError, Sendable {
    public var command: String
    public var status: Int32
    public var message: String

    public var errorDescription: String? {
        message.isEmpty ? "`\(command)` failed with exit code \(status)." : message
    }
}

/// Thin wrapper around `xcrun simctl`.
public enum Simctl {
    // MARK: Listing

    public static func list() async throws -> [Simulator] {
        try parseList(try await run(["list", "-j"]))
    }

    public static func parseList(_ data: Data) throws -> [Simulator] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let list = try decoder.decode(ListOutput.self, from: data)

        let runtimeNames = Dictionary(
            (list.runtimes ?? []).map { ($0.identifier, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        let deviceTypes = Dictionary(
            (list.devicetypes ?? []).map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var result: [Simulator] = []
        for (runtimeID, devices) in list.devices {
            let runtimeName = runtimeNames[runtimeID] ?? fallbackRuntimeName(runtimeID)
            for device in devices {
                let typeID = device.deviceTypeIdentifier ?? ""
                let type = deviceTypes[typeID]
                result.append(Simulator(
                    udid: device.udid,
                    name: device.name,
                    state: .init(simctl: device.state),
                    isAvailable: device.isAvailable ?? true,
                    availabilityError: device.availabilityError,
                    runtimeIdentifier: runtimeID,
                    runtimeName: runtimeName,
                    deviceTypeName: type?.name ?? fallbackDeviceTypeName(typeID),
                    family: .init(productFamily: type?.productFamily, deviceTypeIdentifier: typeID),
                    dataPath: device.dataPath ?? "",
                    dataSize: device.dataPathSize ?? 0,
                    logPath: device.logPath,
                    lastUsedAt: device.lastUsedAt
                ))
            }
        }
        return result.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-17-5" → "iOS 17.5"
    static func fallbackRuntimeName(_ identifier: String) -> String {
        let last = identifier.split(separator: ".").last.map(String.init) ?? identifier
        var parts = last.split(separator: "-").map(String.init)
        guard !parts.isEmpty else { return identifier }
        let platform = parts.removeFirst()
        let version = parts.prefix { Int($0) != nil }.joined(separator: ".")
        return version.isEmpty ? platform : "\(platform) \(version)"
    }

    /// "com.apple.CoreSimulator.SimDeviceType.iPhone-15-Pro" → "iPhone 15 Pro"
    static func fallbackDeviceTypeName(_ identifier: String) -> String {
        let last = identifier.split(separator: ".").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "-", with: " ")
    }

    // MARK: Actions

    public static func boot(_ udid: String) async throws {
        try await run(["boot", udid])
    }

    public static func shutdown(_ udid: String) async throws {
        try await run(["shutdown", udid])
    }

    public static func shutdownAll() async throws {
        try await run(["shutdown", "all"])
    }

    /// Wipes the device's contents and settings. The device must be shut down.
    public static func erase(_ udid: String) async throws {
        try await run(["erase", udid])
    }

    public static func delete(_ udid: String) async throws {
        try await run(["delete", udid])
    }

    public static func deleteUnavailable() async throws {
        try await run(["delete", "unavailable"])
    }

    // MARK: Process plumbing

    @discardableResult
    public static func run(_ arguments: [String]) async throws -> Data {
        try await runTool("/usr/bin/xcrun", ["simctl"] + arguments)
    }

    @discardableResult
    public static func runTool(_ path: String, _ arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try runBlocking(path, arguments) })
            }
        }
    }

    private static func runBlocking(_ path: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        try process.run()

        // Drain stderr on another thread so neither pipe can fill up and stall the child.
        let errorBox = DataBox()
        let group = DispatchGroup()
        DispatchQueue.global(qos: .utility).async(group: group) {
            errorBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorBox.data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw SimctlError(
                command: ([(path as NSString).lastPathComponent] + arguments).joined(separator: " "),
                status: process.terminationStatus,
                message: message
            )
        }
        return output
    }

    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }

    // MARK: JSON shapes

    private struct ListOutput: Decodable {
        var devices: [String: [Device]]
        var runtimes: [Runtime]?
        var devicetypes: [DeviceType]?
    }

    private struct Device: Decodable {
        var udid: String
        var name: String
        var state: String
        var isAvailable: Bool?
        var availabilityError: String?
        var deviceTypeIdentifier: String?
        var dataPath: String?
        var dataPathSize: Int64?
        var logPath: String?
        var lastUsedAt: Date?
    }

    private struct Runtime: Decodable {
        var identifier: String
        var name: String
    }

    private struct DeviceType: Decodable {
        var identifier: String
        var name: String
        var productFamily: String?
    }
}
