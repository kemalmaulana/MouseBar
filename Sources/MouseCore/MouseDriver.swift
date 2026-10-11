/// What the rest of MouseCore needs from a connected mouse, whichever backend talks to the hardware.
public protocol MouseDriver: Actor {
    func apply(_ key: String, _ value: SettingValue) async throws
    func save() async throws
    func readBattery() async throws -> BatteryReading?
    func rawBatteryQuery() async throws -> [UInt8]?
    /// Current values the mouse can report itself; empty when it can't.
    func readSettings() async -> [String: SettingValue]
    func close() async
}

extension MouseDriver {
    public func readSettings() async -> [String: SettingValue] { [:] }
}

extension MouseDevice: MouseDriver {}
