import Darwin
import Foundation

/// Measures CPU and memory per booted simulator by walking the process table.
///
/// Every booted simulator has one `launchd_sim` whose argument names the device's data
/// directory; everything running inside that simulator is a descendant of it. CPU is
/// computed from the change in CPU time between two calls to `sample()`, so the first
/// call always reports 0%.
public struct ProcessSampler: Sendable {
    private var previousCPUTime: [pid_t: UInt64] = [:]
    private var previousSampleTime: UInt64?
    private var udidByLaunchd: [pid_t: String] = [:]

    public init() {}

    /// Returns usage keyed by simulator UDID. Only booted simulators appear.
    public mutating func sample() -> [String: ResourceUsage] {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let elapsed = previousSampleTime.map { now &- $0 } ?? 0
        previousSampleTime = now

        var children: [pid_t: [pid_t]] = [:]
        var roots: [pid_t: String] = [:]
        for pid in Self.allPIDs() {
            guard let info = Self.bsdInfo(pid) else { continue }
            children[pid_t(info.pbi_ppid), default: []].append(pid)
            if Self.name(of: info) == "launchd_sim" {
                if let udid = udidByLaunchd[pid] ?? Self.simulatorUDID(forLaunchd: pid) {
                    roots[pid] = udid
                }
            }
        }
        udidByLaunchd = roots

        var result: [String: ResourceUsage] = [:]
        var cpuTimes: [pid_t: UInt64] = [:]
        for (root, udid) in roots {
            var usage = ResourceUsage()
            var cpuDelta: UInt64 = 0
            var stack = [root]
            var seen: Set<pid_t> = []
            while let pid = stack.popLast() {
                guard seen.insert(pid).inserted else { continue }
                stack.append(contentsOf: children[pid] ?? [])
                guard let rusage = Self.rusage(pid) else { continue }
                usage.processCount += 1
                usage.memoryBytes += rusage.ri_phys_footprint
                let cpu = Self.nanoseconds(fromMachTime: rusage.ri_user_time &+ rusage.ri_system_time)
                cpuTimes[pid] = cpu
                if let before = previousCPUTime[pid], cpu >= before {
                    cpuDelta += cpu - before
                }
            }
            if elapsed > 0 {
                usage.cpuPercent = Double(cpuDelta) / Double(elapsed) * 100
            }
            result[udid, default: ResourceUsage()] = result[udid, default: ResourceUsage()] + usage
        }
        previousCPUTime = cpuTimes
        return result
    }

    // MARK: libproc

    private static func allPIDs() -> [pid_t] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        }
        guard count > 0 else { return [] }
        return pids.prefix(Int(count)).filter { $0 > 0 }
    }

    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }

    private static func name(of info: proc_bsdinfo) -> String {
        withUnsafeBytes(of: info.pbi_comm) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    private static func rusage(_ pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return status == 0 ? info : nil
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func nanoseconds(fromMachTime value: UInt64) -> UInt64 {
        guard timebase.denom != 0, timebase.numer != timebase.denom else { return value }
        return value / UInt64(timebase.denom) * UInt64(timebase.numer)
            + value % UInt64(timebase.denom) * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    /// Reads the process's argument block and pulls the device UDID out of
    /// `.../CoreSimulator/Devices/<UDID>/data/var/run/launchd_bootstrap.plist`.
    private static func simulatorUDID(forLaunchd pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let text = String(decoding: buffer.prefix(size).map { $0 == 0 ? UInt8(ascii: " ") : $0 }, as: UTF8.self)
        return udid(inLaunchdArguments: text)
    }

    static func udid(inLaunchdArguments text: String) -> String? {
        guard let match = text.firstMatch(of: /\/Devices\/([0-9A-Fa-f-]{36})\/data/) else { return nil }
        return String(match.1).uppercased()
    }
}
