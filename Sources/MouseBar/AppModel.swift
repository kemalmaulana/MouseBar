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
    static let steelSeriesVendorID = 0x1038
    static let logitechVendorID = 0x046D

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
    /// Display names of vendor apps running now that can fight MouseBar (`ConflictDetector`); checked once at launch.
    private(set) var conflictingApps: [String] = []
    var connection: ConnectionKind?
    /// The distinct physical mice connected right now, for the panel's picker.
    private(set) var mice: [MouseChoice] = []
    /// `DeviceModel.mouse` of the active mouse.
    private(set) var activeMouseID: String?
    /// Settings the active mouse reports itself: their values are live, so no "Default" capsule.
    private(set) var readableKeys: Set<String> = []
    var saveState: SaveState?
    /// `DeviceModel.vendorId` of the active mouse.
    private(set) var activeVendorID: Int?
    /// OpenLogi's short revision, once `LogiFFI.version()` has answered; nil in demo mode.
    private(set) var logiRevision: String?
    /// True while the hardware check runs; Settings and the panel's quick controls are disabled.
    private(set) var isCheckRunning = false
    /// `DeviceModel.mouse` of the mouse a running hardware check tests (from its snapshot); nil when no check runs.
    private var checkedMouse: String?
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
    private var logiVersionRequested = false
    /// The banner of the last failed Logitech enumeration, cleared from `problem` once a Logitech mouse arrives.
    private var receiverProblem: String?
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
    /// True when GG's engine runs (the hardware check's welcome card warns about it).
    var ggWarning: Bool { conflictingApps.contains(ConflictDetector.steelSeriesGG) }
    /// The hardware check is for SteelSeries mice only; with no mouse connected there is nothing to hide it for.
    var supportsHardwareCheck: Bool { activeVendorID.map { $0 == Self.steelSeriesVendorID } ?? true }

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
        // Each check spawns pgrep, so keep it off the main thread.
        Task {
            conflictingApps = await Task.detached(priority: .utility) { ConflictDetector.runningApps() }.value
        }
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
                await forwardLogitech(watcher.events, to: inputs)
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

    /// A Logitech mouse whose settings arrive late is reported as `.disconnected(id)` and at once `.connected` with the
    /// same id. Passing both on would make another mouse active in between (and re-apply its settings), so the
    /// pair becomes the lone `.connected`, which `handle` applies in place. A disconnect that no connect follows
    /// within a moment is a real one and goes on unchanged.
    private func forwardLogitech(_ events: AsyncStream<DeviceEvent>, to inputs: AsyncStream<Input>.Continuation) async {
        var held: UInt64?
        var release: Task<Void, Never>?
        func flush() {
            release?.cancel()
            release = nil
            guard let id = held else { return }
            held = nil
            inputs.yield(.device(.disconnected(hidID: id)))
        }
        for await event in events {
            if case .connected(let mouse) = event, mouse.hidID == held {
                release?.cancel()
                release = nil
                held = nil
                inputs.yield(.device(event))
                continue
            }
            flush()
            if case .disconnected(let id) = event {
                held = id
                release = Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    if !Task.isCancelled { flush() }
                }
            } else {
                inputs.yield(.device(event))
            }
        }
        flush()
    }

    /// Makes `id` (a `DeviceModel.mouse`) the active mouse and remembers the choice.
    func selectMouse(_ id: String) {
        guard mice.contains(where: { $0.id == id }) else { return }
        preferredMouse = id
        // A demo run must not change which mouse the real app picks.
        if !Self.isDemo { UserDefaults.standard.set(id, forKey: Self.activeMouseKey) }
        inputs?.yield(.reselect)
    }

    /// Called by the hardware check, with the checked mouse (the snapshot's `DeviceModel.mouse`) when it starts.
    /// While it runs, `selectActive` only picks that mouse. When it ends, the preferred mouse is looked at again:
    /// it may have connected meanwhile, and `selectActive` kept the checked mouse (or none) until now.
    func setCheckRunning(_ running: Bool, mouse: String? = nil) {
        let ended = isCheckRunning && !running
        isCheckRunning = running
        checkedMouse = running ? mouse : nil
        // The check starts on its snapshot's mouse; if another one became active in between, switch back (or to none).
        if ended || (running && activeMouseID != mouse) { inputs?.yield(.reselect) }
    }

    /// True when the UI shows the factory default: MouseBar never set the value and the mouse can't report it.
    func isFactoryDefault(_ key: String) -> Bool {
        values[key] == nil && !readableKeys.contains(key)
    }

    private func handle(_ event: DeviceEvent) async {
        switch event {
        case .connected(let mouse):
            // A Logitech mouse arrived, so the receiver answers again: its earlier failure banner is stale.
            if mouse.model.vendorId == Self.logitechVendorID, let stale = receiverProblem {
                if problem == stale { problem = nil }
                receiverProblem = nil
            }
            // The same mouse again (its settings arrived late): swap it in place, keep its position, and restart
            // only its own session, if it is the active one.
            var replaced: UInt64?
            if let index = available.firstIndex(where: { $0.hidID == mouse.hidID }) {
                available[index] = mouse
                replaced = mouse.hidID
            } else {
                available.append(mouse)
            }
            mice = Self.distinctMice(available)
            await selectActive(restarting: replaced)
        case .disconnected(let id):
            available.removeAll { $0.hidID == id }
            mice = Self.distinctMice(available)
            await selectActive()
        case .openFailed(let info, let message):
            if info.vendorID == Self.logitechVendorID {
                // The Logitech watcher opens no device itself (no Input Monitoring): its enumeration failed or timed
                // out, often because another Logitech app holds the receiver. The watcher retries on its own.
                let banner = "Could not read the Logitech receiver: \(message). Quit Logitech G HUB, Logi Options+ "
                    + "or OpenLogi if they are running, then unplug and replug the receiver."
                problem = banner
                receiverProblem = banner
            } else {
                problem = "Could not open \(info.product ?? "the mouse"): \(message). "
                    + "If macOS asked for Input Monitoring, allow MouseBar in System Settings → Privacy & Security."
            }
        }
    }

    private static func distinctMice(_ available: [ConnectedMouse]) -> [MouseChoice] {
        var seen = Set<String>()
        return available.compactMap { mouse in
            guard seen.insert(mouse.model.mouse).inserted else { return nil }
            return MouseChoice(id: mouse.model.mouse, name: shortName(mouse.model.name))
        }
    }

    private func selectActive(restarting replaced: UInt64? = nil) async {
        // A running hardware check owns its mouse: only the checked mouse (over cable or dongle) can be active. With
        // it gone no mouse is active, so the check waits for it; another mouse never takes over and never gets the
        // check's connection, battery or values.
        let chosen = if isCheckRunning, let checkedMouse {
            ActiveMousePolicy.choose(from: available.filter { $0.model.mouse == checkedMouse }, preferred: nil)
        } else {
            ActiveMousePolicy.choose(from: available, preferred: preferredMouse)
        }
        guard chosen?.hidID != activeID || (replaced != nil && replaced == activeID) else { return }
        for task in resyncTasks.values { task.cancel() }
        resyncTasks = [:]
        await session?.stop()
        session = nil
        activeID = chosen?.hidID
        activeMouseID = chosen?.model.mouse
        activeVendorID = chosen?.model.vendorId
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
        if chosen.model.vendorId == Self.logitechVendorID { loadLogiRevision() }
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
            // Only the checked mouse polls fast (for a Logitech mouse every poll is a full receiver enumeration).
            if chosen.model.mouse == checkedMouse { await session.setPollInterval(.seconds(5)) }
        } else {
            // A check interrupted by a crash or force quit left a snapshot: put the owner's settings back once.
            await CheckRunner.shared.restoreIfInterrupted()
        }
    }

    /// Fetches OpenLogi's revision once, for the Device tab. Demo mode never calls the library. The call is queued
    /// behind any enumeration on the library's own queue, so it runs in a task and the Device tab shows "—" meanwhile.
    private func loadLogiRevision() {
        guard !Self.isDemo, logiRevision == nil, !logiVersionRequested else { return }
        logiVersionRequested = true
        Task {
            if let version = try? await LogiFFI.version() {
                logiRevision = String(version.openlogiRev.prefix(7))
            } else {
                logiVersionRequested = false   // try again the next time a Logitech mouse becomes active
            }
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

    /// SteelSeries only: a Logitech mouse has no factory reset here (Device tab offers `forgetSettings` instead).
    func resetAll() {
        guard let session, activeVendorID != Self.logitechVendorID else { return }
        Task {
            do {
                try await session.resetAll()
                values = await session.currentValues
            } catch {
                problem = "Reset failed: \(error)"
            }
        }
    }

    /// Logitech's "Forget MouseBar's settings for this mouse": clears what MouseBar stored for the active mouse so it
    /// is no longer re-applied. Nothing is written to the mouse and nothing is saved; Settings then shows what the
    /// mouse reports.
    func forgetSettings() {
        guard let session, let id = activeID else { return }
        // A pending resync would put a forgotten optimistic value back on screen.
        for task in resyncTasks.values { task.cancel() }
        resyncTasks = [:]
        problem = nil
        Task {
            do {
                try await session.forgetSavedSettings()
            } catch {
                if id == activeID { problem = "Could not forget the settings: \(error)" }
                return
            }
            let current = await session.currentValues
            let readable = await session.readableKeys
            guard id == activeID else { return }   // another mouse became active meanwhile
            values = current
            readableKeys = readable
        }
    }

    func flush() async {
        await session?.flush()
    }
}
