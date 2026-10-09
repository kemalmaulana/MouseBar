import Testing
@testable import MouseCore

@Suite struct EncoderBasicTests {
    let encoder = SettingEncoder(layouts: ButtonLayouts(keyboard: [:], multimedia: [:], keyboardKeys: [], multimediaKeys: []))

    @Test(arguments: primeFamilyIDs)
    func choiceRangeAndColorMatchRivalcfg(familyID: String) throws {
        try assertGolden(
            familyID: familyID,
            keys: ["polling_rate", "default_lighting", "sleep_timer", "dim_timer", "color"]
        )
    }

    @Test func pollingRateWiredBytes() throws {
        let s = try spec("prime_wireless_wired", "polling_rate")
        #expect(try encoder.encode(s, value: .choice("500")) == [0x2B, 0x01])
    }

    @Test func unknownChoiceThrowsAndNamesTheValidOnes() throws {
        let s = try spec("prime_wireless_wired", "polling_rate")
        #expect(throws: MouseCoreError.self) { try encoder.encode(s, value: .choice("333")) }
    }

    @Test func rangeClampsAboveAndBelow() throws {
        let s = try spec("prime_wireless_wired", "sleep_timer")
        let max = try encoder.encode(s, value: .int(20))
        #expect(try encoder.encode(s, value: .int(25)) == max)
        let zero = try encoder.encode(s, value: .int(0))
        #expect(try encoder.encode(s, value: .int(-3)) == zero)
    }

    @Test func rangeSleepTimerFiveMinutesIsThreeHundredThousandMillis() throws {
        let s = try spec("prime_wireless_wired", "sleep_timer")
        #expect(try encoder.encode(s, value: .int(5)) == [0x29, 0xE0, 0x93, 0x04])
    }

    @Test func nearestInRangeRoundsToNearestStep() {
        #expect(SettingEncoder.nearestInRange(start: 0, stop: 1000, step: 100, value: 110) == 100)
        #expect(SettingEncoder.nearestInRange(start: 0, stop: 1000, step: 100, value: 190) == 200)
        #expect(SettingEncoder.nearestInRange(start: 42, stop: 1000, step: 100, value: 150) == 142)
    }

    @Test func wrongValueKindForSettingThrowsMismatch() throws {
        let s = try spec("prime_wireless_wired", "polling_rate")
        #expect(throws: MouseCoreError.valueMismatch(setting: "polling_rate", expected: "choice")) {
            try encoder.encode(s, value: .int(500))
        }
    }

    @Test func colorPayloadIsCommandThenRGB() throws {
        let s = try spec("prime_wireless_wired", "color")
        #expect(try encoder.encode(s, value: .color(RGBColor(r: 1, g: 2, b: 3))) == [0x21, 0x01, 0x00, 1, 2, 3])
    }
}
