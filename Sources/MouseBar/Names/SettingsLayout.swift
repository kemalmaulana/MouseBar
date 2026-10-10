import SwiftUI
import MouseCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case performance, buttons, lighting, power, device

    var id: String { rawValue }

    var title: String {
        switch self {
        case .performance: "Performance"
        case .buttons: "Buttons"
        case .lighting: "Lighting"
        case .power: "Power"
        case .device: "Device"
        }
    }

    var symbol: String {
        switch self {
        case .performance: "speedometer"
        case .buttons: "computermouse"
        case .lighting: "lightbulb"
        case .power: "powersleep"
        case .device: "info.circle"
        }
    }
}

/// App-side presentation of profile settings: which tab, which order, which friendly label.
/// Settings the table doesn't know appear in the Device tab's "Other" section, so the UI stays data-driven.
enum SettingsLayout {
    struct Entry {
        let tab: SettingsTab
        let order: Int
        let label: String
    }

    static let entries: [String: Entry] = [
        "sensitivity": Entry(tab: .performance, order: 0, label: "DPI presets"),
        "polling_rate": Entry(tab: .performance, order: 1, label: "Polling rate"),
        "buttons_mapping": Entry(tab: .buttons, order: 0, label: "Buttons"),
        "color": Entry(tab: .lighting, order: 0, label: "LED color"),
        "default_lighting": Entry(tab: .lighting, order: 1, label: "Startup lighting"),
        "dim_timer": Entry(tab: .lighting, order: 2, label: "Dim LED after"),
        "sleep_timer": Entry(tab: .power, order: 0, label: "Sleep after"),
    ]

    static func settings(for tab: SettingsTab, in family: DeviceFamily) -> [SettingSpec] {
        family.settings
            .filter { entries[$0.key]?.tab == tab }
            .sorted { (entries[$0.key]?.order ?? 0) < (entries[$1.key]?.order ?? 0) }
    }

    static func otherSettings(in family: DeviceFamily) -> [SettingSpec] {
        family.settings.filter { entries[$0.key] == nil }
    }

    static func label(for spec: SettingSpec) -> String {
        entries[spec.key]?.label ?? spec.label
    }
}

/// Values with units, as shown next to controls.
enum ValueFormat {
    static func dpi(_ value: Int) -> String { "\(value) DPI" }

    /// Segment labels: "1000 Hz" for the polling rate, "Off" / "Rainbow" for the rest.
    static func choice(key: String, _ choice: String) -> String {
        key == "polling_rate" ? "\(choice) Hz" : choice.capitalized
    }

    /// "Off", "30 s", "1 min", "1 min 30 s".
    static func seconds(_ value: Int) -> String {
        if value == 0 { return "Off" }
        if value < 60 { return "\(value) s" }
        let minutes = value / 60
        let rest = value % 60
        return rest == 0 ? "\(minutes) min" : "\(minutes) min \(rest) s"
    }

    static func range(key: String, value: Int) -> String {
        switch key {
        case "sleep_timer": value == 0 ? "Never" : "\(value) min"
        case "dim_timer": seconds(value)
        default: "\(value)"
        }
    }
}
