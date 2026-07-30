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

    func refresh() {
        guard !refreshing else { return }
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < Self.minimumRefreshInterval {
            return
        }
        refreshing = true
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
            devices.sort { a, b in
                if (a.percent != nil) != (b.percent != nil) { return a.percent != nil }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.mac = mac
                self.health = health
                self.devices = devices
                self.lastUpdated = Date()
                self.refreshing = false
                self.onUpdate?()

                var all = devices
                if let mac { all.append(mac) }
                Preferences.registerDevices(all)
                NotificationManager.shared.check(devices: all)
            }
        }
    }
}
