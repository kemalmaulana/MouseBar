import Foundation
import MouseLogi

// logiprobe    print the Logitech library version, every paired device, and for each online
//              device its DPI / report-rate settings and battery.
//
// Read-only: it never calls setDPI or setReportRate.

func describe(_ battery: LogiBattery?) -> String {
    guard let battery else { return "unreachable" }
    return "\(battery.percent)%\(battery.charging ? " charging" : "")"
}

func describe(_ values: [Int], unit: String) -> String {
    guard let low = values.min(), let high = values.max() else { return "none" }
    return "\(values.count) values, \(low)\(unit) to \(high)\(unit)"
}

func hex(_ value: Int) -> String {
    "0x" + String(value, radix: 16, uppercase: true)
}

do {
    let version = try await LogiFFI.version()
    print("mousebar-logi \(version.crate), OpenLogi \(version.openlogiRev)")

    let devices = try await LogiFFI.enumerate()
    print("\(devices.count) device(s)")

    for (index, device) in devices.enumerated() {
        print("[\(index)] \(device.codename ?? "unknown") kind=\(device.kind) online=\(device.online)"
            + " wpid=\(device.wpid.map(hex) ?? "nil") slot=\(device.slot)"
            + " receiver=\"\(device.receiverName)\" pid=\(hex(device.receiverProductID))")
        print("    route=\(device.route)")
        print("    enumerate battery: \(describe(device.battery))")
        guard device.online else { continue }

        let settings = try await LogiFFI.readSettings(route: device.route)
        if let dpi = settings.dpi {
            print("    dpi: \(dpi.current) (\(describe(dpi.supported, unit: "")))")
        } else {
            print("    dpi: not adjustable")
        }
        if let rate = settings.reportRate {
            print("    report rate: \(rate.currentMs) ms (supported: \(rate.supportedMs.map(String.init).joined(separator: ", ")) ms)")
        } else {
            print("    report rate: not adjustable")
        }
        let battery = try await LogiFFI.readBattery(route: device.route)
        print("    battery: \(describe(battery))")
    }
} catch {
    FileHandle.standardError.write(Data("logiprobe: \(error)\n".utf8))
    exit(1)
}
