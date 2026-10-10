public enum PollingRateEstimator {
    /// Events per second from event timestamps in seconds: 1 / the median interval between consecutive events,
    /// ignoring zero intervals and gaps longer than 100 ms (the mouse paused). `nil` with fewer than 10 usable intervals.
    public static func rate(timestamps: [Double]) -> Double? {
        let sorted = timestamps.sorted()
        let intervals = zip(sorted.dropFirst(), sorted)
            .map { $0 - $1 }
            .filter { $0 > 0 && $0 <= 0.1 }
        guard intervals.count >= 10 else { return nil }
        let median = intervals.sorted()[intervals.count / 2]
        return 1 / median
    }
}
