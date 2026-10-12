import MouseCore

/// A Logitech G304 stand-in for `MouseBar --demo`. Never touches the FFI.
public actor SimulatedLogitechDevice: MouseDriver {
    private static let route = "demo-logitech"
    private static let supportedDPI = Array(stride(from: 200, through: 12000, by: 50))
    private static let supportedIntervals = [1, 2, 4, 8]

    private var dpi = 1600
    private var pollingRate = "1000"

    public init() {}

    /// A demo mouse that looks like a connected G304 behind a Lightspeed receiver.
    public static func connectedMouse() -> ConnectedMouse {
        let device = LogiDevice(
            route: route, receiverName: "Demo Lightspeed Receiver", receiverProductID: 0xC53F, slot: 1,
            wpid: 0x4074, codename: "G304", kind: "mouse", online: true,
            battery: LogiBattery(percent: 80, charging: false)
        )
        let settings = LogiSettings(
            dpi: LogiDPI(current: 1600, supported: supportedDPI),
            reportRate: LogiReportRate(currentMs: 1, supportedMs: supportedIntervals)
        )
        let (family, model) = LogitechFamily.make(device: device, settings: settings)
        return ConnectedMouse(hidID: UInt64.max - 1, family: family, model: model, device: SimulatedLogitechDevice())
    }

    public func apply(_ key: String, _ value: SettingValue) async throws {
        switch (key, value) {
        case ("dpi", .int(let requested)):
            dpi = requested
        case ("polling_rate", .choice(let hz)):
            pollingRate = hz
        case ("dpi", _):
            throw MouseCoreError.valueMismatch(setting: key, expected: "range")
        case ("polling_rate", _):
            throw MouseCoreError.valueMismatch(setting: key, expected: "choice")
        default:
            throw MouseCoreError.unknownSetting(key)
        }
    }

    public func save() async throws {}

    public func readBattery() async throws -> BatteryReading? {
        BatteryReading(level: 80, isCharging: false)
    }

    public func rawBatteryQuery() async throws -> [UInt8]? { nil }

    public func readSettings() async -> [String: SettingValue] {
        ["dpi": .int(dpi), "polling_rate": .choice(pollingRate)]
    }

    public func close() async {}
}
