import Foundation

struct DeviceBattery: Codable {
    enum Kind: String, Codable {
        case mac, iphone, ipad, watch, headphones, keyboard, mouse, trackpad, speaker, gamepad, other

        var symbolName: String {
            switch self {
            case .mac: return "laptopcomputer"
            case .iphone: return "iphone"
            case .ipad: return "ipad"
            case .watch: return "applewatch"
            case .headphones: return "headphones"
            case .keyboard: return "keyboard"
            case .mouse: return "magicmouse"
            case .trackpad: return "rectangle.and.hand.point.up.left"
            case .speaker: return "hifispeaker"
            case .gamepad: return "gamecontroller"
            case .other: return "wave.3.right.circle"
            }
        }
    }

    /// Per-component battery level, e.g. AirPods Left / Right / Case.
    struct Component: Codable {
        let label: String
        let percent: Int
    }

    let id: String
    let name: String
    let kind: Kind
    /// nil when the device is connected but doesn't report a battery level.
    let percent: Int?
    var isCharging: Bool = false
    var powerSource: String? = nil
    var fullyCharged: Bool = false
    /// e.g. "33m until fully charged" or "2h 15m remaining"
    var timeRemaining: String? = nil
    var components: [Component] = []
    /// Set when this reading is cached rather than fresh — the device is
    /// present but couldn't be queried right now (e.g. a locked iPhone).
    /// The percent shown is as of this date, not the current moment.
    var staleSince: Date? = nil
    /// Set when the device isn't in the current scan at all but was seen
    /// recently — rendered dimmed instead of silently disappearing.
    var unreachableSince: Date? = nil
}

/// Mac battery health, shown under the header.
struct BatteryHealthInfo {
    let condition: String?          // "Normal", "Fair", …
    let cycleCount: Int?
    let maxCapacityPercent: Int?    // current full-charge capacity vs design
}
