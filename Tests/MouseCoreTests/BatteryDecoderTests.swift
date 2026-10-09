import Testing
@testable import MouseCore

@Suite struct BatteryDecoderTests {
    @Test func goldenRepliesMatchRivalcfg() throws {
        let golden = try GoldenFile.load()
        for familyID in primeFamilyIDs {
            for row in try #require(golden.families[familyID]).battery {
                let decoded = BatteryDecoder.decode(decoder: "prime_wireless", reply: bytes(fromHex: row.reply))
                if let expected = row.expected {
                    #expect(decoded == BatteryReading(level: expected.level, isCharging: expected.isCharging),
                            "reply \(row.reply)")
                } else {
                    #expect(decoded == nil, "reply \(row.reply) must be unreadable")
                }
            }
        }
    }

    @Test func fullChargingAndEmpty() {
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: [0x00, 0x15]) == BatteryReading(level: 100, isCharging: false))
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: [0x00, 0x95]) == BatteryReading(level: 100, isCharging: true))
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: [0x00, 0x01]) == BatteryReading(level: 0, isCharging: false))
    }

    @Test func garbageIsUnreadableNotNegativeOrOverHundred() {
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: [0x00, 0x00]) == nil)
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: [0x00, 0x16]) == nil)
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: [0x00, 0xFF]) == nil)
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: [0x00]) == nil)
        #expect(BatteryDecoder.decode(decoder: "prime_wireless", reply: []) == nil)
    }

    @Test func unknownDecoderIsUnreadable() {
        #expect(BatteryDecoder.decode(decoder: "nope", reply: [0x00, 0x15]) == nil)
    }
}
