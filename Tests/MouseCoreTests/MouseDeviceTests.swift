import Testing
@testable import MouseCore

@Suite struct MouseDeviceTests {
    @Test func wiredWriteIsPacedAndHasNoReadback() async throws {
        let (device, connection, sleeper) = try makeDevice(familyID: "prime_wireless_wired", productID: 0x184A)
        try await device.apply("polling_rate", .choice("500"))
        #expect(await connection.writes == [[0x2B, 0x01]])
        #expect(await connection.log == ["write"])
        #expect(await sleeper.sleeps == [.milliseconds(50)])
    }

    @Test func dongleWriteReadsBackSixtyFourBytes() async throws {
        let (device, connection, _) = try makeDevice(familyID: "prime_wireless_wireless", productID: 0x1848)
        try await device.apply("polling_rate", .choice("500"))
        #expect(await connection.writes == [[0x6B, 0x01]])
        #expect(await connection.log == ["write", "read:64"])
    }

    @Test func aFailedWriteIsRetriedOnceAfterTheDelay() async throws {
        let (device, connection, sleeper) = try makeDevice(
            familyID: "prime_wireless_wired", productID: 0x184A, failingWrites: 1
        )
        try await device.apply("polling_rate", .choice("250"))
        #expect(await connection.writes == [[0x2B, 0x02]])
        #expect(await connection.log == ["write", "write"])
        #expect(await sleeper.sleeps.count == 2)
    }

    @Test func twoFailedWritesThrow() async throws {
        let (device, connection, _) = try makeDevice(
            familyID: "prime_wireless_wired", productID: 0x184A, failingWrites: 2
        )
        await #expect(throws: HIDError.self) {
            try await device.apply("polling_rate", .choice("250"))
        }
        #expect(await connection.writes.isEmpty)
    }

    @Test func invalidValueThrowsBeforeAnythingIsWritten() async throws {
        let (device, connection, _) = try makeDevice(familyID: "prime_wireless_wired", productID: 0x184A)
        await #expect(throws: MouseCoreError.self) {
            try await device.apply("sensitivity", .dpiPresets(presets: [], selected: nil))
        }
        #expect(await connection.log.isEmpty)
    }

    @Test func unknownSettingThrows() async throws {
        let (device, _, _) = try makeDevice(familyID: "prime_wireless_wired", productID: 0x184A)
        await #expect(throws: MouseCoreError.unknownSetting("nope")) {
            try await device.apply("nope", .int(1))
        }
    }

    @Test func saveUsesTheFamilySaveCommand() async throws {
        let (wired, wiredConn, _) = try makeDevice(familyID: "prime_wireless_wired", productID: 0x184A)
        try await wired.save()
        #expect(await wiredConn.writes == [[0x11, 0x00]])

        let (dongle, dongleConn, _) = try makeDevice(familyID: "prime_wireless_wireless", productID: 0x1848)
        try await dongle.save()
        #expect(await dongleConn.writes == [[0x51, 0x00]])
        #expect(await dongleConn.log == ["write", "read:64"])
    }

    @Test func batteryFlushesStaleInputThenQueriesThenDecodes() async throws {
        let (device, connection, _) = try makeDevice(
            familyID: "prime_wireless_wireless", productID: 0x1848,
            replyProvider: batteryReplyProvider(raw: 0x95)
        )
        await connection.enqueueReply([0x00, 0x0B])                 // stale report from before the query
        let reading = try await device.readBattery()
        #expect(reading == BatteryReading(level: 100, isCharging: true))
        #expect(await connection.writes == [[0xD2]])
        #expect(await connection.log == ["flush", "write", "read:2"])
    }

    @Test func batteryWiredUsesTheWiredQueryByte() async throws {
        let (device, connection, _) = try makeDevice(
            familyID: "prime_wireless_wired", productID: 0x184A,
            replyProvider: batteryReplyProvider(raw: 0x0B)
        )
        #expect(try await device.readBattery() == BatteryReading(level: 50, isCharging: false))
        #expect(await connection.writes == [[0x92]])
    }

    @Test func batteryIsNilWhenTheMouseDoesNotAnswer() async throws {
        let (device, _, _) = try makeDevice(familyID: "prime_wireless_wireless", productID: 0x1848)
        #expect(try await device.readBattery() == nil)
    }

    @Test func batteryIsNilForGarbageReply() async throws {
        let (device, _, _) = try makeDevice(
            familyID: "prime_wireless_wireless", productID: 0x1848,
            replyProvider: batteryReplyProvider(raw: 0x00)
        )
        #expect(try await device.readBattery() == nil)
    }

    @Test func closeClosesTheConnection() async throws {
        let (device, connection, _) = try makeDevice(familyID: "prime_wireless_wired", productID: 0x184A)
        await device.close()
        #expect(await connection.isClosed)
    }
}
