import Foundation
import MouseCore
import MouseHID
import MouseLogi
import Observation

/// One physical mouse in the panel's picker (a SteelSeries mouse over cable and dongle is one entry).
struct MouseChoice: Identifiable, Equatable {
    /// `DeviceModel.mouse`.
    let id: String
    let name: String
}

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    static let isDemo = CommandLine.arguments.contains("--demo")
    private static let activePresetKey = "activePresetConfirmed"
    private static let activeMouseKey = "activeMouse"

    enum ConnectionKind: Equatable {
        case cable, dongle

        var title: String { self == .cable ? "Cable" : "2.4 GHz" }
        var symbol: String { self == .cable ? Theme.Symbol.cable : Theme.Symbol.dongle }
    }

    var battery: BatteryState = .disconnected
    var mouseName: String?
    var family: DeviceFamily?
    var values: [String: SettingValue] = [:]
    var problem: String?
    var notice: String?
    var ggWarning = false
    var connection: ConnectionKind?
    /// The distinct physical mice connected right now, for the panel's picker.
    private(set) var mice: [MouseChoice] = []
    /// `DeviceModel.mouse` of the active mouse.
    private(set) var activeMouseID: String?
    /// Settings the active mouse reports itself: their values are live, so no "Default" capsule.
    private(set) var readableKeys: Set<String> = []
    var saveState: SaveState?
    /// True while the hardware check runs; Settings and the panel's quick controls are disabled.
    var isCheckRunning = false
    /// Set by the hardware check when switching the active DPI preset was confirmed on the mouse.
    private(set) var activePresetConfirmed: Bool
    let layouts: ButtonLayouts
    let settingsDirectory: URL

    private let catalog: ProfileCatalog
    private let store: SettingsStore
    private var manager: DeviceManager?
    private var logitech: LogitechWatcher?
    private var session: MouseSession?
    private var activeID: UInt64?
    private var available: [ConnectedMouse] = []
    /// The mouse the owner picked; kept in `UserDefaults` outside demo mode.
    private var preferredMouse: String?
    /// Feeds the one loop that handles every backend's events and every picker choice, one at a time.
    private var inputs: AsyncStream<Input>.Continuation?
    private var started = false
    /// The latest resync per setting key; a newer edit of the same key cancels the older waiter.
    private var resyncTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var saveClearTask: Task<Void, Never>?

    private init() {
        // Generated and unit-tested data; failing to decode it is a programming error.
        catalog = try! ProfileCatalog.load()
        layouts = try! ButtonLayouts.load()
        // Demo edits must never reach the real store: the demo device shares the real mouse's group id,
        // so they would be re-applied to the real mouse on the next normal launch.
        let directory = Self.isDemo
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("mousebar-demo-\(UUID().uuidString)", isDirectory: true)
            : SettingsStore.defaultDirectory()
        settingsDirectory = directory
        store = SettingsStore(directory: directory)
        activePresetConfirmed = Self.isDemo ? false : UserDefaults.standard.bool(forKey: Self.activePresetKey)
        preferredMouse = Self.isDemo ? nil : UserDefaults.standard.string(forKey: Self.activeMouseKey)
    }

    private enum Input: Sendable {
        case device(DeviceEvent)
        /// The picker changed `preferredMouse`.
        case reselect
    }

    /// "SteelSeries Prime Mini Wireless (2.4 GHz wireless mode)" -> "Prime Mini Wireless".
    var displayName: String? { mouseName.map(Self.shortName) }
    var rivalcfgVersion: String { catalog.rivalcfgVersion }
    /// The session of the active mouse (the hardware check drives it directly).
    var activeSession: MouseSession? { session }

    static func shortName(_ name: String) -> String {
        var result = name
        if let paren = result.firstIndex(of: "(") {
            result = String(result[..<paren]).trimmingCharacters(in: .whitespaces)
        }
        if result.hasPrefix("SteelSeries ") {
            result.removeFirst("SteelSeries ".count)
        }
        return result
    }

    func setActivePresetConfirmed(_ confirmed: Bool) {
        activePresetConfirmed = confirmed
        // A demo run must not unlock the DPI picker for the real mouse.
        if !Self.isDemo { UserDefaults.standard.set(confirmed, forKey: Self.activePresetKey) }
    }

    func refreshValues() async {
        values = await session?.currentValues ?? [:]
    }

    func start() {
        guard !started else { return }
        started = true
        ggWarning = GGDetector.isEngineRunning()
        // Every backend and the picker feed one stream that one loop drains. Handling an input suspends
        // (a session stops and starts), so separate loops could interleave and race on the active mouse.
        let (stream, inputs) = AsyncStream.makeStream(of: Input.self)
        self.inputs = inputs
        let transport: any HIDTransport = Self.isDemo ? DemoTransport.make() : IOHIDTransport()
        let manager = DeviceManager(
            transport: transport, catalog: catalog,
            encoder: SettingEncoder(layouts: layouts), sleeper: SystemSleeper()
        )
        self.manager = manager
        Task {
            await manager.start()
            var simulatedAdded = false
            for await event in manager.events {
                inputs.yield(.device(event))
                // Demo only: a simulated G304 joins right after the simulated SteelSeries mouse,
                // so the SteelSeries one is the active mouse first and the picker has two entries.
                if Self.isDemo, !simulatedAdded, case .connected = event {
                    simulatedAdded = true
                    inputs.yield(.device(.connected(SimulatedLogitechDevice.connectedMouse())))
                }
            }
        }
        if !Self.isDemo {
            // The vendor-defined HID++ interface of Logitech receivers. Matching does not open a device.
            let watcher = LogitechWatcher(transport: IOHIDTransport(vendorID: 0x046D, usagePage: 0xFF00))
            logitech = watcher
            Task {
                await watcher.start()
                for await event in watcher.events {
                    inputs.yield(.device(event))
                }
            }
        }
        Task {
            for await input in stream {
                switch input {
                case .device(let event): await handle(event)
                case .reselect: await selectActive()
                }
            }
        }
    }

    /// Makes `id` (a `DeviceModel.mouse`) the active mouse and remembers the choice.
    func selectMouse(_ id: String) {
        guard mice.contains(where: { $0.id == id }) else { return }
        preferredMouse = id
        // A demo run must not change which mouse the real app picks.
        if !Self.isDemo { UserDefaults.standard.set(id, forKey: Self.activeMouseKey) }
        inputs?.yield(.reselect)
    }

    /// True when the UI shows the factory default: MouseBar never set the value and the mouse can't report it.
    func isFactoryDefault(_ key: String) -> Bool {
        values[key] == nil && !readableKeys.contains(key)
    }

    private func handle(_ event: DeviceEvent) async {
        switch event {
        case .connected(let mouse):
            available.append(mouse)
            mice = Self.distinctMice(available)
            await selectActive()
        case .disconnected(let id):
            available.removeAll { $0.hidID == id }
            mice = Self.distinctMice(available)
            await selectActive()
        case .openFailed(let info, let message):
            problem = "Could not open \(info.product ?? "the mouse"): \(message). "
                + "If macOS asked for Input Monitoring, allow MouseBar in System Settings → Privacy & Security."
        }
    }

    private static func distinctMice(_ available: [ConnectedMouse]) -> [MouseChoice] {
        var seen = Set<String>()
        return available.compactMap { mouse in
            guard seen.insert(mouse.model.mouse).inserted else { return nil }
            return MouseChoice(id: mouse.model.mouse, name: shortName(mouse.model.name))
        }
    }

    private func selectActive() async {
        let chosen = ActiveMousePolicy.choose(from: available, preferred: preferredMouse)
        guard chosen?.hidID != activeID else { return }
        for task in resyncTasks.values { task.cancel() }
        resyncTasks = [:]
        await session?.stop()
        session = nil
        activeID = chosen?.hidID
        activeMouseID = chosen?.model.mouse
        values = [:]
        readableKeys = []
        problem = nil
        saveState = nil
        guard let chosen else {
            battery = .disconnected
            mouseName = nil
            family = nil
            connection = nil
            return
        }
        battery = .connecting
        mouseName = chosen.model.name
        family = chosen.family
        connection = chosen.model.isWireless ? .dongle : .cable
        let session = MouseSession(
            mouse: chosen, store: store, encoder: SettingEncoder(layouts: layouts), sleeper: SystemSleeper()
        )
        self.session = session
        let id = chosen.hidID
        await session.setSaveObserver { [weak self] state in await self?.setSaveState(state, from: id) }
        let errors = await session.start(
            onBattery: { [weak self] state in await self?.setBattery(state, from: id) },
            onError: { [weak self] message in await self?.setProblem(message, from: id) }
        )
        values = await session.currentValues
        readableKeys = await session.readableKeys
        if !errors.isEmpty { problem = errors.joined(separator: "\n") }
        if isCheckRunning {
            // The check switched connections (cable <-> dongle): keep its fast battery polling on the new session.
            await session.setPollInterval(.seconds(5))
        } else {
            // A check interrupted by a crash or force quit left a snapshot: put the owner's settings back once.
            await CheckRunner.shared.restoreIfInterrupted()
        }
    }

    // A stopped session can still deliver an already-queued callback; only the active mouse may update the UI.
    private func setBattery(_ state: BatteryState, from id: UInt64) {
        guard id == activeID else { return }
        let wasFresh = battery.freshness == .fresh
        battery = state
        // A restore kept because the mouse was asleep or silent is retried as soon as it answers again.
        if !wasFresh && state.freshness == .fresh && !isCheckRunning && CheckRunner.shared.needsRestore {
            Task { await CheckRunner.shared.restoreIfInterrupted() }
        }
    }

    private func setProblem(_ message: String, from id: UInt64) {
        guard id == activeID else { return }
        problem = message
    }

    private func setSaveState(_ state: SaveState, from id: UInt64) {
        guard id == activeID else { return }
        saveClearTask?.cancel()
        switch state {
        case .saving:
            saveState = .saving
        case .saved:
            saveState = .saved
            saveClearTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.saveState = nil
            }
        case .failed(let message):
            saveState = nil
            problem = "Could not save to the mouse: \(message)"
        }
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
