import Testing
@testable import MouseCore

@Suite struct GGDetectorTests {
    @Test func asksForTheEngineProcessByExactName() {
        let asked = Box<String?>(nil)
        let running = GGDetector.isEngineRunning(pgrep: { name in asked.value = name; return true })
        #expect(running)
        #expect(asked.value == "SteelSeriesEngine")
    }

    @Test func reportsNotRunningWhenPgrepFindsNothing() {
        let running = GGDetector.isEngineRunning(pgrep: { _ in false })
        #expect(!running)
    }
}

final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
