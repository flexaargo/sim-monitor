import Foundation
import Testing
@testable import SimMonitorCore

@Test func parsesSimctlList() throws {
    let json = """
    {
      "devicetypes": [
        {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro", "name": "iPhone 18 Pro", "productFamily": "iPhone"}
      ],
      "runtimes": [
        {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-2", "name": "iOS 27.2"}
      ],
      "devices": {
        "com.apple.CoreSimulator.SimRuntime.iOS-27-2": [
          {
            "dataPath": "/Users/me/Library/Developer/CoreSimulator/Devices/AAAA/data",
            "dataPathSize": 1024,
            "udid": "AAAA",
            "lastUsedAt": "2026-11-12T23:07:14Z",
            "isAvailable": true,
            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro",
            "state": "Booted",
            "name": "Work phone"
          }
        ],
        "com.apple.CoreSimulator.SimRuntime.watchOS-9-4": [
          {
            "udid": "BBBB",
            "isAvailable": false,
            "availabilityError": "runtime profile not found",
            "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-8-45mm",
            "state": "Shutdown",
            "name": "Old watch"
          }
        ]
      }
    }
    """
    let sims = try Simctl.parseList(Data(json.utf8))
    #expect(sims.count == 2)

    let phone = try #require(sims.first { $0.udid == "AAAA" })
    #expect(phone.state == .booted)
    #expect(phone.isRunning)
    #expect(phone.runtimeName == "iOS 27.2")
    #expect(phone.deviceTypeName == "iPhone 18 Pro")
    #expect(phone.family == .iPhone)
    #expect(phone.dataSize == 1024)
    #expect(phone.devicePath == "/Users/me/Library/Developer/CoreSimulator/Devices/AAAA")
    #expect(phone.lastUsedAt != nil)

    let watch = try #require(sims.first { $0.udid == "BBBB" })
    #expect(!watch.isAvailable)
    #expect(watch.runtimeName == "watchOS 9.4")
    #expect(watch.deviceTypeName == "Apple Watch Series 8 45mm")
    #expect(watch.family == .watch)
}

@Test func extractsUDIDFromLaunchdArguments() {
    let args = "launchd_sim /Users/me/Library/Developer/CoreSimulator/Devices/a7ddad07-460a-436f-8579-52080559dec2/data/var/run/launchd_bootstrap.plist"
    #expect(ProcessSampler.udid(inLaunchdArguments: args) == "A7DDAD07-460A-436F-8579-52080559DEC2")
    #expect(ProcessSampler.udid(inLaunchdArguments: "launchd_sim") == nil)
}

/// Exercises the real `simctl` and process table. Creates and removes its own device so it
/// never touches simulators that are already on the machine.
@Test func lifecycleAgainstRealSimctl() async throws {
    let existing = try await Simctl.list()
    guard let template = existing.first(where: { $0.isAvailable && $0.family == .iPhone }) else { return }

    let name = "SimMonitor Test \(UUID().uuidString.prefix(6))"
    let created = try await Simctl.run(["create", name, template.deviceTypeName, template.runtimeIdentifier])
    let udid = String(decoding: created, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

    do {
        var sampler = ProcessSampler()
        #expect(sampler.sample()[udid] == nil)

        try await Simctl.boot(udid)
        #expect(try await Simctl.list().first { $0.udid == udid }?.state == .booted)

        _ = sampler.sample()
        try await Task.sleep(for: .seconds(2))
        let usage = try #require(sampler.sample()[udid])
        #expect(usage.processCount > 1)
        #expect(usage.memoryBytes > 10_000_000)
        #expect(usage.cpuPercent >= 0)

        try await Simctl.shutdown(udid)
        #expect(try await Simctl.list().first { $0.udid == udid }?.state == .shutdown)
        #expect(sampler.sample()[udid] == nil)

        try await Simctl.erase(udid)
        try await Simctl.delete(udid)
        #expect(try await Simctl.list().contains { $0.udid == udid } == false)
    } catch {
        try? await Simctl.delete(udid)
        throw error
    }
}
