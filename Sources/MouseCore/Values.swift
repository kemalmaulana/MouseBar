import Foundation

public enum MouseCoreError: Error, Equatable, Sendable {
    case overflow
    case unknownSetting(String)
    case unsupportedValueType(String)
    case valueMismatch(setting: String, expected: String)
    case invalidValue(String)
    case noPrimaryClick
}

enum Bytes {
    /// `value` as `length` little-endian bytes. Mirrors rivalcfg `uint_to_little_endian_bytearray`.
    static func littleEndian(_ value: Int, length: Int) throws -> [UInt8] {
        guard value >= 0, length >= 1, length <= 8 else { throw MouseCoreError.overflow }
        if length < 8 && value > (1 << (8 * length)) - 1 { throw MouseCoreError.overflow }
        return (0..<length).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }

    static func u8(_ ints: [Int]) -> [UInt8] {
        ints.map { UInt8(truncatingIfNeeded: $0) }
    }
}

public struct RGBColor: Equatable, Sendable, Codable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    static let named: [String: RGBColor] = [
        "white": RGBColor(r: 0xFF, g: 0xFF, b: 0xFF),
        "silver": RGBColor(r: 0xC0, g: 0xC0, b: 0xC0),
        "gray": RGBColor(r: 0x80, g: 0x80, b: 0x80),
        "black": RGBColor(r: 0x00, g: 0x00, b: 0x00),
        "red": RGBColor(r: 0xFF, g: 0x00, b: 0x00),
        "maroon": RGBColor(r: 0x80, g: 0x00, b: 0x00),
        "yellow": RGBColor(r: 0xFF, g: 0xFF, b: 0x00),
        "olive": RGBColor(r: 0x80, g: 0x80, b: 0x00),
        "lime": RGBColor(r: 0x00, g: 0xFF, b: 0x00),
        "green": RGBColor(r: 0x00, g: 0x80, b: 0x00),
        "aqua": RGBColor(r: 0x00, g: 0xFF, b: 0xFF),
        "teal": RGBColor(r: 0x00, g: 0x80, b: 0x80),
        "blue": RGBColor(r: 0x00, g: 0x00, b: 0xFF),
        "navy": RGBColor(r: 0x00, g: 0x00, b: 0x80),
        "fuchsia": RGBColor(r: 0xFF, g: 0x00, b: 0xFF),
        "purple": RGBColor(r: 0x80, g: 0x00, b: 0x80),
    ]

    /// Accepts rivalcfg color strings: a named color, `rgb`, `#rgb`, `rrggbb`, `#rrggbb`.
    public init?(parsing text: String) {
        let lower = text.lowercased()
        if let color = Self.named[lower] {
            self = color
            return
        }
        var digits = lower.hasPrefix("#") ? String(lower.dropFirst()) : lower
        guard digits.count == 3 || digits.count == 6,
              digits.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) })
        else { return nil }
        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard let value = UInt32(digits, radix: 16) else { return nil }
        self.init(r: UInt8((value >> 16) & 0xFF), g: UInt8((value >> 8) & 0xFF), b: UInt8(value & 0xFF))
    }

    public var hexString: String {
        String(format: "%02x%02x%02x", r, g, b)
    }
}

public struct ButtonMapping: Equatable, Sendable, Codable {
    /// Lowercased button name -> lowercased action token. `"default"` means the factory action.
    public var assignments: [String: String]

    public init(assignments: [String: String] = [:]) {
        self.assignments = Dictionary(
            assignments.map { ($0.key.lowercased(), $0.value.lowercased()) },
            uniquingKeysWith: { _, latest in latest }
        )
    }
}

public enum SettingValue: Equatable, Sendable, Codable {
    case int(Int)
    case choice(String)
    case dpiPresets(presets: [Int], selected: Int?)
    case color(RGBColor)
    case buttons(ButtonMapping)

    private enum CodingKeys: String, CodingKey {
        case type, value, presets, selected, r, g, b, assignments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "int":
            self = .int(try c.decode(Int.self, forKey: .value))
        case "choice":
            self = .choice(try c.decode(String.self, forKey: .value))
        case "dpi":
            self = .dpiPresets(
                presets: try c.decode([Int].self, forKey: .presets),
                selected: try c.decodeIfPresent(Int.self, forKey: .selected)
            )
        case "color":
            self = .color(RGBColor(
                r: try c.decode(UInt8.self, forKey: .r),
                g: try c.decode(UInt8.self, forKey: .g),
                b: try c.decode(UInt8.self, forKey: .b)
            ))
        case "buttons":
            self = .buttons(ButtonMapping(assignments: try c.decode([String: String].self, forKey: .assignments)))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "unknown setting value type"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .int(let v):
            try c.encode("int", forKey: .type)
            try c.encode(v, forKey: .value)
        case .choice(let v):
            try c.encode("choice", forKey: .type)
            try c.encode(v, forKey: .value)
        case .dpiPresets(let presets, let selected):
            try c.encode("dpi", forKey: .type)
            try c.encode(presets, forKey: .presets)
            try c.encode(selected, forKey: .selected)
        case .color(let color):
            try c.encode("color", forKey: .type)
            try c.encode(color.r, forKey: .r)
            try c.encode(color.g, forKey: .g)
            try c.encode(color.b, forKey: .b)
        case .buttons(let mapping):
            try c.encode("buttons", forKey: .type)
            try c.encode(mapping.assignments, forKey: .assignments)
        }
    }
}
