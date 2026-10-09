import Foundation
import Testing
@testable import MouseCore

@Suite struct ValuesTests {
    @Test func littleEndianBytes() throws {
        #expect(try Bytes.littleEndian(0x0493E0, length: 3) == [0xE0, 0x93, 0x04])
        #expect(try Bytes.littleEndian(0, length: 1) == [0])
        #expect(try Bytes.littleEndian(255, length: 1) == [255])
    }

    @Test func littleEndianOverflowThrows() {
        #expect(throws: MouseCoreError.overflow) { try Bytes.littleEndian(256, length: 1) }
        #expect(throws: MouseCoreError.overflow) { try Bytes.littleEndian(-1, length: 1) }
    }

    @Test(arguments: [
        ("ff8000", RGBColor(r: 255, g: 128, b: 0)),
        ("#ff8000", RGBColor(r: 255, g: 128, b: 0)),
        ("#f80", RGBColor(r: 255, g: 136, b: 0)),
        ("f80", RGBColor(r: 255, g: 136, b: 0)),
        ("red", RGBColor(r: 255, g: 0, b: 0)),
        ("RED", RGBColor(r: 255, g: 0, b: 0)),
        ("navy", RGBColor(r: 0, g: 0, b: 128)),
    ])
    func parsesColors(text: String, expected: RGBColor) {
        #expect(RGBColor(parsing: text) == expected)
    }

    @Test(arguments: ["", "ggg", "#12345", "+f0", "ff80001", "notacolor"])
    func rejectsBadColors(text: String) {
        #expect(RGBColor(parsing: text) == nil)
    }

    @Test func hexStringRoundTrips() {
        #expect(RGBColor(r: 255, g: 128, b: 0).hexString == "ff8000")
    }

    @Test func buttonMappingLowercasesKeysAndValues() {
        let mapping = ButtonMapping(assignments: ["Button1": "Button2", "ScrollUp": "VolumeUp"])
        #expect(mapping.assignments == ["button1": "button2", "scrollup": "volumeup"])
    }

    @Test(arguments: [
        SettingValue.int(5),
        .choice("1000"),
        .dpiPresets(presets: [400, 800], selected: 1),
        .dpiPresets(presets: [400], selected: nil),
        .color(RGBColor(r: 1, g: 2, b: 3)),
        .buttons(ButtonMapping(assignments: ["button1": "button2"])),
    ])
    func settingValueRoundTripsThroughJSON(value: SettingValue) throws {
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(SettingValue.self, from: data) == value)
    }

    @Test func settingValueDecodesTheGeneratorFormat() throws {
        let json = #"{"type":"dpi","presets":[400,800],"selected":null}"#
        #expect(try JSONDecoder().decode(SettingValue.self, from: Data(json.utf8))
                == .dpiPresets(presets: [400, 800], selected: nil))
    }

    @Test func unknownSettingValueTypeFailsToDecode() {
        let json = #"{"type":"nope"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SettingValue.self, from: Data(json.utf8))
        }
    }
}
