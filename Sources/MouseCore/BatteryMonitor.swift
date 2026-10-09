import Foundation

public struct BatteryState: Equatable, Sendable {
    public enum Freshness: Equatable, Sendable {
        case fresh, stale, asleep, disconnected
    }

    public var level: Int?
    public var isCharging: Bool?
    public var lastReadAt: Date?
    public var consecutiveFailures: Int
    public var freshness: Freshness

    public static let disconnected = BatteryState(
        level: nil, isCharging: nil, lastReadAt: nil, consecutiveFailures: 0, freshness: .disconnected
    )
    /// A mouse is connected but nothing has been read yet.
    public static let connecting = BatteryState(
        level: nil, isCharging: nil, lastReadAt: nil, consecutiveFailures: 0, freshness: .stale
    )

    /// One failed read keeps the last value as stale; two in a row mean asleep. The last value is kept.
    public func applying(_ reading: BatteryReading?, at date: Date) -> BatteryState {
        if let reading {
            return BatteryState(
                level: reading.level, isCharging: reading.isCharging,
                lastReadAt: date, consecutiveFailures: 0, freshness: .fresh
            )
        }
        var next = self
        next.consecutiveFailures += 1
        next.freshness = next.consecutiveFailures >= 2 ? .asleep : .stale
        return next
    }
}

public actor BatteryMonitor {
    private let device: MouseDevice
    private let interval: Duration
    private let sleeper: any Sleeper
    private let now: @Sendable () -> Date
    private var state = BatteryState.connecting

    public init(
        device: MouseDevice,
        interval: Duration,
        sleeper: any Sleeper,
        now: @escaping @Sendable () -> Date
    ) {
        self.device = device
        self.interval = interval
        self.sleeper = sleeper
        self.now = now
    }

    public func pollOnce() async -> BatteryState {
        let reading = try? await device.readBattery()
        state = state.applying(reading, at: now())
        return state
    }

    /// Polls until the task is cancelled.
    public func run(_ onChange: @escaping @Sendable (BatteryState) async -> Void) async {
        while !Task.isCancelled {
            await onChange(await pollOnce())
            await sleeper.sleep(for: interval)
        }
    }
}

public enum BatteryPresentation {
    public static func symbolName(for state: BatteryState) -> String {
        guard state.freshness != .disconnected, let level = state.level else { return "computermouse" }
        if state.isCharging == true { return "battery.100percent.bolt" }
        switch level {
        case 88...: return "battery.100percent"
        case 63...: return "battery.75percent"
        case 38...: return "battery.50percent"
        case 13...: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    /// Text next to the menu bar icon. `nil` means show the icon only.
    public static func compactTitle(for state: BatteryState) -> String? {
        if state.freshness == .disconnected { return nil }
        guard let level = state.level else { return "…" }
        return "\(level)%"
    }

    public static func detail(for state: BatteryState, now: Date) -> String {
        if state.freshness == .disconnected { return "No mouse connected" }
        guard let level = state.level else { return "Reading battery…" }
        let charging = state.isCharging == true ? ", charging" : ""
        switch state.freshness {
        case .fresh:
            return "\(level)%\(charging)"
        case .stale:
            return "\(level)%\(charging) (updating…)"
        case .asleep:
            let minutes = state.lastReadAt.map { max(1, Int(now.timeIntervalSince($0) / 60)) }
            let age = minutes.map { ", last read \($0) min ago" } ?? ""
            return "\(level)% (mouse asleep\(age))"
        case .disconnected:
            return "No mouse connected"
        }
    }
}
