import Foundation
import Testing
@testable import MouseCore

@Suite struct BatteryTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func freshReadingReplacesEverything() {
        let state = BatteryState.connecting.applying(BatteryReading(level: 80, isCharging: false), at: t0)
        #expect(state.level == 80)
        #expect(state.isCharging == false)
        #expect(state.freshness == .fresh)
        #expect(state.lastReadAt == t0)
        #expect(state.consecutiveFailures == 0)
    }

    @Test func oneFailureIsStaleTwoIsAsleepAndBothKeepTheLastValue() {
        let fresh = BatteryState.connecting.applying(BatteryReading(level: 80, isCharging: false), at: t0)
        let stale = fresh.applying(nil, at: t0.addingTimeInterval(60))
        #expect(stale.freshness == .stale)
        #expect(stale.level == 80)
        let asleep = stale.applying(nil, at: t0.addingTimeInterval(120))
        #expect(asleep.freshness == .asleep)
        #expect(asleep.level == 80)
        #expect(asleep.lastReadAt == t0)
    }

    @Test func aSuccessfulReadAfterSleepingIsFreshAgain() {
        let asleep = BatteryState.connecting
            .applying(BatteryReading(level: 80, isCharging: false), at: t0)
            .applying(nil, at: t0).applying(nil, at: t0)
        let woke = asleep.applying(BatteryReading(level: 79, isCharging: false), at: t0.addingTimeInterval(300))
        #expect(woke.freshness == .fresh)
        #expect(woke.level == 79)
        #expect(woke.consecutiveFailures == 0)
    }

    @Test func neverReadStaysWithoutALevelNeverZero() {
        let state = BatteryState.connecting.applying(nil, at: t0).applying(nil, at: t0)
        #expect(state.level == nil)
        #expect(state.freshness == .asleep)
    }

    @Test func presentation() {
        let fresh = BatteryState.connecting.applying(BatteryReading(level: 87, isCharging: false), at: t0)
        #expect(BatteryPresentation.compactTitle(for: fresh) == "87%")
        #expect(BatteryPresentation.symbolName(for: fresh) == "battery.75percent")
        let charging = BatteryState.connecting.applying(BatteryReading(level: 40, isCharging: true), at: t0)
        #expect(BatteryPresentation.symbolName(for: charging) == "battery.100percent.bolt")
        let low = BatteryState.connecting.applying(BatteryReading(level: 5, isCharging: false), at: t0)
        #expect(BatteryPresentation.symbolName(for: low) == "battery.0percent")
        #expect(BatteryPresentation.compactTitle(for: .disconnected) == nil)
        #expect(BatteryPresentation.symbolName(for: .disconnected) == "computermouse")
        #expect(BatteryPresentation.compactTitle(for: .connecting) == "…")
    }

    @Test func detailMentionsSleepAndAge() {
        let asleep = BatteryState.connecting
            .applying(BatteryReading(level: 80, isCharging: false), at: t0)
            .applying(nil, at: t0).applying(nil, at: t0)
        let text = BatteryPresentation.detail(for: asleep, now: t0.addingTimeInterval(180))
        #expect(text.contains("80%"))
        #expect(text.contains("asleep"))
        #expect(text.contains("3 min"))
        #expect(BatteryPresentation.detail(for: .disconnected, now: t0) == "No mouse connected")
    }

    @Test func detailSaysAsleepForAMouseThatWasNeverRead() {
        let state = BatteryState.connecting.applying(nil, at: t0).applying(nil, at: t0)
        #expect(state.level == nil)
        let text = BatteryPresentation.detail(for: state, now: t0)
        #expect(text.contains("asleep"))
        #expect(BatteryPresentation.detail(for: .connecting, now: t0) == "Reading battery…")   // one failure is not asleep yet
        #expect(BatteryPresentation.compactTitle(for: state) == "…")
        #expect(BatteryPresentation.symbolName(for: state) == "computermouse")
    }

    @Test func monitorPollOnceReadsTheDeviceAndTracksFailures() async throws {
        let catalog = try ProfileCatalog.load()
        let match = try #require(catalog.match(vendorID: 0x1038, productID: 0x1848))
        let connection = SimulatedHIDConnection(replyProvider: batteryReplyProvider(raw: 0x0B))
        let device = MouseDevice(
            family: match.family, model: match.model, connection: connection,
            encoder: SettingEncoder(layouts: try ButtonLayouts.load()), sleeper: RecordingSleeper()
        )
        let monitor = BatteryMonitor(device: device, interval: .seconds(60), sleeper: RecordingSleeper(), now: { Date(timeIntervalSince1970: 5) })
        let state = await monitor.pollOnce()
        #expect(state.level == 50)
        #expect(state.freshness == .fresh)
    }

    @Test func monitorMarksAsleepWhenTheMouseStaysSilent() async throws {
        let catalog = try ProfileCatalog.load()
        let match = try #require(catalog.match(vendorID: 0x1038, productID: 0x1848))
        let device = MouseDevice(
            family: match.family, model: match.model, connection: SimulatedHIDConnection(),
            encoder: SettingEncoder(layouts: try ButtonLayouts.load()), sleeper: RecordingSleeper()
        )
        let monitor = BatteryMonitor(device: device, interval: .seconds(60), sleeper: RecordingSleeper(), now: { Date() })
        _ = await monitor.pollOnce()
        let second = await monitor.pollOnce()
        #expect(second.freshness == .asleep)
        #expect(second.level == nil)
    }
}
