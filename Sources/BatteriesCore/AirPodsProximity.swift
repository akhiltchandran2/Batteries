import Foundation

/// Battery + charging state decoded from an AirPods BLE proximity broadcast.
public struct AirPodsBattery: Equatable {
    public let left: Int?        // nil = pod not in case / disconnected
    public let right: Int?
    public let caseLevel: Int?
    public let leftCharging: Bool
    public let rightCharging: Bool
    public let caseCharging: Bool
    /// Apple model identifier (e.g. 0x2019 = AirPods 4), from the broadcast —
    /// the device name doesn't include the model, so this is how we pick art.
    public let model: UInt16

    /// The lowest present pod level — a reasonable single number for a menu row.
    public var minPod: Int? { [left, right].compactMap { $0 }.min() }
}

/// Decodes Apple's reverse-engineered "proximity pairing" advertisement
/// (manufacturer-data type 0x07), which AirPods broadcast when the case lid is
/// opened. The battery nibbles were validated against a real device reading
/// 80/80/80. This is undocumented and can change with firmware, so the decoder
/// is defensive and returns nil on anything unexpected.
public enum AirPodsProximity {
    /// `data` is the raw Bluetooth manufacturer data including the little-endian
    /// Apple company id (4C 00). Returns nil if it isn't a proximity message.
    public static func decode(manufacturerData data: Data) -> AirPodsBattery? {
        let bytes = [UInt8](data)
        // 4C 00 07 <len> … need at least through the case-battery byte (index 9).
        guard bytes.count >= 10,
              bytes[0] == 0x4C, bytes[1] == 0x00, bytes[2] == 0x07 else {
            return nil
        }

        // bytes[5..6] carry the Apple model identifier, high byte last
        // (0x20 0x19 -> 0x2019 = AirPods 4).
        let model = (UInt16(bytes[6]) << 8) | UInt16(bytes[5])

        // bytes[7] status: bit 1 of its high nibble says which pod is "primary",
        // i.e. whether the left/right nibbles are flipped.
        let flipped = ((bytes[7] >> 4) & 0x02) == 0

        let pods = bytes[8]                 // high nibble = one pod, low = the other
        let caseByte = bytes[9]             // high nibble = charging bits, low = case
        let podHigh = Int(pods >> 4)
        let podLow  = Int(pods & 0x0F)
        let leftNibble  = flipped ? podHigh : podLow
        let rightNibble = flipped ? podLow  : podHigh
        let caseNibble  = Int(caseByte & 0x0F)
        let chargeBits  = caseByte >> 4

        func level(_ nibble: Int) -> Int? {
            nibble == 15 ? nil : min(nibble, 10) * 10   // 0x0F = absent; else nibble×10
        }

        return AirPodsBattery(
            left: level(leftNibble),
            right: level(rightNibble),
            caseLevel: level(caseNibble),
            // Charging nibble: bit0 right pod, bit1 left pod, bit2 case.
            leftCharging: (chargeBits & 0x02) != 0,
            rightCharging: (chargeBits & 0x01) != 0,
            caseCharging: (chargeBits & 0x04) != 0,
            model: model
        )
    }
}
