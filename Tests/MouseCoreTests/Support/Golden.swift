import Foundation
import Testing
@testable import MouseCore

let primeFamilyIDs = ["prime_wireless_wired", "prime_wireless_wireless"]

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

func bytes(fromHex text: String) -> [UInt8] {
    stride(from: 0, to: text.count, by: 2).map { i in
        let start = text.index(text.startIndex, offsetBy: i)
        return UInt8(text[start..<text.index(start, offsetBy: 2)], radix: 16)!
    }
}

struct GoldenFile: Decodable {
    struct Case: Decodable {
        let setting: String
        let value: SettingValue
        let hex: String
    }
    struct Expected: Decodable, Equatable {
        let level: Int
        let isCharging: Bool
    }
    struct Battery: Decodable {
        let reply: String
        let expected: Expected?
    }
    struct Family: Decodable {
        let settings: [Case]
        let saveHex: String
        let batteryQueryHex: String
        let battery: [Battery]
    }
    let rivalcfgVersion: String
    let families: [String: Family]

    static func load() throws -> GoldenFile {
        let url = try #require(
            Bundle.module.url(forResource: "golden", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(GoldenFile.self, from: Data(contentsOf: url))
    }
}

func spec(_ familyID: String, _ key: String) throws -> SettingSpec {
    let catalog = try ProfileCatalog.load()
    let family = try #require(catalog.families.first { $0.id == familyID })
    return try #require(family.setting(key))
}

/// Checks the encoder against every golden case of `familyID` whose setting key is in `keys`.
func assertGolden(familyID: String, keys: Set<String>) throws {
    let golden = try #require(try GoldenFile.load().families[familyID])
    let encoder = SettingEncoder(layouts: try ButtonLayouts.load())
    var checked = 0
    for c in golden.settings where keys.contains(c.setting) {
        let encoded = try encoder.encode(try spec(familyID, c.setting), value: c.value)
        #expect(hex(encoded) == c.hex, "\(familyID) \(c.setting) \(c.value)")
        checked += 1
    }
    #expect(checked > 0, "no golden cases for \(keys)")
}
