import Foundation

// Shapes of the JSON the Rust library returns (Rust/mousebar-logi/include/mousebar_logi.h).
// Keys are mapped with explicit CodingKeys, not a decoder strategy, so the mapping is visible here.

public struct LogiVersion: Codable, Sendable, Equatable {
    public var crate: String
    public var openlogiRev: String

    public init(crate: String, openlogiRev: String) {
        self.crate = crate
        self.openlogiRev = openlogiRev
    }

    private enum CodingKeys: String, CodingKey {
        case crate
        case openlogiRev = "openlogi_rev"
    }
}

public struct LogiBattery: Codable, Sendable, Equatable {
    public var percent: Int
    public var charging: Bool

    public init(percent: Int, charging: Bool) {
        self.percent = percent
        self.charging = charging
    }

    private enum CodingKeys: String, CodingKey {
        case percent
        case charging
    }
}

public struct LogiDevice: Codable, Sendable, Equatable {
    /// Opaque handle for the other calls. Not stable across enumerations of different receivers.
    public var route: String
    public var receiverName: String
    public var receiverProductID: Int
    public var slot: Int
    public var wpid: Int?
    public var codename: String?
    public var kind: String
    public var online: Bool
    public var battery: LogiBattery?

    public init(
        route: String, receiverName: String, receiverProductID: Int, slot: Int,
        wpid: Int?, codename: String?, kind: String, online: Bool, battery: LogiBattery?
    ) {
        self.route = route
        self.receiverName = receiverName
        self.receiverProductID = receiverProductID
        self.slot = slot
        self.wpid = wpid
        self.codename = codename
        self.kind = kind
        self.online = online
        self.battery = battery
    }

    private enum CodingKeys: String, CodingKey {
        case route
        case receiverName = "receiver_name"
        case receiverProductID = "receiver_product_id"
        case slot
        case wpid
        case codename
        case kind
        case online
        case battery
    }
}

public struct LogiDPI: Codable, Sendable, Equatable {
    public var current: Int
    public var supported: [Int]

    public init(current: Int, supported: [Int]) {
        self.current = current
        self.supported = supported
    }

    private enum CodingKeys: String, CodingKey {
        case current
        case supported
    }
}

public struct LogiReportRate: Codable, Sendable, Equatable {
    public var currentMs: Int
    public var supportedMs: [Int]

    public init(currentMs: Int, supportedMs: [Int]) {
        self.currentMs = currentMs
        self.supportedMs = supportedMs
    }

    private enum CodingKeys: String, CodingKey {
        case currentMs = "current_ms"
        case supportedMs = "supported_ms"
    }
}

public struct LogiSettings: Codable, Sendable, Equatable {
    /// nil when the mouse does not report an adjustable DPI.
    public var dpi: LogiDPI?
    /// nil when the mouse does not report an adjustable report rate.
    public var reportRate: LogiReportRate?

    public init(dpi: LogiDPI?, reportRate: LogiReportRate?) {
        self.dpi = dpi
        self.reportRate = reportRate
    }

    private enum CodingKeys: String, CodingKey {
        case dpi
        case reportRate = "report_rate"
    }
}

public enum LogiError: Error, CustomStringConvertible {
    /// The library answered `{"error": "<message>"}`.
    case device(String)
    /// The reply was missing, not JSON, or not the expected shape.
    case decoding(String)

    public var description: String {
        switch self {
        case .device(let message): message
        case .decoding(let message): "Unreadable reply from the Logitech library: \(message)"
        }
    }
}
