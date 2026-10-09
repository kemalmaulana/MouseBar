import Foundation

/// Port of rivalcfg's value-type handlers. Pure functions: no I/O, no state.
public struct SettingEncoder: Sendable {
    public let layouts: ButtonLayouts

    public init(layouts: ButtonLayouts) {
        self.layouts = layouts
    }

    /// The HID payload for one setting, without the report id (rivalcfg writes `[0x00] + payload`).
    public func encode(_ spec: SettingSpec, value: SettingValue) throws -> [UInt8] {
        let data: [UInt8]
        switch (spec.valueType, value) {
        case ("choice", .choice(let key)):
            data = [try choiceByte(spec, key)]
        case ("range", .int(let v)):
            data = try rangeBytes(spec, v)
        case ("rgbcolor", .color(let c)):
            data = [c.r, c.g, c.b]
        case ("multidpi_range_choice", .dpiPresets(let presets, let selected)):
            data = try dpiBytes(spec, presets: presets, selected: selected)
        case ("buttons", .buttons(let mapping)):
            data = try buttonBytes(spec, mapping)
        case ("choice", _), ("range", _), ("rgbcolor", _), ("multidpi_range_choice", _), ("buttons", _):
            throw MouseCoreError.valueMismatch(setting: spec.key, expected: spec.valueType)
        default:
            throw MouseCoreError.unsupportedValueType(spec.valueType)
        }
        var packet = Bytes.u8(spec.command) + data + Bytes.u8(spec.commandSuffix)
        if spec.packetLength > packet.count {
            packet += [UInt8](repeating: 0, count: spec.packetLength - packet.count)
        }
        return packet
    }

    // MARK: choice

    private func choiceByte(_ spec: SettingSpec, _ key: String) throws -> UInt8 {
        guard let entry = spec.choices?.first(where: { $0.key == key }) else {
            let valid = (spec.choices ?? []).map(\.key).joined(separator: ", ")
            throw MouseCoreError.invalidValue("\(spec.key): '\(key)' must be one of [\(valid)]")
        }
        return UInt8(truncatingIfNeeded: entry.value)
    }

    // MARK: range

    /// rivalcfg `matches_value_in_range`: clamp, then round to the nearest step.
    static func nearestInRange(start: Int, stop: Int, step: Int, value: Int) -> Int {
        if value <= start { return start }
        if value >= stop { return stop }
        let delta = (value - start) % step
        if delta == 0 { return value }
        return Double(delta) < Double(step) / 2 ? value - delta : value - delta + step
    }

    private func rangeBytes(_ spec: SettingSpec, _ value: Int) throws -> [UInt8] {
        guard let input = spec.inputRange, input.count == 3, input[2] > 0,
              let output = spec.outputRange, output.count == 3, output[2] > 0
        else { throw MouseCoreError.invalidValue("\(spec.key): profile has no valid range") }
        let inputCount = (input[1] - input[0]) / input[2] + 1
        let outputCount = (output[1] - output[0]) / output[2] + 1
        guard inputCount == outputCount else {
            throw MouseCoreError.invalidValue("\(spec.key): input and output ranges differ in length")
        }
        let matched = Self.nearestInRange(start: input[0], stop: input[1], step: input[2], value: value)
        let index = (matched - input[0]) / input[2]
        return try Bytes.littleEndian(output[0] + index * output[2], length: spec.rangeLengthByte ?? 1)
    }

    // MARK: multidpi_range_choice

