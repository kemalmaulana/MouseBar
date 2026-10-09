public protocol Sleeper: Sendable {
    func sleep(for duration: Duration) async
}

public struct SystemSleeper: Sleeper {
    public init() {}
    /// Returns early when the surrounding task is cancelled.
    public func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}
