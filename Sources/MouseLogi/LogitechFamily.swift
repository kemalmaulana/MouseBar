import MouseCore

/// Builds the settings family the app shows for a Logitech mouse, from what the mouse reports it supports.
/// Neither setting is kept by the mouse itself between sessions in a way the app can save, so both are
/// `persistsOnDevice == false` and the app re-sends its remembered values.
public enum LogitechFamily {
    public static func make(device: LogiDevice, settings: LogiSettings) -> (DeviceFamily, DeviceModel) {
        let mouse = if let wpid = device.wpid {
            "logitech-" + hex4(wpid)
        } else {
            "logitech-slot\(device.slot)"
        }
        let model = DeviceModel(
            name: LogitechNames.name(wpid: device.wpid, codename: device.codename),
            mouse: mouse,
            vendorId: 0x046D,
            productId: device.receiverProductID,
            endpoint: 0,
            isWireless: true
        )
        var specs: [SettingSpec] = []
        if let dpi = settings.dpi {
            specs.append(dpiSpec(dpi))
        }
        if let rate = settings.reportRate {
            specs.append(pollingRateSpec(rate))
        }
        let family = DeviceFamily(
            id: model.mouse, name: model.name, models: [model], settings: specs,
            battery: nil, saveCommand: nil
        )
        return (family, model)
    }

    /// Polling rate in Hz for a report interval; nil for an interval that is not positive.
    static func hertz(forIntervalMs ms: Int) -> Int? {
        ms > 0 ? 1000 / ms : nil
    }

    private static func hex4(_ value: Int) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }

    private static func dpiSpec(_ dpi: LogiDPI) -> SettingSpec {
        let supported = Array(Set(dpi.supported)).sorted()
        let low = supported.first ?? dpi.current
        let high = supported.last ?? dpi.current
        var step = Int.max
        for (a, b) in zip(supported, supported.dropFirst()) {
            step = min(step, b - a)
        }
        if step == Int.max { step = 1 }
        return SettingSpec(
            key: "dpi",
            label: "DPI",
            description: "Set the sensor resolution (DPI)",
            command: [],
            commandSuffix: [],
            valueType: "range",
            defaultText: String(dpi.current),
            readbackLength: 0,
            packetLength: 0,
            persistsOnDevice: false,
            inputRange: [low, high, max(1, step)]
        )
    }

    private static func pollingRateSpec(_ rate: LogiReportRate) -> SettingSpec {
        var seen = Set<Int>()
        var choices: [ChoiceEntry] = []
        for ms in rate.supportedMs {
            guard let hz = hertz(forIntervalMs: ms), seen.insert(hz).inserted else { continue }
            choices.append(ChoiceEntry(key: String(hz), value: ms))
        }
        choices.sort { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
        return SettingSpec(
            key: "polling_rate",
            label: "Polling rate",
            description: "Set polling rate (Hz)",
            command: [],
            commandSuffix: [],
            valueType: "choice",
            defaultText: hertz(forIntervalMs: rate.currentMs).map(String.init) ?? "",
            readbackLength: 0,
            packetLength: 0,
            persistsOnDevice: false,
            choices: choices
        )
    }
}
