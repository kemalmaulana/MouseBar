import Testing
@testable import MouseCore

actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

@Suite struct SaveDebouncerTests {
    @Test func manySchedulesCollapseIntoOneAction() async {
        let sleeper = ManualSleeper()
        let counter = Counter()
        let debouncer = SaveDebouncer(delay: .seconds(2), sleeper: sleeper) { await counter.increment() }
        for _ in 0..<5 { await debouncer.schedule() }
        #expect(await waitUntil { await sleeper.waiterCount == 5 })
        await sleeper.releaseAll()
        #expect(await waitUntil { await counter.value == 1 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await counter.value == 1)
    }

    @Test func flushRunsNowAndCancelsTheTimer() async {
        let sleeper = ManualSleeper()
        let counter = Counter()
        let debouncer = SaveDebouncer(delay: .seconds(2), sleeper: sleeper) { await counter.increment() }
        await debouncer.schedule()
        #expect(await waitUntil { await sleeper.waiterCount == 1 })
        await debouncer.flush()
        #expect(await counter.value == 1)
        await sleeper.releaseAll()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await counter.value == 1)
    }

    @Test func flushWithNothingPendingDoesNothing() async {
        let counter = Counter()
        let debouncer = SaveDebouncer(delay: .seconds(2), sleeper: ManualSleeper()) { await counter.increment() }
        await debouncer.flush()
        #expect(await counter.value == 0)
    }

    @Test func scheduleAfterAFireStartsANewCycle() async {
        let sleeper = ManualSleeper()
        let counter = Counter()
        let debouncer = SaveDebouncer(delay: .seconds(2), sleeper: sleeper) { await counter.increment() }
        await debouncer.schedule()
        #expect(await waitUntil { await sleeper.waiterCount == 1 })
        await sleeper.releaseAll()
        #expect(await waitUntil { await counter.value == 1 })
        await debouncer.schedule()
        #expect(await waitUntil { await sleeper.waiterCount == 1 })
        await sleeper.releaseAll()
        #expect(await waitUntil { await counter.value == 2 })
    }
}
