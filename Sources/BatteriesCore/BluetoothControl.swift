import Foundation
import IOBluetooth

/// Connects and disconnects classic Bluetooth devices (AirPods, headphones,
/// Magic mouse/keyboard/trackpad, speakers) via IOBluetooth.
///
/// Requires the app to hold Bluetooth permission — on macOS the first call
/// triggers the system prompt, so the bundle must declare
/// NSBluetoothAlwaysUsageDescription. iPhones/iPads/Watches are BLE/Continuity
/// devices and don't appear here; only classic paired devices are controllable.
public struct ControllableDevice: Equatable {
    public let name: String
    public let address: String
    public let connected: Bool
}

enum BluetoothControl {
    /// Paired classic Bluetooth devices with their current connection state.
    /// Call from the main thread when building the menu (fast, local). The
    /// first call may surface the Bluetooth permission prompt.
    static func pairedDevices() -> [ControllableDevice] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }
        return devices.compactMap { device in
            guard let address = device.addressString, !address.isEmpty else { return nil }
            return ControllableDevice(name: device.name ?? "Unknown Device",
                                      address: address,
                                      connected: device.isConnected())
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Connects a paired device found by name (used by the AirPods pop-up,
    /// which only knows the broadcast name, not the address). No-op if already
    /// connected or not found.
    static func connect(name: String) {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
              let device = devices.first(where: { $0.name == name }) else { return }
        if !device.isConnected() {
            let result = device.openConnection()
            Log.devices.debug("connect by name \(name, privacy: .public): \(result)")
        }
    }

    /// Connects the device if disconnected, or disconnects it if connected.
    /// The open/close calls block briefly, so run off the main thread.
    static func toggle(address: String) {
        guard let device = IOBluetoothDevice(addressString: address) else {
            Log.devices.error("Bluetooth toggle: no device for \(address, privacy: .public)")
            return
        }
        if device.isConnected() {
            let result = device.closeConnection()
            Log.devices.debug("disconnect \(address, privacy: .public): \(result)")
        } else {
            let result = device.openConnection()
            Log.devices.debug("connect \(address, privacy: .public): \(result)")
        }
    }
}
