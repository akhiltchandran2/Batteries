import XCTest
@testable import Batteries

final class IOSDevicesTests: XCTestCase {
    // MARK: - parseUDID(from:)

    func testParseUDID_usbSuffix() {
        XCTAssertEqual(IOSDevices.parseUDID(from: "00008150-000955203C00C01C (USB)"),
                       "00008150-000955203C00C01C")
    }

    func testParseUDID_networkSuffix() {
        XCTAssertEqual(IOSDevices.parseUDID(from: "00008030-001A6D940A41802E (Network)"),
                       "00008030-001A6D940A41802E")
    }

    func testParseUDID_noSuffix() {
        // Some idevice_id versions print bare UDIDs with no connection suffix.
        XCTAssertEqual(IOSDevices.parseUDID(from: "00008030-001A6D940A41802E"),
                       "00008030-001A6D940A41802E")
    }

    func testParseUDID_emptyLine() {
        XCTAssertNil(IOSDevices.parseUDID(from: ""))
    }

    // MARK: - parseInfoOutput(_:)

    func testParseInfoOutput_simpleKeyValues() {
        let output = """
        BatteryCurrentCapacity: 81
        BatteryIsCharging: true
        DeviceName: iPhone 11
        """
        let result = IOSDevices.parseInfoOutput(output)
        XCTAssertEqual(result["BatteryCurrentCapacity"], "81")
        XCTAssertEqual(result["BatteryIsCharging"], "true")
        XCTAssertEqual(result["DeviceName"], "iPhone 11")
    }

    func testParseInfoOutput_valueContainingColons() {
        // A MAC address value has colons of its own — only the first colon
        // should split key from value.
        let output = "BluetoothAddress: 74:14:d0:09:c7:89"
        let result = IOSDevices.parseInfoOutput(output)
        XCTAssertEqual(result["BluetoothAddress"], "74:14:d0:09:c7:89")
    }

    func testParseInfoOutput_skipsLinesWithoutColon() {
        let output = """
        DeviceName: iPhone 11
        not a key value line
        DeviceClass: iPhone
        """
        let result = IOSDevices.parseInfoOutput(output)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result["DeviceName"], "iPhone 11")
        XCTAssertEqual(result["DeviceClass"], "iPhone")
    }

    func testParseInfoOutput_emptyString() {
        XCTAssertTrue(IOSDevices.parseInfoOutput("").isEmpty)
    }
}
