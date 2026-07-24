import AppKit
import Network

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = BatteryStore()
    private var statusController: StatusItemController?
    private var timer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var pendingRefresh: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestAuthorization()

        let controller = StatusItemController(store: store)
        statusController = controller
        store.onUpdate = { [weak controller] in controller?.refreshUI() }
        store.refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.store.refresh()
        }

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
}
