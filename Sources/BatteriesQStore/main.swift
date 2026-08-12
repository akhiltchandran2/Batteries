import AppKit
import BatteriesCore
import Sparkle

let app = NSApplication.shared
let delegate = AppDelegate()

// Held here at top level so it lives for the app's whole run — main.swift's
// top-level scope stays active for as long as app.run() is blocking below.
let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
)

delegate.onLaunch = { statusController in
    let checkForUpdatesItem = NSMenuItem(
        title: "Check for Updates…",
        action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
        keyEquivalent: ""
    )
    checkForUpdatesItem.target = updaterController
    statusController.extraSettingsItems = [checkForUpdatesItem]
}

app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
