import AppKit
import Network

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = BatteryStore()
    private var statusController: StatusItemController?
    private var autoRefreshTimer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var pendingRefresh: DispatchWorkItem?

    /// A battery monitor that itself drains the battery defeats the point.
    /// Scan often while plugged in, back off on battery power, and let macOS
    /// coalesce the wakeup with other timers instead of an exact-instant fire.
    private static let acRefreshInterval: TimeInterval = 60
    private static let batteryRefreshInterval: TimeInterval = 300

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestAuthorization()

        let controller = StatusItemController(store: store)
        statusController = controller
        store.onUpdate = { [weak self, weak controller] in
            controller?.refreshUI()
            self?.scheduleNextAutoRefresh()
        }
        store.refresh()

        // Rescan shortly after any network change, so iPhones on Wi-Fi appear
        // seconds after joining the network instead of on the next timer tick.
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.scheduleRefresh() }
        }
        monitor.start(queue: .global(qos: .utility))
        pathMonitor = monitor

        // Also rescan right after the Mac wakes from sleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func didWake() {
        scheduleRefresh()
    }

    /// Debounced refresh: network transitions fire several path updates in a
    /// row, so wait for things to settle before scanning.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.store.refresh() }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// Reschedules the periodic scan after each refresh completes. Using a
    /// self-rescheduling one-shot timer (rather than a fixed repeating one)
    /// means the interval can adapt to the current power source each cycle,
    /// and a slow scan never overlaps with the next tick.
    private func scheduleNextAutoRefresh() {
        autoRefreshTimer?.invalidate()
        let onAC = store.mac?.powerSource == "Power Adapter"
        let interval = onAC ? Self.acRefreshInterval : Self.batteryRefreshInterval

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.store.refresh()
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        autoRefreshTimer = timer
    }
}
