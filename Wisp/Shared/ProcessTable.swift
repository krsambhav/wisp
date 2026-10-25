import Darwin
import Foundation

/// One process's cumulative CPU time and memory, as read from libproc.
/// Compiled into the app and the helper: the sandboxed app can only read exact
/// footprints for itself, the unsandboxed helper for every process.
nonisolated struct ProcessUsage: Codable, Sendable, Equatable {
    let pid: Int32
    let name: String
    /// User + system time in Mach ticks (see `ProcessTable.nanosPerTick`).
    let cpuTicks: UInt64
    /// Bytes: physical footprint when `exact`, otherwise resident size.
    let memory: UInt64
    let exact: Bool
}

nonisolated enum ProcessTable {
    /// `struct proc_pidcoalitioninfo` from <sys/proc_info.h>; the flavor and
    /// layout are kernel ABI but not surfaced to Swift.
    private struct CoalitionInfo {
        var ids: (UInt64, UInt64) = (0, 0)       // resource, jetsam
        var reserved: (UInt64, UInt64, UInt64) = (0, 0, 0)
    }
    private static let coalitionFlavor: Int32 = 20

    /// Nanoseconds per Mach tick (libproc CPU times are in ticks).
    static let nanosPerTick: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom)
    }()

    /// Resource coalition of `pid` (0 when unavailable). WebKit's helpers are
    /// launchd children, but they join the app's coalition, which is also how
    /// Activity Monitor groups them.
    static func coalitionID(of pid: pid_t) -> UInt64 {
        var info = CoalitionInfo()
        let size = Int32(MemoryLayout<CoalitionInfo>.size)
        return proc_pidinfo(pid, coalitionFlavor, 0, &info, size) == size ? info.ids.0 : 0
    }

    /// Every live process in `coalition` (plus `always`, normally the caller),
    /// with whatever precision the caller's sandbox allows.
    static func members(ofCoalition coalition: UInt64, always: pid_t = getpid()) -> [ProcessUsage] {
        var rows: [ProcessUsage] = []
        for pid in allPIDs() where pid > 0 {
            let mine = pid == always || (coalition != 0 && coalitionID(of: pid) == coalition)
            guard mine, let u = usage(of: pid) else { continue }
            rows.append(ProcessUsage(pid: pid, name: name(of: pid), cpuTicks: u.ticks, memory: u.memory, exact: u.exact))
        }
        return rows
    }

    static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        if count > 0 {
            var pids = [pid_t](repeating: 0, count: Int(count) + 64)
            let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
            if n > 0 { return Array(pids.prefix(Int(n))) }
        }
        // The App Sandbox denies proc_listallpids; the kern.proc.all sysctl is allowed.
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 16)
        size = procs.count * stride
        guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else { return [] }
        return procs.prefix(size / stride).map(\.kp_proc.p_pid)
    }

    /// `proc_pid_rusage` gives the physical footprint (Activity Monitor's
    /// "Memory") but the sandbox refuses it for other pids; `PROC_PIDTASKINFO`
    /// is allowed and reports resident size, which runs higher.
    static func usage(of pid: pid_t) -> (ticks: UInt64, memory: UInt64, exact: Bool)? {
        var ru = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &ru) { p in
            p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        } == 0
        if ok { return (ru.ri_user_time + ru.ri_system_time, ru.ri_phys_footprint, true) }
        var ti = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, size) == size else { return nil }
        return (ti.pti_total_user + ti.pti_total_system, ti.pti_resident_size, false)
    }

    static func name(of pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_name(pid, &buf, UInt32(buf.count)) > 0 else { return "Process" }
        return String(cString: buf)
    }
}
