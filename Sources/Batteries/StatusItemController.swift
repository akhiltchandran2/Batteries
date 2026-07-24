import AppKit
import ServiceManagement

final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let store: BatteryStore
    private let menu = NSMenu()
    private var menuIsOpen = false

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
        // Rebuilding the items of a menu that is currently on screen leaves
        // stale empty space when the content shrinks, so defer until close —
        // the menu is rebuilt in menuNeedsUpdate before every open anyway.
        if !menuIsOpen {
            rebuildMenu()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        rebuildMenu()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        store.refresh() // kick a background refresh; menu shows cached data
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        // ── Header: Battery ................ 84% ─────────────────────
        let mac = store.mac
        addRow(BatteryRowView(header: "Battery", percent: mac?.percent))
        if let mac {
            addInfo("Power Source: \(mac.powerSource ?? "Unknown")")
            if mac.fullyCharged {
                addInfo("Fully Charged")
            } else if let time = mac.timeRemaining {
                addInfo(time)
            } else if mac.isCharging {
                addInfo("Charging")
            }
            if let health = store.health {
                var parts: [String] = []
                if let condition = health.condition { parts.append(condition) }
                if let cycles = health.cycleCount { parts.append("\(cycles) cycles") }
                if !parts.isEmpty {
                    let row = InfoRowView(text: "Health: " + parts.joined(separator: " · "))
                    if let capacity = health.maxCapacityPercent {
                        row.toolTip = "Maximum capacity: \(capacity)% of design"
                    }
                    addRow(row)
                }
            }
        }
        menu.addItem(.separator())

        // ── Connected devices ────────────────────────────────────────
        if store.devices.isEmpty {
            addInfo(store.lastUpdated == nil ? "Scanning for devices…" : "No devices found")
        } else {
            for device in store.devices {
                addRow(BatteryRowView(icon: device.kind.symbolName,
                                      title: device.name,
                                      percent: device.percent,
                                      charging: device.isCharging,
                                      detail: device.detail))
                for component in device.components {
                    addRow(BatteryRowView(title: component.label,
                                          percent: component.percent,
                                          isComponent: true))
                }
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

        let quit = NSMenuItem(title: "Quit Batteries", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
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
            let hint = NSMenuItem(title: "Enable iPhone & iPad Battery Levels…",
                                  action: #selector(showIOSHelp), keyEquivalent: "")
            hint.target = self
            prefsMenu.addItem(hint)
        }

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
        store.refresh()
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
        alert.messageText = "iPhone & iPad battery levels"
        alert.informativeText = """
        To show iPhone/iPad battery percentages, install libimobiledevice:

            brew install libimobiledevice

        Then connect your device once via USB and tap "Trust". For Wi-Fi, \
        also enable "Show this iPhone when on Wi-Fi" in Finder. The device \
        will appear here as long as it's on the same network.
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
