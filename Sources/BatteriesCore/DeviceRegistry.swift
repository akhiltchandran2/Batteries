import Foundation

/// Remembers every accessory the app has seen so one that stops responding
/// shows up as "Unreachable" instead of silently vanishing from the menu —
/// a device disappearing looks identical to "everything's fine" otherwise.
/// Persisted to disk so it survives app restarts.
enum DeviceRegistry {
    private struct Entry: Codable {
        var device: DeviceBattery
        var lastSeen: Date
    }

    /// Devices unreachable longer than this are dropped rather than shown
    /// forever — an accessory not seen in a day just isn't around anymore.
    private static let staleAfter: TimeInterval = 24 * 3600

    private static let lock = NSLock()
    private static var entries: [String: Entry] = load()

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("PowerDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("device-registry.json")
    }

    private static func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func save() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Feed the current scan's devices in; get back that same list plus any
    /// previously-seen devices that are now missing, marked unreachable.
    static func reconcile(current: [DeviceBattery]) -> [DeviceBattery] {
        lock.lock(); defer { lock.unlock() }

        let now = Date()
        var seenIDs = Set<String>()
        for device in current {
            seenIDs.insert(device.id)
            entries[device.id] = Entry(device: device, lastSeen: now)
        }

        var result = current
        for (id, entry) in entries where !seenIDs.contains(id) {
            if now.timeIntervalSince(entry.lastSeen) > staleAfter {
                entries.removeValue(forKey: id)
                continue
            }
            var missing = entry.device
            missing.staleSince = nil
            missing.unreachableSince = entry.lastSeen
            result.append(missing)
        }

        save()
        return result
    }
}
