import Foundation

/// The mouse is write-only, so we remember what the user chose and re-apply it on connect.
public actor SettingsStore {
    private struct File: Codable {
        var version = 1
        var values: [String: SettingValue] = [:]
    }

    private let directory: URL
    private var cache: [String: File] = [:]

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MouseBar", isDirectory: true)
    }

    public func values(for mouse: String) -> [String: SettingValue] {
        load(mouse).values
    }

    public func set(_ value: SettingValue, key: String, mouse: String) throws {
        var file = load(mouse)
        file.values[key] = value
        try write(file, mouse: mouse)
    }

    public func clear(mouse: String) throws {
        try write(File(), mouse: mouse)
    }

    private func url(for mouse: String) -> URL {
        let safe = String(mouse.unicodeScalars.map { scalar in
            (scalar.properties.isAlphabetic && scalar.isASCII) || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-"
                ? Character(scalar) : "_"
        })
        return directory.appendingPathComponent("\(safe).json")
    }

    private func load(_ mouse: String) -> File {
        if let cached = cache[mouse] { return cached }
        let file = (try? Data(contentsOf: url(for: mouse)))
            .flatMap { try? JSONDecoder().decode(File.self, from: $0) } ?? File()
        cache[mouse] = file
        return file
    }

    private func write(_ file: File, mouse: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url(for: mouse), options: .atomic)
        cache[mouse] = file
    }
}

public enum DefaultSettings {
    /// The factory value of a setting, as rivalcfg's `--reset` would apply it.
    public static func value(for spec: SettingSpec) -> SettingValue? {
        switch spec.valueType {
        case "choice":
            return .choice(spec.defaultText)
        case "range":
            return Int(spec.defaultText).map(SettingValue.int)
        case "rgbcolor":
            return RGBColor(parsing: spec.defaultText).map(SettingValue.color)
        case "multidpi_range_choice":
            let presets = spec.defaultText
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return presets.isEmpty ? nil : .dpiPresets(presets: presets, selected: nil)
        case "buttons":
            return .buttons(ButtonMapping())
        default:
            return nil
        }
    }
}
