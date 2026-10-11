import Foundation
import MouseCore

/// Turns Logitech receiver hotplug into the same `DeviceEvent`s `DeviceManager` emits for SteelSeries mice.
///
/// The transport only says that *something* on a receiver changed. Mice are found by asking the Rust
/// library (`LogiFFI.enumerate`), so every transport event just schedules one re-enumeration, 500 ms
/// later; events inside that window share it. The transport is never opened: the library talks to the
/// receiver itself.
///
/// All reads and writes of `known` happen inside `pass()`, and passes never overlap (`reconcile()`
/// folds requests that arrive during a pass into one rerun), so a pass can suspend on the library
/// without another pass reordering its view of the known set.
public actor LogitechWatcher {
    public nonisolated let events: AsyncStream<DeviceEvent>
    private let continuation: AsyncStream<DeviceEvent>.Continuation
    private let transport: any HIDTransport

    private struct Known {
        var hidID: UInt64
        var device: LogitechDevice
        /// The mouse was offline, or its settings could not be read, when it was connected.
        var needsSettings: Bool
    }

    private var known: [String: Known] = [:]
    private var transportTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var reconciling = false
    private var rerunRequested = false
    private var reportedFailure = false
    private var stopped = false

    private static let debounce: Duration = .milliseconds(500)
    private static let retryInterval: Duration = .seconds(30)

    public init(transport: any HIDTransport) {
        self.transport = transport
        let made = AsyncStream.makeStream(of: DeviceEvent.self)
        events = made.stream
        continuation = made.continuation
    }

    deinit {
        transportTask?.cancel()
        debounceTask?.cancel()
        retryTask?.cancel()
        continuation.finish()
    }

    /// Starts listening. A watcher that has been stopped stays stopped.
    public func start() {
        guard transportTask == nil, !stopped else { return }
        let stream = transport.events()
        transportTask = Task { [weak self] in
            for await _ in stream {
                await self?.scheduleEnumeration()
            }
        }
    }

    public func stop() async {
        guard !stopped else { return }
        stopped = true
        transportTask?.cancel()
        debounceTask?.cancel()
        retryTask?.cancel()
        transportTask = nil
        debounceTask = nil
        retryTask = nil
        let devices = known.values.map(\.device)
        known.removeAll()
        continuation.finish()
        for device in devices { await device.close() }
    }

    // MARK: - Scheduling

    private func scheduleEnumeration() {
        guard !stopped, debounceTask == nil else { return }
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.debounce)
            } catch {
                return
            }
            await self?.debounceFired()
        }
    }

    private func debounceFired() async {
        guard !Task.isCancelled, !stopped else { return }
        debounceTask = nil
        await reconcile()
    }

    private func retryFired() async {
        guard !Task.isCancelled, !stopped else { return }
        retryTask = nil
        await reconcile()
    }

    /// Keeps the 30 s re-enumeration armed exactly while a known mouse still has no settings.
    private func updateRetryTimer() {
        let needed = !stopped && known.values.contains { $0.needsSettings }
        if !needed {
            retryTask?.cancel()
            retryTask = nil
        } else if retryTask == nil {
            retryTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: Self.retryInterval)
                } catch {
                    return
                }
                await self?.retryFired()
            }
        }
    }

    /// Runs `pass()` and, when another request came in meanwhile, once more. Never two at a time.
    private func reconcile() async {
        if reconciling {
            rerunRequested = true
            return
        }
        reconciling = true
        repeat {
            rerunRequested = false
            await pass()
        } while rerunRequested && !stopped
        reconciling = false
        updateRetryTimer()
    }

    // MARK: - Enumeration

    private func pass() async {
        let found: [LogiDevice]
        do {
            found = try await LogiFFI.enumerate()
        } catch {
            guard !stopped, !reportedFailure else { return }
            reportedFailure = true
            continuation.yield(.openFailed(Self.enumerationFailureInfo, message: String(describing: error)))
            return
        }
        guard !stopped else { return }
        let mice = found.filter { $0.kind == "mouse" }
        let routes = Set(mice.map(\.route))

        // Gone first. `known` changes before any suspension.
        var closing: [LogitechDevice] = []
        for (route, entry) in known where !routes.contains(route) {
            known.removeValue(forKey: route)
            closing.append(entry.device)
            continuation.yield(.disconnected(hidID: entry.hidID))
        }
        for device in closing { await device.close() }

        for mouse in mice {
            guard !stopped else { return }
            if let entry = known[mouse.route] {
                if entry.needsSettings, mouse.online {
                    await upgrade(mouse, replacing: entry)
                }
            } else {
                await add(mouse)
            }
        }
    }

    private func add(_ mouse: LogiDevice) async {
        let settings = mouse.online ? try? await LogiFFI.readSettings(route: mouse.route) : nil
        guard !stopped, known[mouse.route] == nil else { return }
        let hidID = Self.hidID(forRoute: mouse.route)
        let resolved = settings ?? LogiSettings(dpi: nil, reportRate: nil)
        let (family, model) = LogitechFamily.make(device: mouse, settings: resolved)
        let device = LogitechDevice(route: mouse.route, settings: resolved)
        known[mouse.route] = Known(hidID: hidID, device: device, needsSettings: settings == nil)
        continuation.yield(.connected(ConnectedMouse(hidID: hidID, family: family, model: model, device: device)))
    }

    /// A mouse connected without settings answers now: restart its session under the same id.
    private func upgrade(_ mouse: LogiDevice, replacing entry: Known) async {
        guard let settings = try? await LogiFFI.readSettings(route: mouse.route) else { return }
        guard !stopped, let current = known[mouse.route], current.hidID == entry.hidID, current.needsSettings
        else { return }
        let (family, model) = LogitechFamily.make(device: mouse, settings: settings)
        let device = LogitechDevice(route: mouse.route, settings: settings)
        known[mouse.route] = Known(hidID: entry.hidID, device: device, needsSettings: false)
        continuation.yield(.disconnected(hidID: entry.hidID))
        continuation.yield(.connected(ConnectedMouse(hidID: entry.hidID, family: family, model: model, device: device)))
        await entry.device.close()
    }

    // MARK: - Identity

    /// IORegistry entry ids stay below 2^63, so a hash with the top bit set never collides with one.
    static func hidID(forRoute route: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325   // FNV-1a 64-bit offset basis
        for byte in route.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3   // FNV prime
        }
        return hash | (1 << 63)
    }

    /// Stands in for a HID device when an enumeration fails, which has no device of its own.
    private static let enumerationFailureInfo = HIDDeviceInfo(
        id: hidID(forRoute: "logitech-enumeration"), vendorID: 0x046D, productID: 0,
        interfaceNumber: nil, product: "Logitech receiver"
    )
}
