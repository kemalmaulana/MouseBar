public struct HIDDeviceInfo: Sendable, Hashable {
    /// IORegistry entry id on macOS; unique per HID interface while it is plugged in.
    public var id: UInt64
    public var vendorID: Int
    public var productID: Int
    public var interfaceNumber: Int?
    public var usagePage: Int
    public var usage: Int
    public var product: String?

    public init(
        id: UInt64, vendorID: Int, productID: Int, interfaceNumber: Int?,
        usagePage: Int = 0, usage: Int = 0, product: String? = nil
    ) {
        self.id = id
        self.vendorID = vendorID
        self.productID = productID
        self.interfaceNumber = interfaceNumber
        self.usagePage = usagePage
        self.usage = usage
        self.product = product
    }
}

public enum HIDEvent: Sendable {
    case added(HIDDeviceInfo)
    case removed(UInt64)
}

public enum HIDError: Error, Equatable, Sendable {
    case openFailed(code: Int32)
    case writeFailed(code: Int32)
    case notOpen
    case simulated(String)
}

public protocol HIDConnection: Sendable {
    /// Sends one output report. The payload excludes the report id (report id 0 is implicit).
    func write(_ payload: [UInt8]) async throws
    /// Waits for one input report; `nil` on timeout. The report is truncated to `length`.
    func read(length: Int, timeout: Duration) async throws -> [UInt8]?
    /// Drops queued input reports so the next read sees only fresh data.
    func flushInput() async
    func close() async
}

public protocol HIDTransport: Sendable {
    /// Emits `.added` for every matching device already present, then live changes.
    func events() -> AsyncStream<HIDEvent>
    func open(_ device: HIDDeviceInfo) async throws -> any HIDConnection
}
