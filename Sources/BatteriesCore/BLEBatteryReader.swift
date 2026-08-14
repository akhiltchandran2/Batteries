import Foundation
import CoreBluetooth

/// Reads battery levels for BLE accessories (mice, keyboards, headphones) that
/// expose the standard GATT Battery Service, which macOS does NOT surface
/// through system_profiler or IORegistry — an MX Master shows "—" everywhere
/// else but reports 35% right here. Fills the gap the way AirBuddy does, using
/// the *standard* service (0x180F / 0x2A19), not reverse-engineered data.
///
/// Requires Bluetooth permission (the bundle declares
/// NSBluetoothAlwaysUsageDescription). CoreBluetooth connections are per-app,
/// so attaching a short GATT session to read the level does not disturb the
/// device's system-level HID connection.
final class BLEBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BLEBatteryReader()

    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")
    /// Don't reconnect for a fresh read more often than this — battery moves
    /// slowly and each read is a connect/discover/read round-trip.
    private static let minInterval: TimeInterval = 150

    private let queue = DispatchQueue(label: "com.powerdeck.ble")
    private var central: CBCentralManager?
    private var inFlight: Set<CBPeripheral> = []
    private var lastRefresh: Date?

    private let lock = NSLock()
    private var levelsByName: [String: Int] = [:]

    private override init() { super.init() }

    /// Latest battery percent read for a device name, or nil if unknown.
    /// Thread-safe; called from the battery refresh queue.
    func battery(forName name: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return levelsByName[name]
    }

    /// Kicks a throttled read of all system-connected BLE battery peripherals.
    /// Non-blocking; results land asynchronously and are read via battery(forName:)
    /// on subsequent refreshes.
    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            // Creating the central here (on our queue) triggers the one-time
            // Bluetooth permission prompt the first time.
            if self.central == nil {
                self.central = CBCentralManager(
                    delegate: self, queue: self.queue,
                    options: [CBCentralManagerOptionShowPowerAlertKey: false])
                return // wait for poweredOn; the state callback starts the read
            }
            if let last = self.lastRefresh, Date().timeIntervalSince(last) < Self.minInterval {
                return
            }
            self.readConnected()
        }
    }

    private func readConnected() {
        guard let central, central.state == .poweredOn else { return }
        lastRefresh = Date()
        let peripherals = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        Log.devices.debug("BLE battery: \(peripherals.count) connected peripheral(s) with a battery service")
        for peripheral in peripherals {
            peripheral.delegate = self
            inFlight.insert(peripheral)
            central.connect(peripheral, options: nil)
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            readConnected()
        } else {
            Log.devices.debug("BLE battery: central state \(central.state.rawValue) (not poweredOn)")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        inFlight.remove(peripheral)
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == Self.batteryService {
            peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.batteryLevel {
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let name = peripheral.name, let byte = characteristic.value?.first {
            lock.lock(); levelsByName[name] = Int(byte); lock.unlock()
            Log.devices.debug("BLE battery: \(name, privacy: .public) = \(byte)%")
        }
        // Drop our GATT session — per-app, so the HID connection is unaffected.
        inFlight.remove(peripheral)
        central?.cancelPeripheralConnection(peripheral)
    }
}
