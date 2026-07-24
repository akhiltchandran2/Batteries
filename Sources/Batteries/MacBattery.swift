import Foundation
import IOKit.ps

enum MacBattery {
    static func read() -> DeviceBattery? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }

        for source in list {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard let type = info[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType else { continue }

            let current = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = info[kIOPSMaxCapacityKey] as? Int ?? 100
            let percent = max > 0 ? Int(round(Double(current) * 100.0 / Double(max))) : current

            let state = info[kIOPSPowerSourceStateKey] as? String
            let powerSource = (state == kIOPSACPowerValue) ? "Power Adapter" : "Battery"
            let charging = info[kIOPSIsChargingKey] as? Bool ?? false
            let charged = info[kIOPSIsChargedKey] as? Bool ?? (percent >= 100 && state == kIOPSACPowerValue)

            // Time estimates are in minutes; -1 while macOS is still calculating.
            var timeRemaining: String?
            if charging, let minutes = info[kIOPSTimeToFullChargeKey] as? Int, minutes > 0 {
                timeRemaining = "\(formatMinutes(minutes)) until fully charged"
            } else if state == kIOPSBatteryPowerValue,
                      let minutes = info[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
                timeRemaining = "\(formatMinutes(minutes)) remaining"
            }

            return DeviceBattery(
                id: "internal-battery",
                name: Host.current().localizedName ?? "This Mac",
                kind: .mac,
                percent: percent,
                isCharging: charging,
                powerSource: powerSource,
                fullyCharged: charged,
                timeRemaining: timeRemaining
            )
        }
        return nil
    }

    private static func formatMinutes(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }
}
