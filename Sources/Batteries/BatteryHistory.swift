import Foundation

/// Rolling ~24h history of battery levels per device, backing the sparklines
/// in the "Battery History" menu. Persisted to disk so history survives app
/// restarts.
enum BatteryHistory {
    struct Sample: Codable {
        let date: Date
        let percent: Int
    }

    private struct Series: Codable {
        var name: String
        var samples: [Sample]
    }

    private static let window: TimeInterval = 24 * 3600
    private static let maxSamplesPerDevice = 400
    /// Skip near-duplicate points so a device parked at one level for hours
    /// doesn't bloat the log with identical samples.
    private static let minSampleGap: TimeInterval = 240

    private static let lock = NSLock()
    private static var store: [String: Series] = load()

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("Batteries", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private static func load() -> [String: Series] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Series].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func save() {
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Records a live reading. Only call with fresh percentages — feeding it
    /// a stale/cached value would draw flat stretches that never happened.
    static func record(id: String, name: String, percent: Int) {
        lock.lock(); defer { lock.unlock() }

        let now = Date()
        var series = store[id]?.samples ?? []
        if let last = series.last, last.percent == percent,
           now.timeIntervalSince(last.date) < minSampleGap {
            store[id]?.name = name
            return
        }

        series.append(Sample(date: now, percent: percent))
        let cutoff = now.addingTimeInterval(-window)
        series.removeAll { $0.date < cutoff }
        if series.count > maxSamplesPerDevice {
            series.removeFirst(series.count - maxSamplesPerDevice)
        }
        store[id] = Series(name: name, samples: series)
        save()
    }

    static func availableSeries() -> [(id: String, name: String, samples: [Sample])] {
        lock.lock(); defer { lock.unlock() }
        return store.compactMap { id, series in
            guard series.samples.count >= 2 else { return nil }
            return (id, series.name, series.samples)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
