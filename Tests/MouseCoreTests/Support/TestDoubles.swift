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

/// Battery replies a Prime Wireless would send: 64 bytes, byte 0 echoes the command, level code in byte 1
/// (the wired layout seen on hardware: `92 94 00 ...`).
func batteryReplyProvider(raw: UInt8) -> SimulatedHIDConnection.ReplyProvider {
    { payload in
        guard let first = payload.first, first == 0x92 || first == 0xD2 else { return nil }
        return [first, raw] + [UInt8](repeating: 0, count: 62)
    }
}

/// A 64-byte HID report with the given leading bytes.
func report(_ head: [UInt8]) -> [UInt8] {
    head + [UInt8](repeating: 0, count: 64 - head.count)
}

func makeDevice(
    familyID: String,
    productID: Int,
    replyProvider: SimulatedHIDConnection.ReplyProvider? = nil,
    repliesProvider: SimulatedHIDConnection.RepliesProvider? = nil,
    failingWrites: Int = 0
) throws -> (MouseDevice, SimulatedHIDConnection, RecordingSleeper) {
    let sleeper = RecordingSleeper()
    let (device, connection) = try makeDevice(
        familyID: familyID, productID: productID, sleeper: sleeper,
        replyProvider: replyProvider, repliesProvider: repliesProvider, failingWrites: failingWrites
    )
    return (device, connection, sleeper)
}

/// Same as above with a caller-supplied sleeper (e.g. `ManualSleeper`).
func makeDevice(
    familyID: String,
    productID: Int,
    sleeper: some Sleeper,
    replyProvider: SimulatedHIDConnection.ReplyProvider? = nil,
    repliesProvider: SimulatedHIDConnection.RepliesProvider? = nil,
    failingWrites: Int = 0
) throws -> (MouseDevice, SimulatedHIDConnection) {
    let catalog = try ProfileCatalog.load()
    let match = try #require(catalog.match(vendorID: 0x1038, productID: productID))
    #expect(match.family.id == familyID)
    let connection = SimulatedHIDConnection(
        replyProvider: replyProvider, repliesProvider: repliesProvider, failingWrites: failingWrites
    )
    let device = MouseDevice(
        family: match.family,
        model: match.model,
        connection: connection,
        encoder: SettingEncoder(layouts: try ButtonLayouts.load()),
        sleeper: sleeper
    )
    return (device, connection)
}
