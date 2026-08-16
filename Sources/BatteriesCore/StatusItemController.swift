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
    private var lowPowerItem: NSMenuItem?
    private var renderedEnergyNames: [String] = []
    /// The "Connect / Disconnect" submenu, populated lazily when opened so
    /// IOBluetooth (and its permission prompt) is only touched on demand.
    private var bluetoothMenu: NSMenu?

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
        // These fire for submenus too (the Bluetooth submenu shares this
        // delegate) — only track open/close for the top-level menu, and never
        // rebuild the main menu while a submenu is closing (that raises an
        // NSInternalInconsistencyException mid-session).
        guard menu === self.menu else { return }
        menuIsOpen = true
    }

    public func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        menuIsOpen = false
        rebuildMenu()
    }

    // MARK: - Menu

    public func menuNeedsUpdate(_ menu: NSMenu) {
        // The Bluetooth submenu populates itself on open, so IOBluetooth is
        // only queried when the user actually wants to connect something.
        if menu === bluetoothMenu {
            rebuildBluetoothMenu(menu)
            return
        }
        store.refresh(reason: "menu-open") // kick a background refresh; menu shows cached data
        rebuildMenu()
    }

    private func rebuildBluetoothMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let devices = BluetoothControl.pairedDevices()
        if devices.isEmpty {
            let empty = NSMenuItem(title: "No Bluetooth devices", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for device in devices {
            let item = NSMenuItem(title: device.name,
                                  action: #selector(toggleBluetoothDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.address
            // Checkmark = connected; clicking toggles it.
            item.state = device.connected ? .on : .off
            item.toolTip = device.connected ? "Disconnect \(device.name)" : "Connect \(device.name)"
            menu.addItem(item)
        }
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

        // Low Power Mode availability appearing/disappearing, or the energy
        // app list changing, are structural — defer to a full rebuild.
        guard (lowPowerItem != nil) == (store.lowPowerEnabled != nil) else { return false }
        // Rebuild if the energy list or any app's paused state changed.
        let suspendedPaths = EnergyControl.suspendedPaths()
        var currentEnergy = store.energyApps.map { "\($0.appPath)|\(suspendedPaths.contains($0.appPath))" }
        for path in suspendedPaths where !store.energyApps.contains(where: { $0.appPath == path }) {
            currentEnergy.append("\(path)|true")
        }
        guard currentEnergy == renderedEnergyNames else { return false }

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
        if let lowPower = store.lowPowerEnabled {
            lowPowerItem?.state = lowPower ? .on : .off
        }
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
        lowPowerItem = nil
        renderedEnergyNames = []
        bluetoothMenu = nil

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

        // ── Low Power Mode (quick toggle) ────────────────────────────
        if let lowPower = store.lowPowerEnabled {
            let item = NSMenuItem(title: "Low Power Mode",
                                  action: #selector(toggleLowPowerMode), keyEquivalent: "")
            item.target = self
            item.state = lowPower ? .on : .off
            menu.addItem(item)
            lowPowerItem = item
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

        // ── Apps using significant energy ────────────────────────────
        // Paused apps use ~zero CPU so they fall off the energy scan; keep
        // showing them (so they can be resumed) by merging them back in.
        var energyRows: [(name: String, path: String, paused: Bool)] =
            store.energyApps.map { ($0.name, $0.appPath, EnergyControl.isSuspended(appPath: $0.appPath)) }
        let listedPaths = Set(store.energyApps.map(\.appPath))
        for path in EnergyControl.suspendedPaths() where !listedPaths.contains(path) {
            let name = (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            energyRows.append((name, path, true))
        }

        if !energyRows.isEmpty {
            addInfo("Apps Using Significant Energy")
            for row in energyRows {
                let item = NSMenuItem(title: row.paused ? "\(row.name) — Paused" : row.name,
                                      action: nil, keyEquivalent: "")
                item.image = Self.appIcon(path: row.path)

                let sub = NSMenu()
                if row.paused {
                    let resume = NSMenuItem(title: "Resume Now",
                                            action: #selector(resumeEnergyApp(_:)), keyEquivalent: "")
                    resume.target = self
                    resume.representedObject = row.path
                    resume.toolTip = "Unfreeze \(row.name) now"
                    sub.addItem(resume)
                } else {
                    let front = NSMenuItem(title: "Bring to Front",
                                           action: #selector(activateEnergyApp(_:)), keyEquivalent: "")
                    front.target = self
                    front.representedObject = row.path
                    sub.addItem(front)

                    let pause = NSMenuItem(title: "Pause Until Plugged In",
                                           action: #selector(pauseEnergyApp(_:)), keyEquivalent: "")
                    pause.target = self
                    pause.representedObject = row.path
                    pause.toolTip = "Freeze \(row.name) so it stops draining the battery, "
                                  + "until the Mac is next on power (it will be unresponsive while paused)"
                    sub.addItem(pause)
                }
                item.submenu = sub
                menu.addItem(item)
            }
            renderedEnergyNames = energyRows.map { "\($0.path)|\($0.paused)" }
            menu.addItem(.separator())
        }

        // ── Connect / Disconnect (Bluetooth) ─────────────────────────
        let btItem = NSMenuItem(title: "Connect / Disconnect", action: nil, keyEquivalent: "")
        let btMenu = NSMenu()
        btMenu.delegate = self          // populated lazily in menuNeedsUpdate
        btItem.submenu = btMenu
        bluetoothMenu = btMenu
        menu.addItem(btItem)

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

    /// A small icon for an app path, for energy-app rows.
    private static func appIcon(path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
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

        let showEnergy = NSMenuItem(title: "Show Energy-Intensive Apps",
                                    action: #selector(toggleShowEnergy), keyEquivalent: "")
        showEnergy.target = self
        showEnergy.state = Preferences.showEnergyApps ? .on : .off
        prefsMenu.addItem(showEnergy)

        let notifyEnergy = NSMenuItem(title: "Notify About Energy-Intensive Apps",
                                      action: #selector(toggleNotifyEnergy), keyEquivalent: "")
        notifyEnergy.target = self
        notifyEnergy.state = Preferences.notifyEnergyApps ? .on : .off
        // Notifying is only meaningful if we're scanning at all.
        notifyEnergy.isEnabled = Preferences.showEnergyApps
        prefsMenu.addItem(notifyEnergy)

        prefsMenu.addItem(.separator())

        let airpods = NSMenuItem(title: "AirPods Pop-up When Case Opens",
                                 action: #selector(toggleAirPodsPopup), keyEquivalent: "")
        airpods.target = self
        airpods.state = Preferences.airPodsPopupEnabled ? .on : .off
        airpods.toolTip = "Show a battery card when you open your AirPods case nearby "
                        + "(uses always-on Bluetooth scanning)"
        prefsMenu.addItem(airpods)

        let airpodsMenuBattery = NSMenuItem(title: "Show AirPods Battery in Menu",
                                            action: #selector(toggleAirPodsMenuBattery), keyEquivalent: "")
        airpodsMenuBattery.target = self
        airpodsMenuBattery.state = Preferences.airPodsMenuBatteryEnabled ? .on : .off
        airpodsMenuBattery.toolTip = "Keep AirPods battery visible in the menu the moment the case "
                                   + "opens nearby, even before they're connected (uses always-on "
                                   + "Bluetooth scanning)"
        prefsMenu.addItem(airpodsMenuBattery)

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

    @objc private func toggleShowEnergy() {
        Preferences.showEnergyApps.toggle()
        if Preferences.showEnergyApps {
            store.refresh(reason: "manual")
        }
    }

    @objc private func toggleNotifyEnergy() {
        Preferences.notifyEnergyApps.toggle()
        if Preferences.notifyEnergyApps {
            NotificationManager.shared.requestAuthorization()
        }
    }

    @objc private func toggleAirPodsPopup() {
        Preferences.airPodsPopupEnabled.toggle()
        AirPodsMonitor.shared.setEnabled(Preferences.airPodsScanningEnabled)
    }

    @objc private func toggleAirPodsMenuBattery() {
        Preferences.airPodsMenuBatteryEnabled.toggle()
        AirPodsMonitor.shared.setEnabled(Preferences.airPodsScanningEnabled)
    }

    @objc private func toggleLowPowerMode() {
        // pmset needs root, so this shows the native admin prompt and blocks
        // until the user responds — run it off the main thread, then refresh
        // to reflect the new state.
        let target = !(store.lowPowerEnabled ?? false)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            PowerMode.setLowPower(target)
            DispatchQueue.main.async { self?.store.reloadLowPowerMode() }
        }
    }

    @objc private func activateEnergyApp(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func pauseEnergyApp(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        // kill(2) blocks only briefly, but process enumeration can take a
        // moment — do it off the main thread, then rebuild so the row flips
        // to "Paused" / "Resume Now".
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            EnergyControl.suspend(appPath: path)
            DispatchQueue.main.async { self?.refreshUI() }
        }
    }

    @objc private func resumeEnergyApp(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            EnergyControl.resume(appPath: path)
            DispatchQueue.main.async { self?.refreshUI() }
        }
    }

    @objc private func toggleBluetoothDevice(_ sender: NSMenuItem) {
        guard let address = sender.representedObject as? String else { return }
        // openConnection/closeConnection block briefly — do it off the main
        // thread so the menu closes cleanly.
        DispatchQueue.global(qos: .userInitiated).async {
            BluetoothControl.toggle(address: address)
        }
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
