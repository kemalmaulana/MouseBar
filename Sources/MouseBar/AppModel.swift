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
    private let store = SettingsStore(directory: SettingsStore.defaultDirectory())
    private var manager: DeviceManager?
    private var session: MouseSession?
    private var activeID: UInt64?
    private var available: [ConnectedMouse] = []
    private var started = false

    private init() {
        // Generated and unit-tested data; failing to decode it is a programming error.
        catalog = try! ProfileCatalog.load()
        layouts = try! ButtonLayouts.load()
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
        let errors = await session.start(
            onBattery: { [weak self] state in await self?.setBattery(state) },
            onError: { [weak self] message in await self?.setProblem(message) }
        )
        values = await session.currentValues
        if !errors.isEmpty { problem = errors.joined(separator: "\n") }
    }

    private func setBattery(_ state: BatteryState) { battery = state }
    private func setProblem(_ message: String) { problem = message }

    func submit(_ key: String, _ value: SettingValue) {
        values[key] = value
        guard let session else { return }
        Task { await session.submit(key, value) }
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
