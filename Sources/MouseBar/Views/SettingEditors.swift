import SwiftUI
import MouseCore

/// The value the UI shows: what MouseBar stored, or the factory default (the mouse can't be read).
@MainActor func currentValue(_ spec: SettingSpec, _ model: AppModel) -> SettingValue? {
    model.values[spec.key] ?? DefaultSettings.value(for: spec)
}

/// A form section titled with the friendly label and a Default capsule when MouseBar never set the value.
struct SettingSection<Content: View>: View {
    let title: String
    let isDefault: Bool
    @ViewBuilder let content: Content

    var body: some View {
        Section {
            content
        } header: {
            HStack(spacing: Theme.Space.s) {
                Text(title)
                if isDefault { DefaultCapsule() }
            }
        }
    }
}

/// Picks the editor for a setting's value type.
struct SettingEditor: View {
    let model: AppModel
    let spec: SettingSpec

    var body: some View {
        switch spec.valueType {
        case "multidpi_range_choice": DPIEditor(model: model, spec: spec)
        case "choice": ChoiceEditor(model: model, spec: spec)
        case "range": RangeEditor(model: model, spec: spec)
        case "rgbcolor": ColorEditor(model: model, spec: spec)
        case "buttons": ButtonsEditor(model: model, spec: spec)
        default:
            Text("This setting type (\(spec.valueType)) has no editor yet.")
                .foregroundStyle(.secondary)
        }
    }
}

struct ChoiceEditor: View {
    let model: AppModel
    let spec: SettingSpec

    var body: some View {
        Picker(SettingsLayout.label(for: spec), selection: Binding(
            get: {
                if case .choice(let c)? = currentValue(spec, model) { return c }
                return spec.defaultText
            },
            set: { model.submit(spec.key, .choice($0)) }
        )) {
            ForEach(spec.choices ?? [], id: \.key) { choice in
                Text(ValueFormat.choice(key: spec.key, choice.key)).tag(choice.key)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(SettingsLayout.label(for: spec))
    }
}

/// Slider that writes when dragging ends, with the value and its unit next to it.
struct RangeEditor: View {
    let model: AppModel
    let spec: SettingSpec
    @State private var draft: Double = 0

    var body: some View {
        let range = spec.inputRange ?? [0, 1, 1]
        HStack(spacing: Theme.Space.m) {
            Slider(value: $draft, in: Double(range[0])...Double(range[1]), step: Double(range[2])) { editing in
                guard !editing else { return }
                // A bare click on the thumb ends an "edit" without moving it: don't write an unchanged value.
                let newValue = Int(draft)
                if case .int(let shown)? = currentValue(spec, model), shown == newValue { return }
                model.submit(spec.key, .int(newValue))
            }
            .accessibilityLabel(SettingsLayout.label(for: spec))
            .accessibilityValue(ValueFormat.range(key: spec.key, value: Int(draft)))
            Text(ValueFormat.range(key: spec.key, value: Int(draft)))
                .monospacedDigit()
                .frame(width: 84, alignment: .trailing)
        }
        .onAppear { sync() }
        .onChange(of: model.values[spec.key]) { _, _ in sync() }
    }

    private func sync() {
        if case .int(let value)? = currentValue(spec, model) { draft = Double(value) }
    }
}

/// One row per DPI preset: number badge, slider, value, stepper, active star (once confirmed), remove.
struct DPIEditor: View {
    let model: AppModel
    let spec: SettingSpec
    @State private var drafts: [Double] = []

    private var presets: [Int] {
        if case .dpiPresets(let p, _)? = currentValue(spec, model) { return p }
        return [800]
    }
    private var selected: Int {
        if case .dpiPresets(_, let s)? = currentValue(spec, model) { return s ?? 0 }
        return 0
    }
    private var maxCount: Int { spec.maxPresetCount ?? 5 }
    private var bounds: [Int] { spec.inputRange ?? [100, 18000, 100] }

    private func commit(_ next: [Int], selected: Int) {
        guard !next.isEmpty else { return }
        model.submit(spec.key, .dpiPresets(presets: next, selected: min(max(selected, 0), next.count - 1)))
    }

    private func value(at index: Int) -> Int {
        presets.indices.contains(index) ? presets[index] : bounds[0]
    }

    var body: some View {
        ForEach(presets.indices, id: \.self) { index in
            HStack(spacing: Theme.Space.m) {
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(.quaternary))
                    .accessibilityHidden(true)
                Slider(value: Binding(
                    get: { drafts.indices.contains(index) ? drafts[index] : Double(value(at: index)) },
                    set: { new in
                        if !drafts.indices.contains(index) { drafts = presets.map(Double.init) }
                        if drafts.indices.contains(index) { drafts[index] = new }
                    }
                ), in: Double(bounds[0])...Double(bounds[1]), step: Double(bounds[2])) { editing in
                    guard !editing, drafts.count == presets.count else { return }
                    // A bare click on the thumb ends an "edit" without moving it: don't rewrite the presets.
                    let next = drafts.map { Int($0) }
                    if next == presets { return }
                    commit(next, selected: selected)
                }
                .accessibilityLabel("Preset \(index + 1)")
                .accessibilityValue(ValueFormat.dpi(value(at: index)))
                Text(ValueFormat.dpi(drafts.indices.contains(index) ? Int(drafts[index]) : value(at: index)))
                    .monospacedDigit()
                    .frame(width: 84, alignment: .trailing)
                Stepper("Preset \(index + 1)", value: Binding(
                    get: { value(at: index) },
                    set: { new in
                        guard presets.indices.contains(index) else { return }
                        var next = presets
                        next[index] = new
                        commit(next, selected: selected)
                    }
                ), in: bounds[0]...bounds[1], step: bounds[2])
                .labelsHidden()
                if model.activePresetConfirmed {
                    Button {
                        commit(presets, selected: index)
                    } label: {
                        Image(systemName: index == selected ? "star.fill" : "star")
                            .frame(minWidth: Theme.minHitTarget, minHeight: Theme.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Make preset \(index + 1) the active preset")
                    .accessibilityLabel(index == selected ? "Preset \(index + 1), active" : "Make preset \(index + 1) active")
                }
                Button {
                    guard presets.indices.contains(index) else { return }
                    var next = presets
                    next.remove(at: index)
                    commit(next, selected: selected > index ? selected - 1 : selected)
                } label: {
                    Image(systemName: "minus.circle")
                        .frame(minWidth: Theme.minHitTarget, minHeight: Theme.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(presets.count <= 1)
                .accessibilityLabel("Remove preset \(index + 1)")
            }
        }
        .onAppear { drafts = presets.map(Double.init) }
        .onChange(of: model.values[spec.key]) { _, _ in drafts = presets.map(Double.init) }
        Button {
            guard presets.count < maxCount else { return }
            commit(presets + [min(presets.last ?? 800, bounds[1])], selected: selected)
        } label: {
            Label("Add preset", systemImage: "plus.circle")
                .frame(minWidth: Theme.minHitTarget, minHeight: Theme.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(presets.count >= maxCount)
    }
}
