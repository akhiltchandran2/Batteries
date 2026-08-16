import Foundation
import CoreBluetooth

/// Scans for AirPods proximity broadcasts and fires when the case is opened
/// near the Mac. Opt-in — always-on BLE scanning has a battery cost, so it only
/// runs while enabled (the pop-up and/or continuous-menu-battery preferences —
/// see `Preferences.airPodsScanningEnabled`). Needs Bluetooth permission.
public final class AirPodsMonitor: NSObject, CBCentralManagerDelegate {
    public static let shared = AirPodsMonitor()

    public struct Reading {
        public let name: String
        public let battery: AirPodsBattery
    }

    /// Fired on the main thread when the case opens nearby. One call per open.
    public var onCaseOpen: ((Reading) -> Void)?

    private let queue = DispatchQueue(label: "com.powerdeck.airpods")
    private var central: CBCentralManager?
    private var running = false
    private var lastProximity: Date?
    private var lastPopup: Date?

    private let lock = NSLock()
    private var latestByName: [String: AirPodsBattery] = [:]

    /// Only react to a case that's genuinely next to the Mac (the capture was
    /// -35 dBm right beside it); ignore AirPods across the room.
    private static let nearbyRSSI = -55
    /// A gap this long before a burst of proximity messages marks a new "open".
    private static let openGap: TimeInterval = 8
    /// Don't re-show the pop-up more often than this.
    private static let popupCooldown: TimeInterval = 15

    private override init() { super.init() }

    /// Latest proximity battery for a device name (for the menu), or nil.
    public func battery(forName name: String) -> AirPodsBattery? {
        lock.lock(); defer { lock.unlock() }
        return latestByName[name]
    }

    /// Every AirPods device seen recently, by name — used to show battery in
    /// the menu for a case that's open nearby but not yet Bluetooth-connected
    /// (so wouldn't otherwise appear at all).
    public func allCached() -> [String: AirPodsBattery] {
        lock.lock(); defer { lock.unlock() }
        return latestByName
    }

    public func setEnabled(_ enabled: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            if enabled {
                if self.central == nil {
                    self.central = CBCentralManager(
                        delegate: self, queue: self.queue,
                        options: [CBCentralManagerOptionShowPowerAlertKey: false])
                }
                self.running = true
                self.startScanIfReady()
            } else {
                self.running = false
                self.central?.stopScan()
            }
        }
    }

    private func startScanIfReady() {
        guard running, let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        Log.devices.debug("AirPods monitor: scanning")
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        startScanIfReady()
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let battery = AirPodsProximity.decode(manufacturerData: manufacturer) else {
            return
        }
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "AirPods"

        lock.lock(); latestByName[name] = battery; lock.unlock()

        let now = Date()
        let isNewBurst = lastProximity.map { now.timeIntervalSince($0) > Self.openGap } ?? true
        lastProximity = now
        let onCooldown = lastPopup.map { now.timeIntervalSince($0) < Self.popupCooldown } ?? false

        if isNewBurst, RSSI.intValue >= Self.nearbyRSSI, !onCooldown {
            lastPopup = now
            let reading = Reading(name: name, battery: battery)
            Log.devices.debug("AirPods case opened: \(name, privacy: .public) rssi=\(RSSI.intValue)")
            DispatchQueue.main.async { [weak self] in self?.onCaseOpen?(reading) }
        }
    }
}
