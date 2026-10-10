import SwiftUI
import MouseCore

struct SettingRow: View {
    let spec: SettingSpec
    let model: AppModel

    var body: some View {
        Section {
            switch spec.valueType {
            case "choice": ChoiceRow(spec: spec, model: model)
            case "range": RangeRow(spec: spec, model: model)
            case "rgbcolor": ColorRow(spec: spec, model: model)
            case "multidpi_range_choice": DPIRow(spec: spec, model: model)
            case "buttons": ButtonsRow(spec: spec, model: model)
            default: EmptyView()
            }
            Text(spec.description).font(.caption).foregroundStyle(.secondary)
            if model.values[spec.key] == nil {
                Text(unsetCaption).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text(spec.label)
        }
    }

    /// The mouse cannot report its settings, so a row MouseBar never set shows the factory default.
    private var unsetCaption: String {
        switch spec.valueType {
        case "multidpi_range_choice", "buttons":
            "Not set by MouseBar yet. The mouse can't report its settings, so this shows factory defaults. "
                + "Changing one entry rewrites all of them."
        default:
            "Not set by MouseBar yet; showing the factory default."
        }
    }
}

@MainActor private func current(_ spec: SettingSpec, _ model: AppModel) -> SettingValue? {
    model.values[spec.key] ?? DefaultSettings.value(for: spec)
}

struct ChoiceRow: View {
    let spec: SettingSpec
    let model: AppModel

    var body: some View {
        Picker(spec.label, selection: Binding(
            get: {
                if case .choice(let c)? = current(spec, model) { return c }
                return spec.defaultText
            },
            set: { model.submit(spec.key, .choice($0)) }
        )) {
            ForEach(spec.choices ?? [], id: \.key) { choice in
                Text(choice.key).tag(choice.key)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

struct RangeRow: View {
    let spec: SettingSpec
    let model: AppModel
    @State private var draft: Double = 0

    var body: some View {
        let range = spec.inputRange ?? [0, 1, 1]
        HStack {
            Slider(value: $draft, in: Double(range[0])...Double(range[1]), step: Double(range[2])) { editing in
                if !editing { model.submit(spec.key, .int(Int(draft))) }
            }
            Text("\(Int(draft))").monospacedDigit().frame(width: 52, alignment: .trailing)
        }
        .onAppear {
            if case .int(let v)? = current(spec, model) { draft = Double(v) }
        }
        .onChange(of: model.values[spec.key]) { _, _ in
            if case .int(let v)? = current(spec, model) { draft = Double(v) }
        }
    }
}

struct ColorRow: View {
    let spec: SettingSpec
    let model: AppModel

    var body: some View {
        ColorPicker(spec.label, selection: Binding(
            get: {
                if case .color(let c)? = current(spec, model) { return c.swiftUIColor }
                return .red
            },
            set: { new in
                if let rgb = RGBColor(color: new) { model.submit(spec.key, .color(rgb)) }
            }
        ), supportsOpacity: false)
        .labelsHidden()
    }
}

struct DPIRow: View {
    let spec: SettingSpec
    let model: AppModel

    private var presets: [Int] {
        if case .dpiPresets(let p, _)? = current(spec, model) { return p }
        return [800]
    }
    private var selected: Int {
        if case .dpiPresets(_, let s)? = current(spec, model) { return s ?? 0 }
        return 0
    }
    private var maxCount: Int { spec.maxPresetCount ?? 5 }
    private var range: ClosedRange<Int> {
        let r = spec.inputRange ?? [100, 18000, 100]
        return r[0]...r[1]
    }
    private var step: Int { (spec.inputRange ?? [100, 18000, 100])[2] }

    private func commit(_ new: [Int], selected: Int) {
        model.submit(spec.key, .dpiPresets(presets: new, selected: min(selected, new.count - 1)))
    }

    var body: some View {
        ForEach(presets.indices, id: \.self) { index in
            Stepper(value: Binding(
                get: { presets.indices.contains(index) ? presets[index] : range.lowerBound },
                set: { value in
                    guard presets.indices.contains(index) else { return }
                    var next = presets
                    next[index] = value
                    commit(next, selected: selected)
                }
            ), in: range, step: step) {
                Text("Preset \(index + 1): \(presets.indices.contains(index) ? presets[index] : range.lowerBound) DPI")
            }
        }
        HStack {
            Button("Add preset") {
                commit(presets + [min(presets.last ?? 800, range.upperBound)], selected: selected)
            }
            .disabled(presets.count >= maxCount)
            Button("Remove last") {
                commit(Array(presets.dropLast()), selected: selected)
            }
            .disabled(presets.count <= 1)
        }
    }
}

struct ButtonsRow: View {
    let spec: SettingSpec
    let model: AppModel

    private var mapping: ButtonMapping {
        if case .buttons(let m)? = current(spec, model) { return m }
        return ButtonMapping()
    }

    private func actionBinding(_ button: ButtonSpec) -> Binding<String> {
        Binding(
            get: { mapping.assignments[button.name.lowercased()] ?? "default" },
            set: { token in
                var next = mapping.assignments
                next[button.name.lowercased()] = token
                model.submit(spec.key, .buttons(ButtonMapping(assignments: next)))
            }
        )
    }

    private var otherButtons: [String] { (spec.buttons ?? []).map { $0.name.lowercased() } }
    private var specials: [String] {
        var list: [String] = []
        if spec.buttonDisable != nil { list.append("disabled") }
        if spec.buttonDpiSwitch != nil { list.append("dpi") }
        if spec.buttonScrollUp != nil { list.append("scrollup") }
        if spec.buttonScrollDown != nil { list.append("scrolldown") }
        return list
    }

    var body: some View {
        ForEach(spec.buttons ?? [], id: \.name) { button in
            Picker(button.name, selection: actionBinding(button)) {
                Text("Default (\(button.defaultAction))").tag("default")
                Section("Mouse buttons and actions") {
                    ForEach(otherButtons + specials, id: \.self) { Text($0).tag($0) }
                }
                if spec.buttonMultimedia != nil {
                    Section("Media keys") {
                        ForEach(model.layouts.multimediaKeys, id: \.self) { Text($0).tag($0.lowercased()) }
                    }
                }
                if spec.buttonKeyboard != nil {
                    Section("Keyboard keys") {
                        ForEach(model.layouts.keyboardKeys, id: \.self) { Text($0).tag($0.lowercased()) }
                    }
                }
            }
        }
    }
}
