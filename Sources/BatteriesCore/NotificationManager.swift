import Foundation
import UserNotifications

final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    /// UNUserNotificationCenter crashes in unbundled executables (`swift run`),
    /// so notifications only work when running from Batteries.app.
    private let available = Bundle.main.bundleIdentifier != nil

    /// Devices already alerted this discharge cycle, so we alert once.
    private var lowNotified = Set<String>()
    /// Devices already alerted this charge cycle.
    private var fullNotified = Set<String>()
    /// Apps already alerted for high energy, cleared once they calm down.
    private var energyNotified = Set<String>()

    /// Charge alerts only make sense for devices that report reliable levels;
    /// Bluetooth accessories often sit at 100% in their case for hours.
    private static let fullAlertKinds: Set<DeviceBattery.Kind> = [.mac, .iphone, .ipad]

    private static let lowBatteryCategory = "LOW_BATTERY"
    private static let fullChargeCategory = "FULL_CHARGE"
    private static let energyAppCategory = "ENERGY_APP"
    private static let snoozeAction = "SNOOZE_1H"
    private static let muteAction = "MUTE_DEVICE"
    private static let pauseAppAction = "PAUSE_APP"

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Lets a low-battery/full-charge notification carry a "Snooze 1h" /
    /// "Mute this device" action, and an energy-app notification carry
    /// "Pause Until Plugged In" — instead of doing nothing when clicked.
    private func registerCategories() {
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 1h", options: [])
        let mute = UNNotificationAction(identifier: Self.muteAction, title: "Mute This Device",
                                        options: [.destructive])
        let pause = UNNotificationAction(identifier: Self.pauseAppAction, title: "Pause Until Plugged In",
                                         options: [.destructive])
        let low = UNNotificationCategory(identifier: Self.lowBatteryCategory,
                                         actions: [snooze, mute], intentIdentifiers: [], options: [])
        let full = UNNotificationCategory(identifier: Self.fullChargeCategory,
                                          actions: [mute], intentIdentifiers: [], options: [])
        let energy = UNNotificationCategory(identifier: Self.energyAppCategory,
                                            actions: [pause], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([low, full, energy])
    }

    private var primed = false

    func check(devices: [DeviceBattery]) {
        guard available else { return }

        // Don't announce "fully charged" for devices that were already full
        // when the app launched — only for charges completing while running.
        if !primed {
            primed = true
            for device in devices where Self.fullAlertKinds.contains(device.kind)
                && ((device.percent ?? 0) >= 100 || device.fullyCharged) {
                fullNotified.insert(device.id)
            }
        }

        let muted = Preferences.mutedDeviceIDs
        let threshold = Preferences.lowBatteryThreshold

        for device in devices {
            // Skip devices we couldn't freshly read — alerting off a stale
            // or last-known value risks a wrong or duplicate notification.
            guard let percent = device.percent, !muted.contains(device.id),
                  device.unreachableSince == nil, device.staleSince == nil else { continue }

            // ── Low battery ──────────────────────────────────────────
            if Preferences.notificationsEnabled {
                if percent <= threshold && !device.isCharging {
                    // Snoozed devices are deliberately left out of lowNotified
                    // too, so the alert fires again once the snooze expires
                    // (rather than staying suppressed for the rest of the
                    // discharge cycle).
                    if !lowNotified.contains(device.id) && !Preferences.isSnoozed(deviceID: device.id) {
                        lowNotified.insert(device.id)
                        send(id: "low-\(device.id)",
                             title: "\(device.name) is running low",
                             body: "Battery is at \(percent)%. Time to recharge.",
                             category: Self.lowBatteryCategory,
                             userInfo: ["deviceID": device.id])
                    }
                } else if device.isCharging || percent > threshold + 10 {
                    lowNotified.remove(device.id)
                }
            }

            // ── Fully charged ────────────────────────────────────────
            if Preferences.notifyWhenFullyCharged, Self.fullAlertKinds.contains(device.kind) {
                let isFull = percent >= 100 || device.fullyCharged
                if isFull {
                    if !fullNotified.contains(device.id) {
                        fullNotified.insert(device.id)
                        send(id: "full-\(device.id)",
                             title: "\(device.name) is fully charged",
                             body: "Battery is at 100%. You can unplug it now.",
                             category: Self.fullChargeCategory,
                             userInfo: ["deviceID": device.id])
                    }
                } else if percent < 95 {
                    fullNotified.remove(device.id)
                }
            }
        }
    }

    /// Alerts when an app crosses the high-energy bar, once per app until it
    /// drops back down (hysteresis on the display threshold), so a hog that
    /// hovers near the line doesn't notify repeatedly.
    func checkEnergy(apps: [EnergyApp]) {
        guard available, Preferences.notifyEnergyApps else { return }
        let hot = Set(apps.filter { $0.impact >= EnergyMonitor.notifyThreshold }.map(\.name))

        for app in apps where app.impact >= EnergyMonitor.notifyThreshold {
            // Skip apps the user opted out of ("Notify About This App" off).
            if Preferences.isEnergyNotifyMuted(appPath: app.appPath) { continue }
            if !energyNotified.contains(app.name) {
                energyNotified.insert(app.name)
                send(id: "energy-\(app.name)",
                     title: "\(app.name) is using significant energy",
                     body: "It's a heavy battery drain right now. Quit it to save power.",
                     category: Self.energyAppCategory,
                     userInfo: ["appPath": app.appPath])
            }
        }
        // Re-arm apps that have calmed below the display threshold, or dropped
        // out of the list entirely.
        let stillElevated = Set(apps.filter { $0.impact >= EnergyMonitor.displayThreshold }.map(\.name))
        energyNotified.formIntersection(stillElevated.union(hot))
    }

    private func send(id: String, title: String, body: String, category: String? = nil,
                      userInfo: [String: String] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        content.userInfo = userInfo
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Without this, a notification silently does nothing while the app is
    /// in the foreground — show it as a banner regardless.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case Self.snoozeAction:
            guard let deviceID = userInfo["deviceID"] as? String else { return }
            Preferences.snooze(deviceID: deviceID, for: 3600)
            lowNotified.remove(deviceID)
        case Self.muteAction:
            guard let deviceID = userInfo["deviceID"] as? String else { return }
            Preferences.mute(deviceID: deviceID)
            lowNotified.remove(deviceID)
            fullNotified.remove(deviceID)
        case Self.pauseAppAction:
            guard let appPath = userInfo["appPath"] as? String else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                EnergyControl.suspend(appPath: appPath)
            }
        default:
            break
        }
    }
}
