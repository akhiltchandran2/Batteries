import AppKit
import ServiceManagement

public final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let store: BatteryStore
    private let menu = NSMenu()
    private var menuIsOpen = false

    /// Items appended to the App Settings submenu by a build variant — e.g.
    /// QStore's "Check for Updates…" item. Empty for the plain build, so
    /// its menu is unchanged.
    public var extraSettingsItems: [NSMenuItem] = []

    /// Rows built during the last rebuildMenu(), kept around so a refresh
    /// that completes while the menu is on screen can update displayed
    /// values in place instead of waiting for the menu to close — full
    /// item-structure rebuilds are deferred until close because doing that
    /// while the menu is visible can leave stale empty space if the content
    /// shrinks.
    private struct DeviceRowSet {
        let row: BatteryRowView
        let statusRow: InfoRowView?
        let componentRows: [BatteryRowView]
    }
    private var headerRow: BatteryRowView?
    private var powerSourceRow: InfoRowView?
    private var chargeStatusRow: InfoRowView?
    private var healthRow: InfoRowView?
    private var deviceRows: [String: DeviceRowSet] = [:]
    private var lastDeviceOrder: [String] = []

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    init(store: BatteryStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        refreshUI()
    }

    // MARK: - Menu bar button

    func refreshUI() {
        guard let button = statusItem.button else { return }
        let mac = store.mac
        let onAC = mac?.powerSource == "Power Adapter"
        let critical = (mac?.percent ?? 100) <= 10 && !onAC
        button.image = BatteryIcon.make(percent: mac?.percent, showBolt: onAC,
                                        critical: critical)
        if let percent = mac?.percent {
            button.toolTip = "Battery: \(percent)%"
        } else {
            button.toolTip = "Batteries"
        }
        if menuIsOpen {
            // Try to refresh the already-visible menu's values in place so
            // opening the menu actually shows live data instead of whatever
            // was cached at open time. If the structure changed (a device
            // appeared/disappeared, a status line's presence changed), this
            // bails out safely — menuDidClose always does a full rebuild
            // regardless, so nothing is lost, just deferred as before.
            _ = attemptSoftUpdate()
        } else {
            rebuildMenu()
        }
    }

    public func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
    }

    public func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        rebuildMenu()
    }

    // MARK: - Menu

    public func menuNeedsUpdate(_ menu: NSMenu) {
        store.refresh(reason: "menu-open") // kick a background refresh; menu shows cached data
        rebuildMenu()
    }

    private static func chargeStatusText(for mac: DeviceBattery) -> String? {
        if mac.fullyCharged { return "Fully Charged" }
        if let time = mac.timeRemaining { return time }
        if mac.isCharging { return "Charging" }
        return nil
    }

    private static func healthText(for health: BatteryHealthInfo) -> String? {
        var parts: [String] = []
        if let condition = health.condition { parts.append(condition) }
        if let cycles = health.cycleCount { parts.append("\(cycles) cycles") }
        guard !parts.isEmpty else { return nil }
        return "Health: " + parts.joined(separator: " · ")
    }

    /// Updates every displayed value to match the current store state
    /// without touching the menu's item structure. Returns false (doing
    /// nothing) if the structure has actually changed since the last
    /// rebuild, so the caller can fall back to the existing defer-until-
    /// close behavior for that case.
    private func attemptSoftUpdate() -> Bool {
        let mac = store.mac
        guard headerRow != nil else { return false }
        guard (powerSourceRow != nil) == (mac != nil) else { return false }

        let chargeText = mac.flatMap(Self.chargeStatusText(for:))
        guard (chargeStatusRow != nil) == (chargeText != nil) else { return false }

        let healthText = store.health.flatMap(Self.healthText(for:))
        guard (healthRow != nil) == (healthText != nil) else { return false }

        let devices = store.devices
        guard devices.map(\.id) == lastDeviceOrder else { return false }
        for device in devices {
            guard let rowSet = deviceRows[device.id] else { return false }
            let hasStatusLine = device.unreachableSince != nil || device.staleSince != nil
            guard (rowSet.statusRow != nil) == hasStatusLine else { return false }
            let expectedComponentCount = hasStatusLine ? 0 : device.components.count
            guard rowSet.componentRows.count == expectedComponentCount else { return false }
        }

        // Structure matches exactly — safe to update every value in place.
        headerRow?.update(percent: mac?.percent, charging: mac?.isCharging ?? false)
        if let mac {
            powerSourceRow?.update(text: "Power Source: \(mac.powerSource ?? "Unknown")")
        }
        if let chargeText {
            chargeStatusRow?.update(text: chargeText)
        }
        if let healthText {
            healthRow?.update(text: healthText)
        }
        for device in devices {
            guard let rowSet = deviceRows[device.id] else { continue }
            rowSet.row.update(percent: device.percent, charging: device.isCharging)
            if let since = device.unreachableSince {
                rowSet.statusRow?.update(text: "Unreachable since \(Self.clockFormatter.string(from: since))")
            } else if let since = device.staleSince {
                rowSet.statusRow?.update(text: "Reading from \(Self.clockFormatter.string(from: since)) — unlock to update")
            }
            for (component, row) in zip(device.components, rowSet.componentRows) {
                row.update(percent: component.percent, charging: false)
            }
        }
        return true
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        headerRow = nil
        powerSourceRow = nil
        chargeStatusRow = nil
        healthRow = nil
        deviceRows = [:]
        lastDeviceOrder = []

        // ── Header: Battery ................ 84% ─────────────────────
        let mac = store.mac
        let header = BatteryRowView(header: "Battery", percent: mac?.percent)
        addRow(header)
        headerRow = header
        if let mac {
            let powerSource = InfoRowView(text: "Power Source: \(mac.powerSource ?? "Unknown")")
            addRow(powerSource)
            powerSourceRow = powerSource

            if let chargeText = Self.chargeStatusText(for: mac) {
                let row = InfoRowView(text: chargeText)
                addRow(row)
                chargeStatusRow = row
            }
            if let health = store.health, let healthText = Self.healthText(for: health) {
                let row = InfoRowView(text: healthText)
                if let capacity = health.maxCapacityPercent {
                    row.toolTip = "Maximum capacity: \(capacity)% of design"
                }
                addRow(row)
                healthRow = row
            }
        }
        menu.addItem(.separator())

        // ── Connected devices ────────────────────────────────────────
        if store.devices.isEmpty {
            addInfo(store.lastUpdated == nil ? "Scanning for devices…" : "No devices found")
        } else {
            for device in store.devices {
                lastDeviceOrder.append(device.id)
                let muted = device.unreachableSince != nil || device.staleSince != nil
                let row = BatteryRowView(icon: device.kind.symbolName,
                                         title: device.name,
                                         percent: device.percent,
                                         charging: device.isCharging,
                                         isMuted: muted)
                addRow(row)

                var statusRow: InfoRowView?
                var componentRows: [BatteryRowView] = []
                if let since = device.unreachableSince {
                    let info = InfoRowView(text: "Unreachable since \(Self.clockFormatter.string(from: since))",
                                           indented: true)
                    addRow(info)
                    statusRow = info
                } else if let since = device.staleSince {
                    let info = InfoRowView(text: "Reading from \(Self.clockFormatter.string(from: since)) — unlock to update",
                                           indented: true)
                    addRow(info)
                    statusRow = info
                } else {
                    for component in device.components {
                        let componentRow = BatteryRowView(title: component.label,
                                                          percent: component.percent,
                                                          isComponent: true)
                        addRow(componentRow)
                        componentRows.append(componentRow)
                    }
                }
                deviceRows[device.id] = DeviceRowSet(row: row, statusRow: statusRow, componentRows: componentRows)
            }
        }
        menu.addItem(.separator())

        // ── Battery Preferences ──────────────────────────────────────
        let sysPrefs = NSMenuItem(title: "Battery Preferences…",
                                  action: #selector(openBatterySettings), keyEquivalent: "")
        sysPrefs.target = self
        menu.addItem(sysPrefs)

        let appPrefs = NSMenuItem(title: "App Settings", action: nil, keyEquivalent: "")
        appPrefs.submenu = buildPreferencesMenu()
        menu.addItem(appPrefs)

        let history = NSMenuItem(title: "Battery History", action: nil, keyEquivalent: "")
        history.submenu = buildHistoryMenu()
        menu.addItem(history)

        let quit = NSMenuItem(title: "Quit PowerDeck", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func buildHistoryMenu() -> NSMenu {
        let historyMenu = NSMenu()
        let series = BatteryHistory.availableSeries()
        if series.isEmpty {
            let placeholder = NSMenuItem(title: "Collecting data — check back shortly",
                                         action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            historyMenu.addItem(placeholder)
        } else {
            for entry in series {
                let item = NSMenuItem()
                item.view = HistorySparklineView(name: entry.name, samples: entry.samples)
                historyMenu.addItem(item)
            }
        }
        return historyMenu
    }

    private func buildPreferencesMenu() -> NSMenu {
        let prefsMenu = NSMenu()

        let notifyToggle = NSMenuItem(title: "Low Battery Notifications",
                                      action: #selector(toggleNotifications), keyEquivalent: "")
        notifyToggle.target = self
        notifyToggle.state = Preferences.notificationsEnabled ? .on : .off
        prefsMenu.addItem(notifyToggle)

        let thresholdItem = NSMenuItem(title: "Notify Below", action: nil, keyEquivalent: "")
        let thresholdMenu = NSMenu()
        for value in Preferences.thresholdChoices {
            let choice = NSMenuItem(title: "\(value)%", action: #selector(setThreshold(_:)), keyEquivalent: "")
            choice.target = self
            choice.tag = value
            choice.state = (Preferences.lowBatteryThreshold == value) ? .on : .off
            thresholdMenu.addItem(choice)
        }
        thresholdItem.submenu = thresholdMenu
        prefsMenu.addItem(thresholdItem)

        let fullToggle = NSMenuItem(title: "Full Charge Notifications",
                                    action: #selector(toggleFullCharge), keyEquivalent: "")
        fullToggle.target = self
        fullToggle.state = Preferences.notifyWhenFullyCharged ? .on : .off
        prefsMenu.addItem(fullToggle)

        // Per-device notification toggles
        let devicesItem = NSMenuItem(title: "Notifications For", action: nil, keyEquivalent: "")
        let devicesMenu = NSMenu()
        let known = Preferences.knownDevices
            .sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
        if known.isEmpty {
            let empty = NSMenuItem(title: "No devices seen yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            devicesMenu.addItem(empty)
        } else {
            let muted = Preferences.mutedDeviceIDs
            for (id, name) in known {
                let item = NSMenuItem(title: name, action: #selector(toggleDeviceMute(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = id
                item.state = muted.contains(id) ? .off : .on
                devicesMenu.addItem(item)
            }
        }
        devicesItem.submenu = devicesMenu
        prefsMenu.addItem(devicesItem)

        prefsMenu.addItem(.separator())

        if Bundle.main.bundleIdentifier != nil {
            let loginToggle = NSMenuItem(title: "Launch at Login",
                                         action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
            loginToggle.target = self
            loginToggle.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
            prefsMenu.addItem(loginToggle)
        }

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        prefsMenu.addItem(refresh)

        if !IOSDevices.toolsAvailable {
            let hint = NSMenuItem(title: "Get Precise iPhone & iPad Battery %…",
                                  action: #selector(showIOSHelp), keyEquivalent: "")
            hint.target = self
            prefsMenu.addItem(hint)
        }

        if !extraSettingsItems.isEmpty {
            prefsMenu.addItem(.separator())
            for item in extraSettingsItems {
                prefsMenu.addItem(item)
            }
        }

        prefsMenu.addItem(.separator())
        let credit = NSMenuItem()
        credit.view = InfoRowView(text: "Vibe coded by AkhilTChandran with Claude")
        credit.isEnabled = false
        prefsMenu.addItem(credit)

        return prefsMenu
    }

    private func addRow(_ view: NSView) {
        let item = NSMenuItem()
        item.view = view
        menu.addItem(item)
    }

    private func addInfo(_ text: String) {
        addRow(InfoRowView(text: text))
    }

    // MARK: - Actions

    @objc private func refreshNow() {
        store.refresh(reason: "manual")
    }

    @objc private func openBatterySettings() {
        // Deep link to System Settings → Battery
        if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleNotifications() {
        Preferences.notificationsEnabled.toggle()
        if Preferences.notificationsEnabled {
            NotificationManager.shared.requestAuthorization()
        }
    }

    @objc private func toggleFullCharge() {
        Preferences.notifyWhenFullyCharged.toggle()
        if Preferences.notifyWhenFullyCharged {
            NotificationManager.shared.requestAuthorization()
        }
    }

    @objc private func toggleDeviceMute(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Preferences.toggleMuted(deviceID: id)
    }

    @objc private func setThreshold(_ sender: NSMenuItem) {
        Preferences.lowBatteryThreshold = sender.tag
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Launch at login failed: \(error)")
        }
    }

    @objc private func showIOSHelp() {
        let alert = NSAlert()
        alert.messageText = "Precise iPhone & iPad battery levels"
        alert.informativeText = """
        Your iPhone/iPad already appears here via Bluetooth — no cable \
        needed — but it only shows a percentage when Continuity battery \
        sharing is actively reporting one (device unlocked and nearby).

        For a reliable, always-on percentage instead, install \
        libimobiledevice:

            brew install libimobiledevice

        Then connect your device once via USB and tap "Trust". For Wi-Fi, \
        also enable "Show this iPhone when on Wi-Fi" in Finder. The device \
        will keep reporting a precise level as long as it's on the same \
        network — no need to keep it plugged in afterward.
        """
        alert.addButton(withTitle: "Copy Install Command")
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("brew install libimobiledevice", forType: .string)
        }
    }
}
