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
        guard let output = Shell.runString(ideviceID, ["-l", "-n"], timeout: 10) else { return [] }

        var seen = Set<String>()
        var devices: [DeviceBattery] = []
        for line in output.split(separator: "\n") {
            // Lines look like "00008150-… (USB)" or "00008150-… (Network)" —
            // the UDID is the first whitespace-separated token.
            let udid = line.split(separator: " ").first.map(String.init) ?? ""
            guard !udid.isEmpty, !seen.contains(udid) else { continue }
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
            }
        }
        return devices
    }

    private static func readDevice(udid: String, ideviceinfo: String) -> DeviceBattery? {
        func value(_ args: [String]) -> String? {
            // Try USB first, then the network connection.
            Shell.runString(ideviceinfo, ["-u", udid] + args, timeout: 8)
                ?? Shell.runString(ideviceinfo, ["-u", udid, "-n"] + args, timeout: 8)
        }

        guard let percentText = value(["-q", "com.apple.mobile.battery", "-k", "BatteryCurrentCapacity"]),
              let percent = Int(percentText) else { return nil }

        let name = value(["-k", "DeviceName"]) ?? "iOS Device"
        let deviceClass = value(["-k", "DeviceClass"]) ?? "iPhone"
        let charging = value(["-q", "com.apple.mobile.battery", "-k", "BatteryIsCharging"]) == "true"

        return DeviceBattery(
            id: "ios-\(udid)",
            name: name,
            kind: deviceClass.lowercased().contains("ipad") ? .ipad : .iphone,
            percent: percent,
            isCharging: charging
        )
    }
}
