import Foundation

public struct ChoiceEntry: Codable, Sendable, Equatable {
    public var key: String
    public var value: Int
}

public struct ButtonSpec: Codable, Sendable, Equatable {
    public var name: String
    public var id: Int
    public var offset: Int
    public var defaultAction: String
}

public struct SettingSpec: Codable, Sendable, Identifiable, Equatable {
    public var id: String { key }
    public var key: String
    public var label: String
    public var description: String
    public var command: [Int]
    public var commandSuffix: [Int]
    public var valueType: String
    public var defaultText: String
    public var readbackLength: Int
    public var packetLength: Int
    public var persistsOnDevice: Bool
    // range / multidpi_range_choice
    public var inputRange: [Int]?
    public var outputRange: [Int]?
    public var rangeLengthByte: Int?
    public var dpiLengthByte: Int?
    public var firstPreset: Int?
    public var maxPresetCount: Int?
    public var outputChoices: [[Int]]?
    // choice
    public var choices: [ChoiceEntry]?
    // buttons
    public var buttons: [ButtonSpec]?
    public var buttonFieldLength: Int?
    public var buttonDisable: Int?
    public var buttonKeyboard: Int?
    public var buttonMultimedia: Int?
    public var buttonDpiSwitch: Int?
    public var buttonScrollUp: Int?
    public var buttonScrollDown: Int?
}

public struct CommandSpec: Codable, Sendable, Equatable {
    public var command: [Int]
    public var readbackLength: Int
}

public struct BatterySpec: Codable, Sendable, Equatable {
    public var command: [Int]
    public var responseLength: Int
    public var readbackLength: Int
    public var decoder: String
}

public struct DeviceModel: Codable, Sendable, Equatable {
    public var name: String
    /// Physical mouse id; the cable and the dongle of one mouse share saved settings.
    public var mouse: String
    public var vendorId: Int
    public var productId: Int
    public var endpoint: Int
    public var isWireless: Bool
}

public struct DeviceFamily: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var models: [DeviceModel]
    public var settings: [SettingSpec]
    public var battery: BatterySpec?
    public var saveCommand: CommandSpec?

    public func setting(_ key: String) -> SettingSpec? {
        settings.first { $0.key == key }
    }
}

public struct MatchedProfile: Sendable {
    public let family: DeviceFamily
    public let model: DeviceModel
}

public struct ProfileCatalog: Codable, Sendable {
    public var rivalcfgVersion: String
    public var families: [DeviceFamily]

    public static func load() throws -> ProfileCatalog {
        try JSONDecoder().decode(ProfileCatalog.self, from: Data(GeneratedData.profilesJSON.utf8))
    }

    public func match(vendorID: Int, productID: Int) -> MatchedProfile? {
        for family in families {
            if let model = family.models.first(where: { $0.vendorId == vendorID && $0.productId == productID }) {
                return MatchedProfile(family: family, model: model)
            }
        }
        return nil
    }
}

public struct ButtonLayouts: Codable, Sendable {
    /// Lowercased key name (aliases included) -> USB HID usage code.
    public var keyboard: [String: Int]
    /// Lowercased media key name (aliases included) -> code.
    public var multimedia: [String: Int]
    /// Canonical display names in rivalcfg order, for pickers.
    public var keyboardKeys: [String]
    public var multimediaKeys: [String]

    public static func load() throws -> ButtonLayouts {
        try JSONDecoder().decode(ButtonLayouts.self, from: Data(GeneratedData.layoutsJSON.utf8))
    }
}
