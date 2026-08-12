import Foundation

/// Reads iPhone/iPad batteries over USB or Wi-Fi using libimobiledevice
/// (`brew install libimobiledevice`). Wi-Fi requires "Show this device when
/// on Wi-Fi" to be enabled for the device in Finder.
enum IOSDevices {
    static var toolsAvailable: Bool {
        Shell.findTool("idevice_id") != nil && Shell.findTool("ideviceinfo") != nil
    }

    /// Last successful reading per device. iOS refuses battery queries while
    /// the device is locked, so we keep showing the last known level.
    /// Persisted to disk so it survives app restarts; entries expire after
    /// a week. Only touched from BatteryStore's serial refresh queue.
    private struct CachedReading: Codable {
        var device: DeviceBattery
        var date: Date
    }

    private static var lastKnown: [String: CachedReading] = loadCache()

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("Batteries", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ios-cache.json")
    }

    private static func loadCache() -> [String: CachedReading] {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode([String: CachedReading].self, from: data) else {
            return [:]
        }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        return cache.filter { $0.value.date > cutoff }
    }

    private static func saveCache() {
        if let data = try? JSONEncoder().encode(lastKnown) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    static func read() -> [DeviceBattery] {
        guard let ideviceID = Shell.findTool("idevice_id"),
              let ideviceinfo = Shell.findTool("ideviceinfo") else { return [] }

        // -l lists USB devices, -n lists network (Wi-Fi sync) devices.
        guard let output = Shell.runString(ideviceID, ["-l", "-n"], timeout: 10) else {
            return []
        }

        var seen = Set<String>()
        var devices: [DeviceBattery] = []
        for line in output.split(separator: "\n") {
            guard let udid = parseUDID(from: line), !seen.contains(udid) else { continue }
            seen.insert(udid)
            if let device = readDevice(udid: udid, ideviceinfo: ideviceinfo) {
                lastKnown[udid] = CachedReading(device: device, date: Date())
                saveCache()
                devices.append(device)
            } else if let cached = lastKnown[udid] {
                // Device is present but locked — show the last known level.
                var stale = cached.device
                stale.staleSince = cached.date
                devices.append(stale)
                Log.devices.debug("\(udid, privacy: .public) unreadable, using cached reading from \(cached.date)")
            } else {
                Log.devices.debug("\(udid, privacy: .public) present but unreadable and no cached reading")
            }
        }
        return devices
    }

    /// Lines look like "00008150-… (USB)" or "00008150-… (Network)" — the
    /// UDID is the first whitespace-separated token. Pure and internal
    /// (not private) so it's directly testable.
    static func parseUDID(from line: Substring) -> String? {
        let udid = line.split(separator: " ").first.map(String.init) ?? ""
        return udid.isEmpty ? nil : udid
    }

    private static func readDevice(udid: String, ideviceinfo: String) -> DeviceBattery? {
        // One call for the battery domain (capacity + charging), one for
        // general info (name + class) — down from up to 4 keys x up to 2
        // (USB then network fallback) = 8 process spawns to at most 4.
        guard let battery = dump(ideviceinfo, udid: udid, domain: "com.apple.mobile.battery"),
              let percentText = battery["BatteryCurrentCapacity"],
              let percent = Int(percentText) else {
            return nil
        }

        let general = dump(ideviceinfo, udid: udid, domain: nil) ?? [:]
        let name = general["DeviceName"] ?? "iOS Device"
        let deviceClass = general["DeviceClass"] ?? "iPhone"
        let charging = battery["BatteryIsCharging"] == "true"

        return DeviceBattery(
            id: "ios-\(udid)",
            name: name,
            kind: deviceClass.lowercased().contains("ipad") ? .ipad : .iphone,
            percent: percent,
            isCharging: charging
        )
    }

    private static func dump(_ ideviceinfo: String, udid: String, domain: String?) -> [String: String]? {
        var args = ["-u", udid]
        if let domain { args += ["-q", domain] }
        let output = Shell.runString(ideviceinfo, args, timeout: 8)
            ?? Shell.runString(ideviceinfo, args + ["-n"], timeout: 8)
        guard let output else { return nil }
        return parseInfoOutput(output)
    }

    /// ideviceinfo prints "Key: Value" per line (values can themselves
    /// contain colons, e.g. a MAC address, so only the first colon splits
    /// key from value). A few keys have nested continuation lines that
    /// this doesn't unpack correctly, but none of the keys this app reads
    /// are nested, so that's harmless here. Pure and internal for tests.
    static func parseInfoOutput(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { result[key] = value }
        }
        return result
    }
}
