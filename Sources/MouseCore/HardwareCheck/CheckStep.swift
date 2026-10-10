import Foundation

/// The hardware check's steps, in the order they run.
public enum CheckStepID: String, CaseIterable, Codable, Sendable {
    case preflight, batteryCable, batteryDongle, ledColor, pollingRate, buttons, dpiPreset, savePersistence, wakeReapply

    public var title: String {
        switch self {
        case .preflight: "Before you start"
        case .batteryCable: "Battery over the cable"
        case .batteryDongle: "Battery over the dongle"
        case .ledColor: "LED color"
        case .pollingRate: "Polling rate"
        case .buttons: "Button remapping"
        case .dpiPreset: "DPI and active preset"
        case .savePersistence: "Saving to the mouse"
        case .wakeReapply: "LED color after wake"
        }
    }
}

public enum StepResult: String, Codable, Sendable {
    case pass, fail, skipped

    public var word: String {
        switch self {
        case .pass: "Passed"
        case .fail: "Failed"
        case .skipped: "Skipped"
        }
    }
}

public struct StepOutcome: Codable, Sendable, Equatable {
    public var step: CheckStepID
    public var result: StepResult
    public var detail: String
    public var rawHex: String?
    public var measurements: [String: Double]

    public init(
        step: CheckStepID, result: StepResult, detail: String,
        rawHex: String? = nil, measurements: [String: Double] = [:]
    ) {
        self.step = step
        self.result = result
        self.detail = detail
        self.rawHex = rawHex
        self.measurements = measurements
    }
}

public enum HexFormat {
    /// `[0x92, 0x94]` -> `"92 94"`.
    public static func string(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
