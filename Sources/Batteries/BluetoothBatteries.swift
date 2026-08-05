import Foundation

/// Reads battery levels of connected Bluetooth devices (AirPods, Magic
/// Keyboard/Mouse/Trackpad, third-party headphones, controllers…) from
/// `system_profiler SPBluetoothDataType -json`.
enum BluetoothBatteries {
    static func read() -> [DeviceBattery] {
        guard let data = Shell.run("/usr/sbin/system_profiler",
                                   ["SPBluetoothDataType", "-json"],
                                   timeout: 20) else {
            Log.devices.debug("system_profiler SPBluetoothDataType produced no output")
            return []
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else {
            Log.devices.error("system_profiler SPBluetoothDataType output wasn't the expected JSON shape")
            return []
        }

        var devices: [DeviceBattery] = []
        for section in sections {
            if let connected = section["device_connected"] as? [[String: Any]] {
                for entry in connected {
                    for (name, value) in entry {
                        guard let props = value as? [String: Any] else { continue }
                        if let device = parse(name: name, props: props) {
                            devices.append(device)
                        }
                    }
                }
            }

            // iPhone/iPad/Watch are worth showing even when not actively
            // Bluetooth-connected: Continuity battery sharing only reports
            // a level intermittently (device unlocked and nearby, both on
            // the same Apple ID, Bluetooth+Wi-Fi on), so the device should
            // still appear — as "—" — rather than vanish, matching what
            // System Settings' Bluetooth pane shows. Other not-connected
            // accessories (a keyboard tried once, someone else's earbuds)
            // are deliberately excluded — showing every device ever paired
            // would clutter the menu with things that aren't "yours".
            if let notConnected = section["device_not_connected"] as? [[String: Any]] {
                for entry in notConnected {
                    for (name, value) in entry {
                        guard let props = value as? [String: Any] else { continue }
                        if let device = parse(name: name, props: props),
                           Self.isContinuityDevice(device.kind) {
                            devices.append(device)
                        }
                    }
                }
            }
        }
        return devices
    }

    /// Internal (not private) so tests can exercise it directly.
    static func isContinuityDevice(_ kind: DeviceBattery.Kind) -> Bool {
        kind == .iphone || kind == .ipad || kind == .watch
    }

    /// Internal (not private) so tests can exercise it directly with
    /// fixture props instead of mocking system_profiler.
    static func parse(name: String, props: [String: Any]) -> DeviceBattery? {
        let main = percentValue(props["device_batteryLevelMain"])
        let left = percentValue(props["device_batteryLevelLeft"])
        let right = percentValue(props["device_batteryLevelRight"])
        let caseLevel = percentValue(props["device_batteryLevelCase"])

        let budsMin = [left, right].compactMap { $0 }.min()
        // Connected devices without a reported level are still listed ("—").
        let percent = main ?? budsMin ?? caseLevel

        var components: [DeviceBattery.Component] = []
        if let left { components.append(.init(label: "Left", percent: left)) }
        if let right { components.append(.init(label: "Right", percent: right)) }
        if let caseLevel { components.append(.init(label: "Case", percent: caseLevel)) }

        let address = props["device_address"] as? String ?? name
        return DeviceBattery(
            id: "bt-\(address)",
            name: name,
            kind: kind(name: name, minorType: props["device_minorType"] as? String),
            percent: percent,
            // Only expose components when there's more than the single main
            // level, i.e. earbuds with separate Left/Right/Case cells.
            components: components.count > 1 ? components : []
        )
    }

    private static func percentValue(_ raw: Any?) -> Int? {
        if let number = raw as? Int { return number }
        guard let text = raw as? String else { return nil }
        let digits = text.filter { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    private static func kind(name: String, minorType: String?) -> DeviceBattery.Kind {
        let haystack = ((minorType ?? "") + " " + name).lowercased()
        if haystack.contains("iphone") || haystack.contains("smartphone")
            || haystack.contains("cellphone") {
            return .iphone
        }
        if haystack.contains("ipad") || haystack.contains("tablet") { return .ipad }
        if haystack.contains("watch") { return .watch }
        if haystack.contains("airpods") || haystack.contains("headphone")
            || haystack.contains("headset") || haystack.contains("earbud") {
            return .headphones
        }
        if haystack.contains("keyboard") { return .keyboard }
        if haystack.contains("mouse") { return .mouse }
        if haystack.contains("trackpad") { return .trackpad }
        if haystack.contains("speaker") { return .speaker }
        if haystack.contains("gamepad") || haystack.contains("controller") { return .gamepad }
        return .other
    }
}
