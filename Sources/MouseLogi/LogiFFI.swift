import Foundation
import MouseBarLogiFFI

/// Async Swift face of the Rust Logitech library.
///
/// The C calls can block for seconds and the library serializes them process-wide anyway, so every
/// call runs on one private serial queue and never on the caller's thread. Each reply is copied
/// out of the C string, the C string is freed exactly once, and the JSON is decoded.
public enum LogiFFI {
    private static let queue = DispatchQueue(label: "mousebar.logi.ffi")

    public static func version() async throws -> LogiVersion {
        try await require(LogiVersion.self) { mb_logi_version() }
    }

    public static func enumerate() async throws -> [LogiDevice] {
        try await require([LogiDevice].self) { mb_logi_enumerate() }
    }

    public static func readSettings(route: String) async throws -> LogiSettings {
        try await require(LogiSettings.self) {
            route.withCString { mb_logi_read_settings($0) }
        }
    }

    /// nil when the mouse is offline or the route matches no device.
    public static func readBattery(route: String) async throws -> LogiBattery? {
        try await call(LogiBattery.self) {
            route.withCString { mb_logi_read_battery($0) }
        }
    }

    /// Writes to the hardware.
    public static func setDPI(route: String, dpi: Int) async throws {
        guard let value = UInt32(exactly: dpi) else {
            throw LogiError.device("\(dpi) DPI is outside the range the Logitech library accepts.")
        }
        _ = try await call(Empty.self) {
            route.withCString { mb_logi_set_dpi($0, value) }
        }
    }

    /// Writes to the hardware.
    public static func setReportRate(route: String, intervalMs: Int) async throws {
        guard let value = UInt8(exactly: intervalMs) else {
            throw LogiError.device("A \(intervalMs) ms report interval is outside the range the Logitech library accepts.")
        }
        _ = try await call(Empty.self) {
            route.withCString { mb_logi_set_report_rate($0, value) }
        }
    }

    // MARK: - Plumbing

    /// Payload of `{"ok": null}` replies that carry no value.
    private struct Empty: Decodable, Sendable {}

    /// `{"ok": <value>}` or `{"error": "<message>"}`. `.ok(nil)` is a successful `{"ok": null}`.
    private enum Reply<Value: Decodable>: Decodable {
        case ok(Value?)
        case failure(String)

        private enum Key: String, CodingKey { case ok, error }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            if container.contains(.error) {
                self = .failure(try container.decode(String.self, forKey: .error))
            } else if container.contains(.ok) {
                self = .ok(try container.decodeIfPresent(Value.self, forKey: .ok))
            } else {
                throw DecodingError.keyNotFound(
                    Key.ok,
                    .init(codingPath: container.codingPath, debugDescription: "Reply has neither \"ok\" nor \"error\".")
                )
            }
        }
    }

    /// Like `call`, for replies that must carry a value.
    private static func require<Value: Decodable & Sendable>(
        _ type: Value.Type,
        _ body: @escaping @Sendable () -> UnsafeMutablePointer<CChar>?
    ) async throws -> Value {
        guard let value = try await call(type, body) else {
            throw LogiError.decoding("Expected a value but the reply was null.")
        }
        return value
    }

    /// Runs `body` (one C call) on the serial queue and decodes its reply.
    private static func call<Value: Decodable & Sendable>(
        _ type: Value.Type,
        _ body: @escaping @Sendable () -> UnsafeMutablePointer<CChar>?
    ) async throws -> Value? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try decodeReply(type, raw: body()) })
            }
        }
    }

    private static func decodeReply<Value: Decodable>(
        _ type: Value.Type,
        raw: UnsafeMutablePointer<CChar>?
    ) throws -> Value? {
        guard let raw else { throw LogiError.decoding("The library returned no reply.") }
        let text = String(cString: raw)
        mb_logi_free(raw)
        do {
            switch try JSONDecoder().decode(Reply<Value>.self, from: Data(text.utf8)) {
            case .ok(let value): return value
            case .failure(let message): throw LogiError.device(message)
            }
        } catch let error as DecodingError {
            throw LogiError.decoding(String(describing: error))
        }
    }
}
