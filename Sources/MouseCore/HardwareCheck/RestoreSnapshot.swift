import Foundation

/// What the hardware check puts back: the settings MouseBar stored before the check, plus the DPI presets and
/// button remaps the owner entered (the mouse cannot report them). Written to disk before the first test write.
public struct RestoreSnapshot: Codable, Sendable, Equatable {
    /// The mouse group id (`DeviceModel.mouse`), so a snapshot is only restored to the same physical mouse.
    public var mouse: String
    public var stored: [String: SettingValue]
    public var dpiPresets: [Int]
    public var buttons: ButtonMapping

    public init(mouse: String, stored: [String: SettingValue], dpiPresets: [Int], buttons: ButtonMapping) {
        self.mouse = mouse
        self.stored = stored
        self.dpiPresets = dpiPresets
        self.buttons = buttons
    }

    public static let fileName = "check-restore.json"

    public static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName)
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// `nil` when the file is missing or unreadable.
    public static func read(from url: URL) -> RestoreSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RestoreSnapshot.self, from: data)
    }

    /// The writes that put the mouse back, in this order: the owner's buttons, the owner's DPI presets, then every
    /// other setting the check touches (the stored value, or the factory default when MouseBar never stored one).
    /// Use `storesValue(for:family:)` to tell which of them MouseBar should remember.
    public func restoreWrites(family: DeviceFamily) -> [(key: String, value: SettingValue)] {
        var writes: [(key: String, value: SettingValue)] = []
        if family.setting("buttons_mapping") != nil {
            writes.append((key: "buttons_mapping", value: .buttons(buttons)))
        }
        if family.setting("sensitivity") != nil, !dpiPresets.isEmpty {
            writes.append((key: "sensitivity", value: .dpiPresets(presets: dpiPresets, selected: nil)))
        }
        for key in ["polling_rate", "color", "default_lighting"] {
            guard let spec = family.setting(key) else { continue }
            if let value = stored[key] ?? DefaultSettings.value(for: spec) {
                writes.append((key: key, value: value))
            }
        }
        return writes
    }

    /// True when restoring `key` should also remember the value: MouseBar stored it before the check, or the owner
    /// entered a button remap or DPI presets here. A key MouseBar never stored (and the owner did not enter) is written
    /// to the mouse only, so it keeps showing as "Default".
    public func storesValue(for key: String, family: DeviceFamily) -> Bool {
        if stored[key] != nil { return true }
        switch key {
        case "buttons_mapping":
            return !buttons.assignments.isEmpty
        case "sensitivity":
            guard let spec = family.setting(key), case .dpiPresets(let factory, _)? = DefaultSettings.value(for: spec) else {
                return !dpiPresets.isEmpty
            }
            return factory != dpiPresets
        default:
            return false
        }
    }
}
