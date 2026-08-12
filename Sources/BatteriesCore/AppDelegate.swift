import AppKit
import Network

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = BatteryStore()
    private var statusController: StatusItemController?
    private var autoRefreshTimer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var pendingRefresh: DispatchWorkItem?
    private var lastPathStatus: NWPath.Status?

    /// A battery monitor that itself drains the battery defeats the point.
    /// Scan often while plugged in, back off on battery power, and let macOS
    /// coalesce the wakeup with other timers instead of an exact-instant fire.
    private static let acRefreshInterval: TimeInterval = 60
    private static let batteryRefreshInterval: TimeInterval = 300

    /// Lets a build variant extend the app right after launch — e.g. QStore
    /// wiring up its Sparkle updater and appending a "Check for Updates…"
    /// item. nil for the plain build, so behavior there is unchanged.
    public var onLaunch: ((StatusItemController) -> Void)?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.requestAuthorization()

        let controller = StatusItemController(store: store)
        statusController = controller
        store.onUpdate = { [weak self, weak controller] in
            controller?.refreshUI()
            self?.scheduleNextAutoRefresh()
        }
        store.refresh(reason: "launch")

        // Rescan shortly after a genuine network change (e.g. joining Wi-Fi),
        // so iPhones on Wi-Fi appear seconds after connecting instead of on
        // the next timer tick. NWPathMonitor fires pathUpdateHandler on any
        // path property change, not just connect/disconnect — routine churn
        // while already-satisfied would otherwise trigger a refresh (and,
        // via onUpdate, reset the periodic timer's countdown) far more
        // often than intended, undermining the battery-power backoff.
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.lastPathStatus != path.status else { return }
                self.lastPathStatus = path.status
                Log.refresh.debug("network path status changed: \(String(describing: path.status), privacy: .public)")
                self.scheduleRefresh(reason: "network-change")
            }
        }
        monitor.start(queue: .global(qos: .utility))
        pathMonitor = monitor

        // Also rescan right after the Mac wakes from sleep.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        onLaunch?(controller)
    }

    @objc private func didWake() {
        scheduleRefresh(reason: "wake")
    }

    /// Debounced refresh: network transitions fire several path updates in a
    /// row, so wait for things to settle before scanning.
    private func scheduleRefresh(reason: String) {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.store.refresh(reason: reason) }
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
        Log.refresh.debug("next auto-refresh in \(interval, format: .fixed(precision: 0))s (onAC: \(onAC))")

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.store.refresh(reason: "timer")
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        autoRefreshTimer = timer
    }
}