    private func dpiBytes(_ spec: SettingSpec, presets: [Int], selected: Int?) throws -> [UInt8] {
        guard let table = spec.outputChoices, let first = spec.firstPreset,
              let maxCount = spec.maxPresetCount, let codeLength = spec.dpiLengthByte
        else { throw MouseCoreError.invalidValue("\(spec.key): profile is missing DPI parameters") }
        guard !presets.isEmpty else {
            throw MouseCoreError.invalidValue("you must provide at least one preset")
        }
        guard presets.count <= maxCount else {
            throw MouseCoreError.invalidValue(
                "you provided \(presets.count) presets but the device accepts a maximum of \(maxCount)"
            )
        }
        let selectedPreset = first + (selected ?? 0)
        guard selectedPreset >= first, selectedPreset < presets.count + first else {
            throw MouseCoreError.invalidValue("the selected preset is out of range")
        }
        let sorted = table.compactMap { $0.count == 2 ? (dpi: $0[0], code: $0[1]) : nil }.sorted { $0.dpi < $1.dpi }
        guard !sorted.isEmpty else { throw MouseCoreError.invalidValue("\(spec.key): empty DPI table") }

        var out: [UInt8] = [UInt8(truncatingIfNeeded: presets.count), UInt8(truncatingIfNeeded: selectedPreset)]
        for dpi in presets {
            // rivalcfg find_nearest_choice: ascending scan, strict '<', so ties pick the lower DPI.
            var best = sorted[0]
            for entry in sorted where abs(entry.dpi - dpi) < abs(best.dpi - dpi) {
                best = entry
            }
            out += try Bytes.littleEndian(best.code, length: codeLength)
        }
        return out
    }

    // MARK: buttons

    /// Each physical button with the action it ends up with (lowercased token), in profile order.
    func resolvedActions(spec: SettingSpec, mapping: ButtonMapping) throws -> [(button: ButtonSpec, action: String)] {
        guard let buttons = spec.buttons else {
            throw MouseCoreError.invalidValue("\(spec.key): profile has no buttons")
        }
        let known = Set(buttons.map { $0.name.lowercased() })
        for name in mapping.assignments.keys where !known.contains(name) {
            throw MouseCoreError.invalidValue("This mouse has no button named '\(name)'")
        }
        return buttons.map { button in
            let requested = mapping.assignments[button.name.lowercased()]
            let action = (requested == nil || requested == "default") ? button.defaultAction : requested!
            return (button, action.lowercased())
        }
    }

    private func buttonBytes(_ spec: SettingSpec, _ mapping: ButtonMapping) throws -> [UInt8] {
        guard let buttons = spec.buttons, let fieldLength = spec.buttonFieldLength else {
            throw MouseCoreError.invalidValue("\(spec.key): profile is missing button parameters")
        }
        let byName = Dictionary(buttons.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var specials: [String: Int] = [:]
        if let v = spec.buttonDisable { specials["disable"] = v; specials["disabled"] = v }
        if let v = spec.buttonDpiSwitch { specials["dpi"] = v }
        if let v = spec.buttonScrollUp { specials["scrollup"] = v }
        if let v = spec.buttonScrollDown {
            specials["scrolldown"] = v; specials["scrolldwn"] = v; specials["scrolldn"] = v
        }

        var packet = [UInt8](repeating: 0, count: buttons.count * fieldLength)
        for (button, action) in try resolvedActions(spec: spec, mapping: mapping) {
            let at = button.offset
            guard at + 1 < packet.count else {
                throw MouseCoreError.invalidValue("\(spec.key): button offset out of packet")
            }
            // Same precedence as rivalcfg: mouse button, special action, media key, keyboard key.
            if let target = byName[action] {
                packet[at] = UInt8(truncatingIfNeeded: target.id)
            } else if let code = specials[action] {
                packet[at] = UInt8(truncatingIfNeeded: code)
            } else if let prefix = spec.buttonMultimedia, let code = layouts.multimedia[action] {
                packet[at] = UInt8(truncatingIfNeeded: prefix)
                packet[at + 1] = UInt8(truncatingIfNeeded: code)
            } else if let prefix = spec.buttonKeyboard, let code = layouts.keyboard[action] {
                packet[at] = UInt8(truncatingIfNeeded: prefix)
                packet[at + 1] = UInt8(truncatingIfNeeded: code)
            } else {
                throw MouseCoreError.invalidValue("Unknown button, key or action '\(action)'")
            }
        }
        return packet
    }

    /// Rejects mappings after which no physical button produces the primary click (`button1`).
    /// rivalcfg warns: "keep button1 mapped to a working button, or you won't be able to click".
    public func validateButtons(_ mapping: ButtonMapping, spec: SettingSpec) throws {
        guard let primary = spec.buttons?.first?.name.lowercased() else {
            throw MouseCoreError.invalidValue("\(spec.key): profile has no buttons")
        }
        let actions = try resolvedActions(spec: spec, mapping: mapping)
        guard actions.contains(where: { $0.action == primary }) else {
            throw MouseCoreError.noPrimaryClick
        }
    }
}
