/// Progress of a save to the mouse's own memory, reported to the app for feedback.
public enum SaveState: Equatable, Sendable {
    case saving
    case saved
    case failed(String)
}

/// Holds the app's save observer (set after the session is created) and runs saves through it.
actor SaveReporter {
    private var observer: (@Sendable (SaveState) async -> Void)?

    func setObserver(_ observer: (@Sendable (SaveState) async -> Void)?) {
        self.observer = observer
    }

    /// Runs one save, reporting `.saving` then `.saved` or `.failed`, and rethrows the failure.
    func run(_ save: @Sendable () async throws -> Void) async throws {
        await observer?(.saving)
        do {
            try await save()
            await observer?(.saved)
        } catch {
            await observer?(.failed(String(describing: error)))
            throw error
        }
    }
}
