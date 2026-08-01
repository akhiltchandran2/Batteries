import Foundation

/// Holds the latest snapshot of all battery levels and refreshes it off the
/// main thread. Bluetooth/iOS queries shell out and can take a few seconds,
/// so the menu always renders from the cached snapshot.
final class BatteryStore {
    private(set) var mac: DeviceBattery?
    private(set) var health: BatteryHealthInfo?
    private(set) var devices: [DeviceBattery] = []
    private(set) var lastUpdated: Date?

    var onUpdate: (() -> Void)?

    private let queue = DispatchQueue(label: "com.batteries.refresh", qos: .utility)
    private var refreshing = false

    /// Each refresh shells out to system_profiler and libimobiledevice, which
    /// costs real CPU. Rapid triggers (opening the menu a few times, a burst
    /// of network-change events) shouldn't each kick off a fresh scan — the
    /// menu already renders from the cached snapshot between refreshes.
    private static let minimumRefreshInterval: TimeInterval = 15

    /// `reason` is purely diagnostic — it's what shows up in the log to
    /// answer "what triggered this scan" (timer, menu open, network change,
    /// wake, launch, manual).
    func refresh(reason: String = "unspecified") {
        guard !refreshing else {
            Log.refresh.debug("skip (\(reason, privacy: .public)): already refreshing")
            return
        }
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < Self.minimumRefreshInterval {
            Log.refresh.debug("skip (\(reason, privacy: .public)): throttled, last update was recent")
            return
        }
        refreshing = true
        let start = Date()
        Log.refresh.debug("start (\(reason, privacy: .public))")
        queue.async { [weak self] in
            let mac = MacBattery.read()
            let health = BatteryHealth.read()
            let ios = IOSDevices.read()
            var bluetooth = BluetoothBatteries.read()

            // An iPhone/iPad reachable via libimobiledevice also shows up in
            // the Bluetooth list without a battery level — keep the iOS entry.
            let iosNames = Set(ios.map { $0.name.lowercased() })
            bluetooth.removeAll { iosNames.contains($0.name.lowercased()) }

            var devices = ios + bluetooth
            // Fold in accessories that were seen before but are missing from
            // this scan, marked unreachable rather than silently dropped.
            devices = DeviceRegistry.reconcile(current: devices)
            // The same iPhone/iPad can persist under two different IDs (a
            // Bluetooth MAC address and a libimobiledevice UDID); once both
            // go unreachable independently they'd otherwise show as two
            // rows for the same physical device.
            devices = Self.deduplicated(devices)
            devices.sort { a, b in
                if (a.unreachableSince == nil) != (b.unreachableSince == nil) {
                    return a.unreachableSince == nil
                }
                if (a.percent != nil) != (b.percent != nil) { return a.percent != nil }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

            if let mac, let percent = mac.percent {
                BatteryHistory.record(id: mac.id, name: mac.name, percent: percent)
            }
            for device in devices where device.unreachableSince == nil && device.staleSince == nil {
                if let percent = device.percent {
                    BatteryHistory.record(id: device.id, name: device.name, percent: percent)
                }
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.mac = mac
                self.health = health
                self.devices = devices
                self.lastUpdated = Date()
                self.refreshing = false
                let elapsed = Date().timeIntervalSince(start)
                Log.refresh.debug("done (\(reason, privacy: .public)) in \(elapsed, format: .fixed(precision: 2))s, \(devices.count) devices")
                self.onUpdate?()

                var all = devices
                if let mac { all.append(mac) }
                Preferences.registerDevices(all)
                NotificationManager.shared.check(devices: all)

                WidgetSnapshot(
                    mac: mac.map {
                        WidgetSnapshot.Entry(id: $0.id, name: $0.name, symbolName: $0.kind.symbolName,
                                             percent: $0.percent, isCharging: $0.isCharging)
                    },
                    devices: devices.filter { $0.unreachableSince == nil }.map {
                        WidgetSnapshot.Entry(id: $0.id, name: $0.name, symbolName: $0.kind.symbolName,
                                             percent: $0.percent, isCharging: $0.isCharging)
                    },
                    generatedAt: Date()
                ).write()
            }
        }
    }

    /// Keeps one entry per device name. A real percent beats "—" regardless
    /// of freshness — a stale 81% tells the user more than a live-but-empty
    /// reading — then among equally-informative entries, live beats
    /// stale-but-present beats unreachable, with the more recent sighting
    /// as a final tiebreak.
    private static func deduplicated(_ devices: [DeviceBattery]) -> [DeviceBattery] {
        var bestByName: [String: DeviceBattery] = [:]
        for device in devices {
            let key = device.name.lowercased()
            if let existing = bestByName[key], !isBetter(device, than: existing) {
                continue
            }
            bestByName[key] = device
        }
        return Array(bestByName.values)
    }

    private static func isBetter(_ a: DeviceBattery, than b: DeviceBattery) -> Bool {
        if (a.percent != nil) != (b.percent != nil) { return a.percent != nil }

        func freshness(_ d: DeviceBattery) -> Int {
            if d.unreachableSince != nil { return 0 }
            if d.staleSince != nil { return 1 }
            return 2
        }
        let freshA = freshness(a), freshB = freshness(b)
        if freshA != freshB { return freshA > freshB }

        switch freshA {
        case 0: return (a.unreachableSince ?? .distantPast) > (b.unreachableSince ?? .distantPast)
        case 1: return (a.staleSince ?? .distantPast) > (b.staleSince ?? .distantPast)
        default: return false
        }
    }
}
