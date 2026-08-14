import Foundation

/// Holds the latest snapshot of all battery levels and refreshes it off the
/// main thread. Bluetooth/iOS queries shell out and can take a few seconds,
/// so the menu always renders from the cached snapshot.
final class BatteryStore {
    private(set) var mac: DeviceBattery?
    private(set) var health: BatteryHealthInfo?
    private(set) var devices: [DeviceBattery] = []
    private(set) var lastUpdated: Date?
    /// Low Power Mode state, or nil if the Mac doesn't report it.
    private(set) var lowPowerEnabled: Bool?
    /// Apps currently using significant energy (empty when the feature is off).
    private(set) var energyApps: [EnergyApp] = []

    var onUpdate: (() -> Void)?

    private let queue = DispatchQueue(label: "com.batteries.refresh", qos: .utility)
    private var refreshing = false

    /// Energy scanning shells out to `top` (a couple seconds, real CPU), so
    /// it runs at most this often — far less than the battery refresh — to
    /// keep a battery monitor from being an energy drain itself. Touched only
    /// on the serial refresh queue.
    private static let energyScanInterval: TimeInterval = 180
    private var lastEnergyScan: Date?

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

            // Fill in battery for BLE accessories (e.g. an MX Master) that
            // system_profiler reports as "—" but that expose the standard GATT
            // Battery Service — read directly over CoreBluetooth. Kick a fresh
            // (throttled) read, then merge whatever's cached from prior reads,
            // matching by device name.
            BLEBatteryReader.shared.refresh()
            bluetooth = bluetooth.map { device in
                guard device.percent == nil else { return device }
                // Standard GATT battery service (mice, keyboards, headphones).
                if let ble = BLEBatteryReader.shared.battery(forName: device.name) {
                    return device.withPercent(ble)
                }
                // AirPods proximity broadcast (only when the pop-up scanner is on).
                if let ap = AirPodsMonitor.shared.battery(forName: device.name)?.minPod {
                    return device.withPercent(ap)
                }
                return device
            }

            var devices = ios + bluetooth
            // Fold in accessories that were seen before but are missing from
            // this scan, marked unreachable rather than silently dropped.
            devices = DeviceRegistry.reconcile(current: devices)
            // The same iPhone/iPad can be reported by both sources at once
            // (a Bluetooth MAC address and a libimobiledevice UDID) — keep
            // whichever entry is more useful: a real percent beats "—",
            // and among two real readings the fresher one wins.
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

            let lowPower = PowerMode.lowPowerEnabled()

            // Freshly-scanned energy apps, or nil to mean "kept the previous
            // list this cycle" (throttled). Runs on this serial queue, so the
            // lastEnergyScan bookkeeping needs no extra locking.
            var freshEnergy: [EnergyApp]? = nil
            if Preferences.showEnergyApps {
                let now = Date()
                let due = (self?.lastEnergyScan).map { now.timeIntervalSince($0) >= Self.energyScanInterval } ?? true
                if due {
                    freshEnergy = EnergyMonitor.scan()
                    self?.lastEnergyScan = now
                }
            } else {
                freshEnergy = []
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.mac = mac
                self.health = health
                self.devices = devices
                self.lowPowerEnabled = lowPower
                if let freshEnergy { self.energyApps = freshEnergy }
                self.lastUpdated = Date()
                self.refreshing = false
                let elapsed = Date().timeIntervalSince(start)
                Log.refresh.debug("done (\(reason, privacy: .public)) in \(elapsed, format: .fixed(precision: 2))s, \(devices.count) devices")
                self.onUpdate?()

                var all = devices
                if let mac { all.append(mac) }
                Preferences.registerDevices(all)
                NotificationManager.shared.check(devices: all)
                // Only evaluate energy alerts on a fresh scan, not when we
                // reused the throttled list.
                if let freshEnergy {
                    NotificationManager.shared.checkEnergy(apps: freshEnergy)
                }

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

    /// Re-reads only the Low Power Mode state (cheap) and notifies, so the
    /// menu's checkmark reflects a toggle right away instead of waiting for
    /// the next throttled full refresh.
    func reloadLowPowerMode() {
        queue.async { [weak self] in
            let lowPower = PowerMode.lowPowerEnabled()
            DispatchQueue.main.async {
                self?.lowPowerEnabled = lowPower
                self?.onUpdate?()
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
