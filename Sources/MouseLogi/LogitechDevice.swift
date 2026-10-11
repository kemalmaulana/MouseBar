import MouseCore

/// One paired Logitech mouse, driven through the Rust library by its route.
public actor LogitechDevice: MouseDriver {
    private let route: String
    private let supportedDPI: [Int]
    /// Supported report intervals in milliseconds.
    private let supportedIntervals: [Int]

    public init(route: String, settings: LogiSettings) {
        self.route = route
        supportedDPI = (settings.dpi?.supported ?? []).sorted()
        supportedIntervals = settings.reportRate?.supportedMs ?? []
    }

    public func readBattery() async throws -> BatteryReading? {
        // An unreachable mouse is asleep, not broken, so a failed read is "no reading".
        guard let battery = try? await LogiFFI.readBattery(route: route) else { return nil }
        return BatteryReading(level: battery.percent, isCharging: battery.charging)
    }

    public func readSettings() async -> [String: SettingValue] {
        guard let settings = try? await LogiFFI.readSettings(route: route) else { return [:] }
        var values: [String: SettingValue] = [:]
        if let dpi = settings.dpi {
            values["dpi"] = .int(dpi.current)
        }
        if let rate = settings.reportRate, let hz = LogitechFamily.hertz(forIntervalMs: rate.currentMs) {
            values["polling_rate"] = .choice(String(hz))
        }
        return values
    }

    public func apply(_ key: String, _ value: SettingValue) async throws {
        switch key {
        case "dpi":
            guard case .int(let requested) = value else {
                throw MouseCoreError.valueMismatch(setting: key, expected: "range")
            }
            guard let snapped = supportedDPI.min(by: { abs($0 - requested) < abs($1 - requested) }) else {
                throw MouseCoreError.unknownSetting(key)
            }
            try await LogiFFI.setDPI(route: route, dpi: snapped)
            let settings = try await LogiFFI.readSettings(route: route)
            guard let actual = settings.dpi?.current else {
                throw MouseCoreError.invalidValue("The mouse did not report its DPI after the change.")
            }
            if actual != snapped {
                throw MouseCoreError.invalidValue(
                    "The mouse kept \(actual) DPI instead of \(snapped). Its onboard profile may be in control."
                )
            }
        case "polling_rate":
            guard case .choice(let text) = value else {
                throw MouseCoreError.valueMismatch(setting: key, expected: "choice")
            }
            guard !supportedIntervals.isEmpty else { throw MouseCoreError.unknownSetting(key) }
            guard let hz = Int(text),
                  let interval = supportedIntervals.first(where: { LogitechFamily.hertz(forIntervalMs: $0) == hz })
            else {
                throw MouseCoreError.invalidValue("\(text) Hz is not a polling rate this mouse supports.")
            }
            try await LogiFFI.setReportRate(route: route, intervalMs: interval)
            let settings = try await LogiFFI.readSettings(route: route)
            guard let actualMs = settings.reportRate?.currentMs else {
                throw MouseCoreError.invalidValue("The mouse did not report its polling rate after the change.")
            }
            if actualMs != interval {
                let actual = LogitechFamily.hertz(forIntervalMs: actualMs).map(String.init) ?? "\(actualMs) ms"
                throw MouseCoreError.invalidValue(
                    "The mouse kept \(actual) Hz instead of \(hz). Its onboard profile may be in control."
                )
            }
        default:
            throw MouseCoreError.unknownSetting(key)
        }
    }

    /// Nothing to save: DPI and report rate are written live.
    public func save() async throws {}

    public func rawBatteryQuery() async throws -> [UInt8]? { nil }

    public func close() async {}
}
