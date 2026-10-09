import Foundation
import Testing
@testable import MouseCore

actor RecordingSleeper: Sleeper {
    private(set) var sleeps: [Duration] = []
    func sleep(for duration: Duration) async { sleeps.append(duration) }
}

/// A sleeper that blocks until the test calls `releaseAll()`.
actor ManualSleeper: Sleeper {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var waiterCount: Int { waiters.count }
    func sleep(for duration: Duration) async {
        await withCheckedContinuation { waiters.append($0) }
    }
    func releaseAll() {
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume() }
    }
}

/// Polls `condition` every 5 ms for up to 2 s.
func waitUntil(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<400 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

/// Battery replies a Prime Wireless would send: 64 bytes, level code in byte 1.
func batteryReplyProvider(raw: UInt8) -> SimulatedHIDConnection.ReplyProvider {
    { payload in
        guard let first = payload.first, first == 0x92 || first == 0xD2 else { return nil }
        return [0x00, raw] + [UInt8](repeating: 0, count: 62)
    }
}

func makeDevice(
    familyID: String,
    productID: Int,
    replyProvider: SimulatedHIDConnection.ReplyProvider? = nil,
    failingWrites: Int = 0
) throws -> (MouseDevice, SimulatedHIDConnection, RecordingSleeper) {
    let catalog = try ProfileCatalog.load()
    let match = try #require(catalog.match(vendorID: 0x1038, productID: productID))
    #expect(match.family.id == familyID)
    let connection = SimulatedHIDConnection(replyProvider: replyProvider, failingWrites: failingWrites)
    let sleeper = RecordingSleeper()
    let device = MouseDevice(
        family: match.family,
        model: match.model,
        connection: connection,
        encoder: SettingEncoder(layouts: try ButtonLayouts.load()),
        sleeper: sleeper
    )
    return (device, connection, sleeper)
}
