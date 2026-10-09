import Testing
@testable import MouseCore

@Suite struct EncoderDPITests {
    let encoder = SettingEncoder(layouts: ButtonLayouts(keyboard: [:], multimedia: [:], keyboardKeys: [], multimediaKeys: []))

    @Test(arguments: primeFamilyIDs)
    func dpiMatchesRivalcfg(familyID: String) throws {
        try assertGolden(familyID: familyID, keys: ["sensitivity"])
    }

    @Test func defaultFivePresetsWired() throws {
        let s = try spec("prime_wireless_wired", "sensitivity")
        let out = try encoder.encode(s, value: .dpiPresets(presets: [400, 800, 1200, 2400, 3200], selected: nil))
        #expect(out == [0x2D, 0x05, 0x00, 0x04, 0x09, 0x0D, 0x1B, 0x26])
    }

    @Test func selectedPresetIsEncodedAsSecondByte() throws {
        let s = try spec("prime_wireless_wired", "sensitivity")
        let out = try encoder.encode(s, value: .dpiPresets(presets: [400, 800, 1200], selected: 2))
        #expect(out[1] == 3)
        #expect(out[2] == 2)
    }

    @Test func emptyPresetListThrowsAndWritesNothing() throws {
        let s = try spec("prime_wireless_wired", "sensitivity")
        #expect(throws: MouseCoreError.self) {
            try encoder.encode(s, value: .dpiPresets(presets: [], selected: nil))
        }
    }

    @Test func sixPresetsThrowBecauseTheMouseHoldsFive() throws {
        let s = try spec("prime_wireless_wired", "sensitivity")
        #expect(throws: MouseCoreError.self) {
            try encoder.encode(s, value: .dpiPresets(presets: [400, 800, 1200, 1600, 2000, 2400], selected: nil))
        }
    }

    @Test func selectedPresetBeyondTheListThrows() throws {
        let s = try spec("prime_wireless_wired", "sensitivity")
        #expect(throws: MouseCoreError.self) {
            try encoder.encode(s, value: .dpiPresets(presets: [400, 800], selected: 2))
        }
        #expect(throws: MouseCoreError.self) {
            try encoder.encode(s, value: .dpiPresets(presets: [400, 800], selected: -1))
        }
    }

    @Test func outOfRangeDpiClampsToNearestSupportedValue() throws {
        let s = try spec("prime_wireless_wired", "sensitivity")
        let clamped = try encoder.encode(s, value: .dpiPresets(presets: [50, 20000], selected: nil))
        let exact = try encoder.encode(s, value: .dpiPresets(presets: [100, 18000], selected: nil))
        #expect(clamped == exact)
    }

    @Test func tieBetweenTwoSupportedValuesPicksTheLowerOne() throws {
        let s = try spec("prime_wireless_wired", "sensitivity")
        let tie = try encoder.encode(s, value: .dpiPresets(presets: [150], selected: nil))
        let low = try encoder.encode(s, value: .dpiPresets(presets: [100], selected: nil))
        #expect(tie == low)
    }
}
