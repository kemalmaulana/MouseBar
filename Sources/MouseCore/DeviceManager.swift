public struct ConnectedMouse: Sendable {
    public let hidID: UInt64
    public let family: DeviceFamily
    public let model: DeviceModel
    public let device: MouseDevice

    public init(hidID: UInt64, family: DeviceFamily, model: DeviceModel, device: MouseDevice) {
        self.hidID = hidID
        self.family = family
        self.model = model
        self.device = device
    }
}

public enum DeviceEvent: Sendable {
    case connected(ConnectedMouse)
    case disconnected(hidID: UInt64)
    case openFailed(HIDDeviceInfo, message: String)
}

public enum ActiveMousePolicy {
    /// The cable beats the dongle (the mouse is charging and the path is direct); otherwise the earliest.
    public static func choose(from mice: [ConnectedMouse]) -> ConnectedMouse? {
        mice.first(where: { !$0.model.isWireless }) ?? mice.first
    }
}

public actor DeviceManager {
    public nonisolated let events: AsyncStream<DeviceEvent>
    private let continuation: AsyncStream<DeviceEvent>.Continuation
    private let transport: any HIDTransport
    private let catalog: ProfileCatalog
    private let encoder: SettingEncoder
    private let sleeper: any Sleeper
    private var active: [UInt64: ConnectedMouse] = [:]
    private var task: Task<Void, Never>?

    public init(
        transport: any HIDTransport,
        catalog: ProfileCatalog,
        encoder: SettingEncoder,
        sleeper: any Sleeper
    ) {
        self.transport = transport
        self.catalog = catalog
        self.encoder = encoder
        self.sleeper = sleeper
        let made = AsyncStream.makeStream(of: DeviceEvent.self)
        events = made.stream
        continuation = made.continuation
    }

    public func start() {
        guard task == nil else { return }
        let stream = transport.events()
        task = Task { [weak self] in
            for await event in stream {
                await self?.handle(event)
            }
        }
    }

    public func stop() async {
        task?.cancel()
        task = nil
        for mouse in active.values { await mouse.device.close() }
        active.removeAll()
        continuation.finish()
    }

    private func handle(_ event: HIDEvent) async {
        switch event {
        case .added(let info):
            await add(info)
        case .removed(let id):
            guard let mouse = active.removeValue(forKey: id) else { return }
            await mouse.device.close()
            continuation.yield(.disconnected(hidID: id))
        }
    }

    private func add(_ info: HIDDeviceInfo) async {
        guard active[info.id] == nil,
              let match = catalog.match(vendorID: info.vendorID, productID: info.productID),
              info.interfaceNumber == match.model.endpoint
        else { return }
        do {
            let connection = try await transport.open(info)
            let device = MouseDevice(
                family: match.family, model: match.model, connection: connection,
                encoder: encoder, sleeper: sleeper
            )
            let mouse = ConnectedMouse(hidID: info.id, family: match.family, model: match.model, device: device)
            active[info.id] = mouse
            continuation.yield(.connected(mouse))
        } catch {
            continuation.yield(.openFailed(info, message: String(describing: error)))
        }
    }
}
