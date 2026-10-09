/// Collapses bursts of edits into one device save (the mouse's memory has limited write cycles).
public actor SaveDebouncer {
    private let delay: Duration
    private let sleeper: any Sleeper
    private let action: @Sendable () async -> Void
    private var generation = 0
    private var pending = false

    public init(delay: Duration, sleeper: any Sleeper, action: @escaping @Sendable () async -> Void) {
        self.delay = delay
        self.sleeper = sleeper
        self.action = action
    }

    public func schedule() {
        generation += 1
        pending = true
        let mine = generation
        Task { [delay, sleeper] in
            await sleeper.sleep(for: delay)
            await self.fire(ifGeneration: mine)
        }
    }

    /// Runs the action now if a save is pending (used on quit).
    public func flush() async {
        guard pending else { return }
        pending = false
        generation += 1
        await action()
    }

    private func fire(ifGeneration value: Int) async {
        guard pending, value == generation else { return }
        pending = false
        await action()
    }
}
