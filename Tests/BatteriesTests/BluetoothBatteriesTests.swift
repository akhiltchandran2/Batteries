import XCTest
@testable import Batteries

final class BluetoothBatteriesTests: XCTestCase {
    func testParse_airPodsWithLeftRightCase() {
        let props: [String: Any] = [
            "device_batteryLevelLeft": "80%",
            "device_batteryLevelRight": "78%",
            "device_batteryLevelCase": "60%",
            "device_minorType": "Headphones",
            "device_address": "AA:BB:CC:DD:EE:FF",
        ]
        let device = BluetoothBatteries.parse(name: "John's AirPods Pro", props: props)
        XCTAssertNotNil(device)
        XCTAssertEqual(device?.percent, 78) // min(left, right)
        XCTAssertEqual(device?.kind, .headphones)
        XCTAssertEqual(device?.components.count, 3)
        XCTAssertTrue(device?.components.contains { $0.label == "Left" && $0.percent == 80 } ?? false)
        XCTAssertTrue(device?.components.contains { $0.label == "Case" && $0.percent == 60 } ?? false)
    }

    func testParse_mainLevelOnly_noComponents() {
        // A single main level shouldn't produce a components list — that's
        // reserved for devices with more than one reported cell.
        let props: [String: Any] = [
            "device_batteryLevelMain": "45%",
            "device_minorType": "Mouse",
            "device_address": "11:22:33:44:55:66",
        ]
        let device = BluetoothBatteries.parse(name: "MX Master 3S", props: props)
        XCTAssertEqual(device?.percent, 45)
        XCTAssertEqual(device?.kind, .mouse)
        XCTAssertTrue(device?.components.isEmpty ?? false)
    }

    func testParse_noBatteryKeys_stillReturnsDeviceWithNilPercent() {
        // Connected accessories that don't report a level are still listed,
        // just with percent == nil (rendered as "—" in the menu).
        let props: [String: Any] = [
            "device_minorType": "Mouse",
            "device_address": "11:22:33:44:55:66",
        ]
        let device = BluetoothBatteries.parse(name: "Some Old Mouse", props: props)
        XCTAssertNotNil(device)
        XCTAssertNil(device?.percent)
    }

    func testParse_integerBatteryLevel() {
        // system_profiler sometimes reports levels as raw Int rather than
        // a "NN%" string, depending on macOS version.
        let props: [String: Any] = [
            "device_batteryLevelMain": 90,
            "device_address": "11:22:33:44:55:66",
        ]
        let device = BluetoothBatteries.parse(name: "Magic Keyboard", props: props)
        XCTAssertEqual(device?.percent, 90)
        XCTAssertEqual(device?.kind, .keyboard)
    }

    func testParse_kindDetection_iPhoneOverBluetoothPairing() {
        let props: [String: Any] = ["device_address": "11:22:33:44:55:66"]
        let device = BluetoothBatteries.parse(name: "John's iPhone", props: props)
        XCTAssertEqual(device?.kind, .iphone)
    }

    // MARK: - isContinuityDevice(_:)

    func testIsContinuityDevice_includesIPhoneIPadWatch() {
        XCTAssertTrue(BluetoothBatteries.isContinuityDevice(.iphone))
        XCTAssertTrue(BluetoothBatteries.isContinuityDevice(.ipad))
        XCTAssertTrue(BluetoothBatteries.isContinuityDevice(.watch))
    }

    func testIsContinuityDevice_excludesOrdinaryAccessories() {
        // Not-connected accessories (a keyboard tried once, someone else's
        // earbuds) shouldn't clutter the menu the way a not-connected
        // iPhone/iPad/Watch is worth surfacing.
        XCTAssertFalse(BluetoothBatteries.isContinuityDevice(.headphones))
        XCTAssertFalse(BluetoothBatteries.isContinuityDevice(.keyboard))
        XCTAssertFalse(BluetoothBatteries.isContinuityDevice(.mouse))
        XCTAssertFalse(BluetoothBatteries.isContinuityDevice(.speaker))
        XCTAssertFalse(BluetoothBatteries.isContinuityDevice(.other))
    }
}
