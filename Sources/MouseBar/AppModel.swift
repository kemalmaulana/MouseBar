import Foundation
import MouseCore
import MouseHID
import Observation

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    var battery: BatteryState = .disconnected
    var mouseName: String?
    var family: DeviceFamily?
    var values: [String: SettingValue] = [:]
    var problem: String?
    var ggWarning = false
    let layouts: ButtonLayouts

    private let catalog: ProfileCatalog
    private let store: SettingsStore
    private var manager: DeviceManager?
    private var session: MouseSession?
    private var activeID: UInt64?
    private var available: [ConnectedMouse] = []
    private var started = false
    /// The latest resync per setting key; a newer edit of the same key cancels the older waiter.
    private var resyncTasks: [String: Task<Void, Never>] = [:]

    private init() {
        // Generated and unit-tested data; failing to decode it is a programming error.
        catalog = try! ProfileCatalog.load()
        layouts = try! ButtonLayouts.load()
        // Demo edits must never reach the real store: the demo device shares the real mouse's group id,
        // so they would be re-applied to the real mouse on the next normal launch.
        let directory = CommandLine.arguments.contains("--demo")
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("mousebar-demo-\(UUID().uuidString)", isDirectory: true)
            : SettingsStore.defaultDirectory()
        store = SettingsStore(directory: directory)
    }

    func start() {
        guard !started else { return }
        started = true
        ggWarning = GGDetector.isEngineRunning()
        let transport: any HIDTransport =
            CommandLine.arguments.contains("--demo") ? DemoTransport.make() : IOHIDTransport()
        let manager = DeviceManager(
            transport: transport, catalog: catalog,
            encoder: SettingEncoder(layouts: layouts), sleeper: SystemSleeper()
        )
        self.manager = manager
        Task {
            await manager.start()
            for await event in manager.events {
                await handle(event)
            }
        }
    }

    private func handle(_ event: DeviceEvent) async {
        switch event {
        case .connected(let mouse):
            available.append(mouse)
            await selectActive()
        case .disconnected(let id):
            available.removeAll { $0.hidID == id }
            await selectActive()
        case .openFailed(let info, let message):
            problem = "Could not open \(info.product ?? "the mouse"): \(message). "
                + "If macOS asked for Input Monitoring, allow MouseBar in System Settings → Privacy & Security."
        }
    }

    private func selectActive() async {
        let chosen = ActiveMousePolicy.choose(from: available)
        guard chosen?.hidID != activeID else { return }
        for task in resyncTasks.values { task.cancel() }
        resyncTasks = [:]
        await session?.stop()
        session = nil
        activeID = chosen?.hidID
        values = [:]
        problem = nil
        guard let chosen else {
            battery = .disconnected
            mouseName = nil
            family = nil
            return
        }
        battery = .connecting
        mouseName = chosen.model.name
        family = chosen.family
        let session = MouseSession(
            mouse: chosen, store: store, encoder: SettingEncoder(layouts: layouts), sleeper: SystemSleeper()
        )
        self.session = session
        let id = chosen.hidID
        let errors = await session.start(
            onBattery: { [weak self] state in await self?.setBattery(state, from: id) },
            onError: { [weak self] message in await self?.setProblem(message, from: id) }
        )
        values = await session.currentValues
        if !errors.isEmpty { problem = errors.joined(separator: "\n") }
    }

    // A stopped session can still deliver an already-queued callback; only the active mouse may update the UI.
    private func setBattery(_ state: BatteryState, from id: UInt64) {
        guard id == activeID else { return }
        battery = state
    }

    private func setProblem(_ message: String, from id: UInt64) {
        guard id == activeID else { return }
        problem = message
    }

    func submit(_ key: String, _ value: SettingValue) {
        // Clicking the selected segment or a slider without moving it must not write to the mouse or schedule a save.
        if values[key] != nil && values[key] == value { return }
        problem = nil
        // Optimistic, so controls respond at once; resynced below if the session rejects the edit.
        values[key] = value
        guard let session, let id = activeID else { return }
        resyncTasks[key]?.cancel()
        resyncTasks[key] = Task {
            await session.submit(key, value)
            await session.waitUntilIdle()
            guard !Task.isCancelled else { return }       // a newer edit of this key owns the resync now
            let accepted = await session.currentValues[key]
            // Only this key, only if the mouse is still the active one and no newer optimistic edit landed.
            guard id == activeID && values[key] == value else { return }
            values[key] = accepted
        }
    }

    func resetAll() {
        guard let session else { return }
        Task {
            do {
                try await session.resetAll()
                values = await session.currentValues
            } catch {
                problem = "Reset failed: \(error)"
            }
        }
    }

    func flush() async {
        await session?.flush()
    }
}
