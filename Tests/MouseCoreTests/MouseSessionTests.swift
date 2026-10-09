import Foundation
import Testing
@testable import MouseCore

@Suite struct MouseSessionTests {
    struct Rig {
        let session: MouseSession
        let connection: SimulatedHIDConnection
        let store: SettingsStore
        let sleeper: ManualSleeper

        /// Ends the session and releases every parked sleep so no continuation leaks.
        /// `sleepers` is how many sleeps the test caused (battery loop, save timers). Waiting for
        /// them before stopping closes the race where a sleep registers after the release.
        func finish(sleepers: Int = 0) async {
            _ = await waitUntil { await sleeper.waiterCount >= sleepers }
            await session.stop()
            await sleeper.releaseAll()
        }
    }

    func makeRig(productID: Int = 0x184A) async throws -> Rig {
        let catalog = try ProfileCatalog.load()
        let match = try #require(catalog.match(vendorID: 0x1038, productID: productID))
        let connection = SimulatedHIDConnection(replyProvider: batteryReplyProvider(raw: 0x0B))
        let encoder = SettingEncoder(layouts: try ButtonLayouts.load())
        let device = MouseDevice(
            family: match.family, model: match.model, connection: connection,
            encoder: encoder, sleeper: RecordingSleeper()
        )
        let store = SettingsStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("mousebar-\(UUID().uuidString)")
        )
        let sleeper = ManualSleeper()
        let session = MouseSession(
            mouse: ConnectedMouse(hidID: 1, family: match.family, model: match.model, device: device),
            store: store, encoder: encoder, sleeper: sleeper
        )
        return Rig(session: session, connection: connection, store: store, sleeper: sleeper)
    }

    @Test func startReappliesStoredValuesInProfileOrder() async throws {
        let rig = try await makeRig()
        // Stored out of profile order on purpose.
        try await rig.store.set(.int(10), key: "sleep_timer", mouse: "prime_mini_wireless")
        try await rig.store.set(.choice("500"), key: "polling_rate", mouse: "prime_mini_wireless")
        let errors = await rig.session.start(onBattery: { _ in }, onError: { _ in })
        #expect(errors.isEmpty)
        let writes = await rig.connection.writes.filter { $0.first != 0x92 }
        #expect(writes == [[0x2B, 0x01], [0x29, 0xC0, 0x27, 0x09]])   // polling_rate, then sleep_timer (10 min)
        await rig.finish(sleepers: 1)
    }

    @Test func startReportsBatteryThroughTheCallback() async throws {
        let rig = try await makeRig()
        let box = StateBox()
        _ = await rig.session.start(onBattery: { await box.set($0) }, onError: { _ in })
        #expect(await waitUntil { await box.value?.level == 50 })
        await rig.finish(sleepers: 1)
    }

    @Test func setWritesPersistsAndSchedulesExactlyOneSave() async throws {
        let rig = try await makeRig()
        try await rig.session.set("polling_rate", .choice("250"))
        try await rig.session.set("polling_rate", .choice("125"))
        #expect(await rig.connection.writes == [[0x2B, 0x02], [0x2B, 0x03]])
        #expect(await rig.store.values(for: "prime_mini_wireless")["polling_rate"] == .choice("125"))
        #expect(await waitUntil { await rig.sleeper.waiterCount == 2 })
        await rig.sleeper.releaseAll()
        #expect(await waitUntil { await rig.connection.writes.count == 3 })
        #expect(await rig.connection.writes.last == [0x11, 0x00])
        await rig.finish()
    }

    @Test func colorIsAppliedButNeverScheduledForSaving() async throws {
        let rig = try await makeRig()
        try await rig.session.set("color", .color(RGBColor(r: 255, g: 128, b: 0)))
        #expect(await rig.connection.writes == [[0x21, 0x01, 0x00, 255, 128, 0]])
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await rig.sleeper.waiterCount == 0)
        await rig.finish()
    }

    @Test func buttonMappingWithoutLeftClickIsRejectedBeforeAnyWrite() async throws {
        let rig = try await makeRig()
        await #expect(throws: MouseCoreError.noPrimaryClick) {
            try await rig.session.set("buttons_mapping", .buttons(ButtonMapping(assignments: ["button1": "disabled"])))
        }
        #expect(await rig.connection.writes.isEmpty)
        #expect(await rig.store.values(for: "prime_mini_wireless").isEmpty)
    }

    @Test func invalidValueIsNotPersisted() async throws {
        let rig = try await makeRig()
        await #expect(throws: MouseCoreError.self) {
            try await rig.session.set("sensitivity", .dpiPresets(presets: [], selected: nil))
        }
        #expect(await rig.store.values(for: "prime_mini_wireless").isEmpty)
    }

    @Test func flushSavesAPendingChangeImmediately() async throws {
        let rig = try await makeRig()
        try await rig.session.set("polling_rate", .choice("500"))
        await rig.session.flush()
        #expect(await rig.connection.writes.last == [0x11, 0x00])
        await rig.finish(sleepers: 1)
    }

    @Test func submitCoalescesToTheLatestValue() async throws {
        let rig = try await makeRig()
        for g in stride(from: 0, through: 250, by: 25) {
            await rig.session.submit("color", .color(RGBColor(r: 0, g: UInt8(g), b: 0)))
        }
        await rig.session.waitUntilIdle()
        let writes = await rig.connection.writes
        #expect(writes.last == [0x21, 0x01, 0x00, 0, 250, 0])
        #expect(writes.count <= 11)
        await rig.finish()
    }

    @Test func resetAllAppliesFactoryDefaultsClearsTheStoreAndSchedulesASave() async throws {
        let rig = try await makeRig()
        try await rig.session.set("polling_rate", .choice("125"))
        let before = await rig.connection.writes.count
        try await rig.session.resetAll()
        let writes = await rig.connection.writes
        #expect(writes.count - before == 7)                       // every setting of the family
        #expect(writes.contains([0x2B, 0x00]))                    // polling back to 1000 Hz
        #expect(await rig.store.values(for: "prime_mini_wireless").isEmpty)
        #expect(await waitUntil { await rig.sleeper.waiterCount >= 1 })
        await rig.finish(sleepers: 2)
    }

    @Test func currentValuesReflectWhatTheUserChose() async throws {
        let rig = try await makeRig()
        try await rig.session.set("sleep_timer", .int(7))
        #expect(await rig.session.currentValues["sleep_timer"] == .int(7))
        await rig.finish(sleepers: 1)
    }
}

actor StateBox {
    private(set) var value: BatteryState?
    func set(_ state: BatteryState) { value = state }
}
