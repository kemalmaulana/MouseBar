import MouseCore

/// Friendly names for the profile's button names and action tokens (all lowercased in mappings).
enum ButtonNames {
    static let buttons: [String: String] = [
        "button1": "Left click",
        "button2": "Right click",
        "button3": "Middle click",
        "button4": "Side back",
        "button5": "Side forward",
        "button6": "DPI button",
        "scrollup": "Scroll up",
        "scrolldown": "Scroll down",
    ]

    static let media: [String: String] = [
        "playpause": "Play/Pause",
        "next": "Next track",
        "previous": "Previous track",
        "volumeup": "Volume up",
        "volumedown": "Volume down",
        "mute": "Mute",
    ]

    static func name(_ button: String) -> String {
        buttons[button.lowercased()] ?? button
    }

    static func actionName(_ token: String) -> String {
        let key = token.lowercased()
        switch key {
        case "default": return "Default"
        case "disabled", "disable": return "Disabled"
        case "dpi": return "Cycle DPI"
        default:
            if let name = buttons[key] { return name }
            if let name = media[key] { return name }
            return "Key \(token.uppercased())"
        }
    }

    /// The "Mouse" section of the action menu: other buttons (not the DPI button itself), Cycle DPI, Disabled.
    static func mouseActions(for spec: SettingSpec) -> [String] {
        var actions = (spec.buttons ?? []).map { $0.name.lowercased() }.filter { $0 != "button6" }
        if spec.buttonDpiSwitch != nil { actions.append("dpi") }
        if spec.buttonDisable != nil { actions.append("disabled") }
        return actions
    }
}
