import Foundation

/// Everything the app does with one connected mouse: re-apply saved settings, edit them,
/// save to the device at a safe rate, and report the battery.
public actor MouseSession {
    public let mouse: ConnectedMouse
    private let store: SettingsStore
    private let encoder: SettingEncoder
    private let debouncer: SaveDebouncer
    private let monitor: BatteryMonitor
    private var values: [String: SettingValue] = [:]
    private var monitorTask: Task<Void, Never>?
    private var queued: [String: SettingValue] = [:]
    private var draining = false
    private var onError: (@Sendable (String) async -> Void)?

    public init(
        mouse: ConnectedMouse,
        store: SettingsStore,
        encoder: SettingEncoder,
        sleeper: any Sleeper,
        pollInterval: Duration = .seconds(60),
        saveDelay: Duration = .seconds(2),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.mouse = mouse
        self.store = store
        self.encoder = encoder
        let device = mouse.device
        self.debouncer = SaveDebouncer(delay: saveDelay, sleeper: sleeper) {
            try? await device.save()
        }
        self.monitor = BatteryMonitor(device: device, interval: pollInterval, sleeper: sleeper, now: now)
    }

    public var currentValues: [String: SettingValue] { values }

    /// Re-applies saved values (in profile order) and starts the battery loop.
    /// Returns human-readable errors for values that could not be applied.
    public func start(
        onBattery: @escaping @Sendable (BatteryState) async -> Void,
        onError: @escaping @Sendable (String) async -> Void
    ) async -> [String] {
        self.onError = onError
        values = await store.values(for: mouse.model.mouse)
        var errors: [String] = []
        for spec in mouse.family.settings {
            guard let value = values[spec.key] else { continue }
            do {
                try validate(spec, value)
                try await mouse.device.apply(spec.key, value)
            } catch {
                errors.append("\(spec.label): \(error)")
            }
        }
        let monitor = self.monitor
        monitorTask = Task { await monitor.run(onBattery) }
        return errors
    }

    /// Validates, applies, remembers, and schedules one device save (unless the setting is not stored on the device).
    /// Order matters: an invalid value must never reach the device or the store.
    public func set(_ key: String, _ value: SettingValue) async throws {
        guard let spec = mouse.family.setting(key) else { throw MouseCoreError.unknownSetting(key) }
        try validate(spec, value)
        try await mouse.device.apply(key, value)
        values[key] = value
        try await store.set(value, key: key, mouse: mouse.model.mouse)
        if spec.persistsOnDevice {
            await debouncer.schedule()
        }
    }

    /// Fire-and-forget edit for sliders and color pickers: only the latest value per setting is written.
    public func submit(_ key: String, _ value: SettingValue) {
        queued[key] = value
        guard !draining else { return }
        draining = true
        Task { await self.drain() }
    }

    public func waitUntilIdle() async {
        while draining || !queued.isEmpty {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    /// Applies every factory default, forgets saved choices, and schedules one device save.
    public func resetAll() async throws {
        for spec in mouse.family.settings {
            guard let value = DefaultSettings.value(for: spec) else { continue }
            try await mouse.device.apply(spec.key, value)
        }
        values = [:]
        try await store.clear(mouse: mouse.model.mouse)
        await debouncer.schedule()
    }

    /// Sends a pending device save now (called when the app quits).
    public func flush() async {
        await debouncer.flush()
    }

    public func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    /// Rejects values that must never reach the device (a button remap with no left click).
    /// Used for edits and for saved values re-applied on connect, so a corrupt settings file cannot reach the mouse.
    private func validate(_ spec: SettingSpec, _ value: SettingValue) throws {
        if case .buttons(let mapping) = value {
            try encoder.validateButtons(mapping, spec: spec)
        }
    }

    private func drain() async {
        while let (key, value) = queued.popFirst() {
            do {
                try await set(key, value)
            } catch {
                await onError?("\(key): \(error)")
            }
        }
        draining = false
    }
}
