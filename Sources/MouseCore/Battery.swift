public struct BatteryReading: Equatable, Sendable, Codable {
    public var level: Int
    public var isCharging: Bool

    public init(level: Int, isCharging: Bool) {
        self.level = level
        self.isCharging = isCharging
    }
}

public enum BatteryDecoder {
    /// Decodes the reply to a battery query. `nil` means "unreadable": the caller must not show 0%.
    public static func decode(decoder: String, reply: [UInt8]) -> BatteryReading? {
        switch decoder {
        case "prime_wireless":
            // rivalcfg: charging = bit 7 of reply[1]; level = ((reply[1] & 0x7F) - 1) * 5
            guard reply.count >= 2 else { return nil }
            let raw = Int(reply[1])
            let level = ((raw & 0x7F) - 1) * 5
            guard (0...100).contains(level) else { return nil }
            return BatteryReading(level: level, isCharging: raw & 0x80 != 0)
        default:
            return nil
        }
    }
}
