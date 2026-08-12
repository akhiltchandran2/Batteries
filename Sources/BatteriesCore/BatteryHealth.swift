import Foundation
import IOKit
import IOKit.ps

enum BatteryHealth {
    static func read() -> BatteryHealthInfo? {
        var cycles: Int?
        var maxCapacity: Int?

        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            func prop(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString,
                                                kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            cycles = prop("CycleCount") as? Int
            if let design = prop("DesignCapacity") as? Int, design > 0 {
                let raw = (prop("AppleRawMaxCapacity") as? Int)
                    ?? (prop("NominalChargeCapacity") as? Int)
                if let raw {
                    maxCapacity = min(100, Int(round(Double(raw) * 100.0 / Double(design))))
                }
            }
        }

        // Condition string comes from the power-source description.
        var condition: String?
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let info = IOPSGetPowerSourceDescription(snapshot, source)?
                    .takeUnretainedValue() as? [String: Any],
                      let health = info[kIOPSBatteryHealthKey] as? String else { continue }
                // System Settings calls "Good" batteries "Normal".
                condition = (health == "Good") ? "Normal" : health
            }
        }

        if cycles == nil && maxCapacity == nil && condition == nil { return nil }
        return BatteryHealthInfo(condition: condition, cycleCount: cycles,
                                 maxCapacityPercent: maxCapacity)
    }
}
