import Foundation
import UserNotifications

final class NotificationManager {
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

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
                    if !lowNotified.contains(device.id) {
                        lowNotified.insert(device.id)
                        send(id: "low-\(device.id)",
                             title: "\(device.name) is running low",
                             body: "Battery is at \(percent)%. Time to recharge.")
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
                             body: "Battery is at 100%. You can unplug it now.")
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
            if !energyNotified.contains(app.name) {
                energyNotified.insert(app.name)
                send(id: "energy-\(app.name)",
                     title: "\(app.name) is using significant energy",
                     body: "It's a heavy battery drain right now. Quit it to save power.")
            }
        }
        // Re-arm apps that have calmed below the display threshold, or dropped
        // out of the list entirely.
        let stillElevated = Set(apps.filter { $0.impact >= EnergyMonitor.displayThreshold }.map(\.name))
        energyNotified.formIntersection(stillElevated.union(hot))
    }

    private func send(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
