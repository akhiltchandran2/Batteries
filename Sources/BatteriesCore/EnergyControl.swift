import Foundation
import Darwin

/// Freezes (SIGSTOP) an energy-hungry app's processes so it stops drawing
/// power, and thaws them (SIGCONT) on demand or automatically when the Mac is
/// back on wall power. A paused app uses ~zero CPU but is fully frozen and
/// unresponsive until resumed — that's the point: "stop draining my battery
/// until I'm plugged in".
///
/// State is persisted so a crash while apps are frozen can be recovered from
/// on the next launch (only PIDs that still belong to the same app are thawed,
/// so a recycled PID is never signalled by mistake).
enum EnergyControl {
    private static let lock = NSLock()
    /// appPath → the exact PIDs we stopped, so we continue only those.
    private static var suspended: [String: [Int32]] = load()

    // MARK: - Query

    static func isSuspended(appPath: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return suspended[appPath] != nil
    }

    static func suspendedPaths() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(suspended.keys)
    }

    // MARK: - Control

    /// SIGSTOP every process in the app bundle. No-op if it isn't running.
    static func suspend(appPath: String) {
        let pids = runningPIDs(under: appPath)
        guard !pids.isEmpty else { return }
        for pid in pids { kill(pid, SIGSTOP) }
        lock.lock(); suspended[appPath] = pids; save(); lock.unlock()
        Log.refresh.debug("energy: paused \(appPath, privacy: .public) (\(pids.count) pids)")
    }

    /// SIGCONT the processes we previously stopped for this app.
    static func resume(appPath: String) {
        lock.lock(); let pids = suspended.removeValue(forKey: appPath); save(); lock.unlock()
        for pid in pids ?? [] { kill(pid, SIGCONT) }
        if pids != nil { Log.refresh.debug("energy: resumed \(appPath, privacy: .public)") }
    }

    /// Thaw everything — called when the Mac goes back on power, and on quit so
    /// we never leave an app frozen.
    static func resumeAll() {
        lock.lock(); let all = suspended; suspended = [:]; save(); lock.unlock()
        guard !all.isEmpty else { return }
        for pids in all.values { for pid in pids { kill(pid, SIGCONT) } }
        Log.refresh.debug("energy: resumed all (\(all.count) apps)")
    }

    /// On launch, thaw any apps left frozen by a previous crash — but only PIDs
    /// that still belong to the same app bundle (a recycled PID is skipped).
    static func recoverOnLaunch() {
        lock.lock(); let saved = suspended; lock.unlock()
        for (appPath, pids) in saved {
            let prefix = appPath.hasSuffix("/") ? appPath : appPath + "/"
            for pid in pids where pidPath(pid)?.hasPrefix(prefix) == true {
                kill(pid, SIGCONT)
            }
        }
        lock.lock(); suspended = [:]; save(); lock.unlock()
    }

    // MARK: - Process lookup

    /// Every running PID whose executable lives inside this .app bundle
    /// (main process plus any helpers).
    private static func runningPIDs(under appPath: String) -> [Int32] {
        let maxPids = 8192
        var pids = [pid_t](repeating: 0, count: maxPids)
        let returned = proc_listpids(1 /* PROC_ALL_PIDS */, 0, &pids,
                                     Int32(maxPids * MemoryLayout<pid_t>.size))
        guard returned > 0 else { return [] }
        let count = Int(returned) / MemoryLayout<pid_t>.size
        let prefix = appPath.hasSuffix("/") ? appPath : appPath + "/"
        var result: [Int32] = []
        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0, let path = pidPath(pid), path.hasPrefix(prefix) else { continue }
            result.append(pid)
        }
        return result
    }

    private static func pidPath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: - Persistence

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("PowerDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("suspended-apps.json")
    }

    private static func load() -> [String: [Int32]] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: [Int32]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func save() {
        if let data = try? JSONEncoder().encode(suspended) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
