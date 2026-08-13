import Foundation

/// Reads and toggles macOS Low Power Mode.
///
/// Reading is unprivileged (`pmset -g`). Changing it is not — `pmset` must run
/// as root — so `setLowPower` goes through osascript's "with administrator
/// privileges", which shows the standard macOS authorization prompt. There is
/// no way for an unprivileged, ad-hoc-signed app to flip it silently.
enum PowerMode {
    /// Current Low Power Mode state, or nil if pmset didn't report the key
    /// (e.g. a desktop Mac that doesn't support it).
    static func lowPowerEnabled() -> Bool? {
        guard let out = Shell.runString("/usr/bin/pmset", ["-g"], timeout: 5) else { return nil }
        for line in out.split(separator: "\n") where line.contains("lowpowermode") {
            // " lowpowermode         0"
            if let value = line.split(separator: " ", omittingEmptySubsequences: true).last {
                return value == "1"
            }
        }
        return nil
    }

    /// Toggles Low Power Mode for all power sources. Triggers the native admin
    /// auth prompt. Returns true if the change was authorized and applied.
    /// Runs synchronously (the auth sheet blocks), so call it off the main
    /// thread if you don't want to stall the UI while the user authenticates.
    @discardableResult
    static func setLowPower(_ enabled: Bool) -> Bool {
        let value = enabled ? "1" : "0"
        let script = "do shell script \"/usr/bin/pmset -a lowpowermode \(value)\" "
                   + "with administrator privileges"
        let ok = Shell.runString("/usr/bin/osascript", ["-e", script], timeout: 120) != nil
        Log.refresh.debug("Low Power Mode set to \(value) — authorized: \(ok)")
        return ok
    }
}
