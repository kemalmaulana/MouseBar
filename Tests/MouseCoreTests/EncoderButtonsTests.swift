import Testing
@testable import MouseCore

@Suite struct EncoderButtonsTests {
    let encoder: SettingEncoder

    init() throws {
        encoder = SettingEncoder(layouts: try ButtonLayouts.load())
    }

    @Test(arguments: primeFamilyIDs)
    func buttonsMatchRivalcfg(familyID: String) throws {
        try assertGolden(familyID: familyID, keys: ["buttons_mapping"])
    }

    @Test func defaultMappingIsFortyBytes() throws {
        let s = try spec("prime_wireless_wired", "buttons_mapping")
        let out = try encoder.encode(s, value: .buttons(ButtonMapping()))
        #expect(out.count == 1 + 40)
        #expect(out[0] == 0x2A)
        #expect(Array(out[1...5]) == [0x01, 0, 0, 0, 0])          // button1 -> button1
        #expect(Array(out[26...30]) == [0x30, 0, 0, 0, 0])        // button6 -> dpi
    }

    @Test func mediaKeyUsesMultimediaPrefixAndCode() throws {
        let s = try spec("prime_wireless_wired", "buttons_mapping")
        let out = try encoder.encode(s, value: .buttons(ButtonMapping(assignments: ["button4": "PlayPause"])))
        #expect(Array(out[16...17]) == [0x61, 0xCD])
    }

    @Test func keyboardKeyUsesKeyboardPrefixAndCode() throws {
        let s = try spec("prime_wireless_wired", "buttons_mapping")
        let out = try encoder.encode(s, value: .buttons(ButtonMapping(assignments: ["button3": "a"])))
        #expect(Array(out[11...12]) == [0x51, 0x04])
    }

    @Test func aliasesResolve() throws {
        let s = try spec("prime_wireless_wired", "buttons_mapping")
        let alias = try encoder.encode(s, value: .buttons(ButtonMapping(assignments: ["button4": "vol+"])))
        let canonical = try encoder.encode(s, value: .buttons(ButtonMapping(assignments: ["button4": "VolumeUp"])))
        #expect(alias == canonical)
    }

    @Test func unknownButtonAndUnknownActionThrow() throws {
        let s = try spec("prime_wireless_wired", "buttons_mapping")
        #expect(throws: MouseCoreError.self) {
            try encoder.encode(s, value: .buttons(ButtonMapping(assignments: ["button9": "button1"])))
        }
        #expect(throws: MouseCoreError.self) {
            try encoder.encode(s, value: .buttons(ButtonMapping(assignments: ["button2": "notakey"])))
        }
    }

    @Test func validationAcceptsDefaultAndSwap() throws {
        let s = try spec("prime_wireless_wired", "buttons_mapping")
        try encoder.validateButtons(ButtonMapping(), spec: s)
        try encoder.validateButtons(ButtonMapping(assignments: ["button1": "button2", "button2": "button1"]), spec: s)
    }

    @Test func validationRejectsMappingWithNoLeftClick() throws {
        let s = try spec("prime_wireless_wired", "buttons_mapping")
        #expect(throws: MouseCoreError.noPrimaryClick) {
            try encoder.validateButtons(ButtonMapping(assignments: ["button1": "disabled"]), spec: s)
        }
        #expect(throws: MouseCoreError.noPrimaryClick) {
            try encoder.validateButtons(ButtonMapping(assignments: ["button1": "a"]), spec: s)
        }
    }
}
