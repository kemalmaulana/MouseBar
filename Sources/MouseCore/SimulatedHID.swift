import Foundation
import os

/// In-memory HID connection used by tests and by the app's `--demo` mode.
public actor SimulatedHIDConnection: HIDConnection {
    public typealias ReplyProvider = @Sendable ([UInt8]) -> [UInt8]?
    /// Like `ReplyProvider` but may queue several reports for one write (e.g. a foreign report, then the real answer).
    public typealias RepliesProvider = @Sendable ([UInt8]) -> [[UInt8]]

    public private(set) var writes: [[UInt8]] = []
    /// Operation order: "write", "read:<length>", "flush".
    public private(set) var log: [String] = []
    public private(set) var isClosed = false
    private var replies: [[UInt8]] = []
    private var failingWrites: Int
    private let replyProvider: ReplyProvider?
    private let repliesProvider: RepliesProvider?

    public init(
        replyProvider: ReplyProvider? = nil,
        repliesProvider: RepliesProvider? = nil,
        failingWrites: Int = 0
    ) {
        self.replyProvider = replyProvider
        self.repliesProvider = repliesProvider
        self.failingWrites = failingWrites
    }

    public func enqueueReply(_ bytes: [UInt8]) {
        replies.append(bytes)
    }

    public func write(_ payload: [UInt8]) async throws {
        log.append("write")
        if failingWrites > 0 {
            failingWrites -= 1
            throw HIDError.simulated("write failed")
        }
        writes.append(payload)
        if let reply = replyProvider?(payload) {
            replies.append(reply)
        }
        if let several = repliesProvider?(payload) {
            replies.append(contentsOf: several)
        }
    }

    public func read(length: Int, timeout: Duration) async throws -> [UInt8]? {
        log.append("read:\(length)")
        guard !replies.isEmpty else { return nil }
        return Array(replies.removeFirst().prefix(length))
    }

    public func flushInput() async {
        log.append("flush")
        replies.removeAll()
    }

    public func close() async {
        isClosed = true
    }
}

public final class SimulatedHIDTransport: HIDTransport, Sendable {
    private let stream: AsyncStream<HIDEvent>
    private let continuation: AsyncStream<HIDEvent>.Continuation
    private let connections = OSAllocatedUnfairLock<[UInt64: SimulatedHIDConnection]>(initialState: [:])
    private let openFails = OSAllocatedUnfairLock<Bool>(initialState: false)

    public init() {
        let made = AsyncStream.makeStream(of: HIDEvent.self)
        stream = made.stream
        continuation = made.continuation
    }

    public func plug(_ info: HIDDeviceInfo, connection: SimulatedHIDConnection) {
        connections.withLock { $0[info.id] = connection }
        continuation.yield(.added(info))
    }

    public func unplug(id: UInt64) {
        _ = connections.withLock { $0.removeValue(forKey: id) }
        continuation.yield(.removed(id))
    }

    public func setOpenFails(_ fails: Bool) {
        openFails.withLock { $0 = fails }
    }

    public func events() -> AsyncStream<HIDEvent> {
        stream
    }

    public func open(_ device: HIDDeviceInfo) async throws -> any HIDConnection {
        if openFails.withLock({ $0 }) {
            throw HIDError.openFailed(code: -536870174)
        }
        guard let connection = connections.withLock({ $0[device.id] }) else {
            throw HIDError.notOpen
        }
        return connection
    }
}
