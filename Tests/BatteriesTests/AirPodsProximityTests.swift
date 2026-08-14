import XCTest
@testable import BatteriesCore

final class AirPodsProximityTests: XCTestCase {
    private func data(_ hex: String) -> Data {
        var bytes = [UInt8]()
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            bytes.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        return Data(bytes)
    }

    func testDecode_realPacket_80_80_80() {
        // Captured live; the device reported 80% / 80% / 80%.
        let packet = "4c0007190119201588b852000404d0d0520ba17e4c9f6c08117091d63c"
        let b = AirPodsProximity.decode(manufacturerData: data(packet))
        XCTAssertNotNil(b)
        XCTAssertEqual(b?.left, 80)
        XCTAssertEqual(b?.right, 80)
        XCTAssertEqual(b?.caseLevel, 80)
        XCTAssertEqual(b?.model, 0x2019)   // AirPods 4
    }

    func testDecode_rejectsNonProximity() {
        // type 0x10 (nearby), not proximity — must be ignored.
        XCTAssertNil(AirPodsProximity.decode(manufacturerData: data("4c001007211fe4aa1bfe38")))
        // too short
        XCTAssertNil(AirPodsProximity.decode(manufacturerData: data("4c0007")))
        // not Apple
        XCTAssertNil(AirPodsProximity.decode(manufacturerData: data("00000719011920")))
    }

    func testDecode_absentNibbleMapsToNil() {
        // 0x0F in a battery nibble means "absent" and must decode to nil.
        // Take the real packet and force the case nibble (low nibble of byte 9)
        // to 0x0F: byte 9 was 0xb8 -> 0xbf.
        let packet = "4c0007190119201588bf52000404d0d0520ba17e4c9f6c08117091d63c"
        let b = AirPodsProximity.decode(manufacturerData: data(packet))
        XCTAssertNotNil(b)
        XCTAssertEqual(b?.left, 80)
        XCTAssertEqual(b?.right, 80)
        XCTAssertNil(b?.caseLevel)   // 0x0F -> absent
    }
}
