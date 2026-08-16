import Foundation

enum Preferences {
    private static let defaults = UserDefaults.standard

    static let thresholdChoices = [10, 15, 20, 30]

    static var lowBatteryThreshold: Int {
        get {
            let value = defaults.integer(forKey: "lowBatteryThreshold")
            return value == 0 ? 20 : value
        }
        set { defaults.set(newValue, forKey: "lowBatteryThreshold") }
    }

    static var notificationsEnabled: Bool {
        get { defaults.object(forKey: "notificationsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notificationsEnabled") }
    }

    static var notifyWhenFullyCharged: Bool {
        get { defaults.object(forKey: "notifyWhenFullyCharged") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notifyWhenFullyCharged") }
    }

    /// Whether to scan for and show energy-intensive apps in the menu.
    /// On by default (scanning is throttled), off for battery purists who
    /// don't want the periodic `top` call at all.
    static var showEnergyApps: Bool {
        get { defaults.object(forKey: "showEnergyApps") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showEnergyApps") }
    }

    /// Whether to notify when an app is using a lot of energy. Off by
    /// default — this is the interrupting one.
    static var notifyEnergyApps: Bool {
        get { defaults.object(forKey: "notifyEnergyApps") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "notifyEnergyApps") }
    }

    /// Show the AirPods pop-up card when the case opens nearby. Off by
    /// default — it needs always-on Bluetooth scanning, which has a battery
    /// cost, so it's the user's choice to turn on.
    static var airPodsPopupEnabled: Bool {
        get { defaults.object(forKey: "airPodsPopupEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "airPodsPopupEnabled") }
    }

    /// Show live AirPods battery in the menu (not just the case-open card),
    /// even before they're fully Bluetooth-connected. Also always-on
    /// scanning, so also opt-in and off by default.
    static var airPodsMenuBatteryEnabled: Bool {
        get { defaults.object(forKey: "airPodsMenuBatteryEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "airPodsMenuBatteryEnabled") }
    }

    /// Either AirPods feature wanting live data means the proximity scanner
    /// needs to be running.
    static var airPodsScanningEnabled: Bool {
        airPodsPopupEnabled || airPodsMenuBatteryEnabled
    }

    // MARK: - Per-device notification muting

    static var mutedDeviceIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "mutedDeviceIDs") ?? []) }
        set { defaults.set(Array(newValue), forKey: "mutedDeviceIDs") }
    }

    static func toggleMuted(deviceID: String) {
        var muted = mutedDeviceIDs
        if muted.contains(deviceID) { muted.remove(deviceID) } else { muted.insert(deviceID) }
        mutedDeviceIDs = muted
    }

    /// Mutes a device outright (used by the notification's "Mute" action,
    /// where there's nothing to toggle — it's only offered while unmuted).
    static func mute(deviceID: String) {
        var muted = mutedDeviceIDs
        muted.insert(deviceID)
        mutedDeviceIDs = muted
    }

    // MARK: - Low-battery snooze (from the notification's "Snooze 1h" action)

    private static var snoozedUntil: [String: Date] {
        get {
            let raw = defaults.dictionary(forKey: "snoozedUntil") as? [String: Double] ?? [:]
            return raw.mapValues { Date(timeIntervalSince1970: $0) }
        }
        set { defaults.set(newValue.mapValues { $0.timeIntervalSince1970 }, forKey: "snoozedUntil") }
    }

    static func snooze(deviceID: String, for interval: TimeInterval) {
        var snoozed = snoozedUntil
        snoozed[deviceID] = Date().addingTimeInterval(interval)
        snoozedUntil = snoozed
    }

    static func isSnoozed(deviceID: String) -> Bool {
        guard let until = snoozedUntil[deviceID] else { return false }
        return until > Date()
    }

    /// Every device ever seen (id → name), so the notification toggles can
    /// list devices even when they're currently disconnected.
    static var knownDevices: [String: String] {
        get { defaults.dictionary(forKey: "knownDevices") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "knownDevices") }
    }

    static func registerDevices(_ devices: [DeviceBattery]) {
        var known = knownDevices
        for device in devices { known[device.id] = device.name }
        if known != knownDevices { knownDevices = known }
    }
}
