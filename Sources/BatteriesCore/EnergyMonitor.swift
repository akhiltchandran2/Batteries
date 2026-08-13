import Foundation
import Darwin

/// One application currently drawing significant energy, with its per-app
/// energy impact summed across all of its processes (main + helpers).
public struct EnergyApp: Codable, Equatable {
    public let name: String
    public let impact: Double
    /// Path to the owning `.app`, for its icon and to activate it on click.
    public let appPath: String
}

/// Lists the applications using the most energy right now, using the same
/// per-process "energy impact" metric Activity Monitor shows — read from
/// `top` (no root needed) and attributed to the owning app via each PID's
/// executable path, so a browser's helper processes roll up to the browser.
enum EnergyMonitor {
    /// Only surface apps at least this impactful — below this isn't
    /// "significant" and would just be noise.
    static let displayThreshold: Double = 20
    /// A higher bar for notifying, so only genuine hogs interrupt.
    static let notifyThreshold: Double = 50

    /// Runs `top` with two samples (the second has settled CPU-based power)
    /// and returns the top apps by summed energy impact, above the display
    /// threshold. Blocking (~1-2s); call off the main thread.
    static func scan(limit: Int = 4) -> [EnergyApp] {
        guard let out = Shell.runString(
            "/usr/bin/top",
            ["-l", "2", "-n", "60", "-stats", "pid,power", "-o", "power"],
            timeout: 10) else {
            Log.refresh.debug("energy scan: top produced no output")
            return []
        }

        // top prints two snapshots; iterating in order means the second
        // (settled) sample overwrites the first for each PID.
        var powerByPID: [Int32: Double] = [:]
        for line in out.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 2,
                  let pid = Int32(fields[0]),
                  let power = Double(fields[1]) else { continue }
            powerByPID[pid] = power
        }

        // Roll each process up to its owning .app and sum.
        var byApp: [String: EnergyApp] = [:]
        for (pid, power) in powerByPID where power > 0 {
            guard let (name, path) = owningApp(of: pid) else { continue }
            let existing = byApp[path]
            byApp[path] = EnergyApp(name: name,
                                    impact: (existing?.impact ?? 0) + power,
                                    appPath: path)
        }

        return byApp.values
            .filter { $0.impact >= displayThreshold }
            .sorted { $0.impact > $1.impact }
            .prefix(limit)
            .map { $0 }
    }

    /// (display name, .app path) of the application a PID belongs to, or nil
    /// for a process with no owning app (system daemons like WindowServer).
    private static func owningApp(of pid: Int32) -> (name: String, path: String)? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(cString: buffer)
        // e.g. /Applications/Arc.app/Contents/Frameworks/Arc Helper.app/… → Arc
        guard let range = path.range(of: ".app/") else { return nil }
        let appPath = String(path[..<range.lowerBound]) + ".app"
        let name = (appPath as NSString).lastPathComponent
            .replacingOccurrences(of: ".app", with: "")
        return (name, appPath)
    }
}
