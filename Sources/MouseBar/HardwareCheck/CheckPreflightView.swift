import SwiftUI
import MouseCore

/// Collects the owner's DPI presets and button remaps, which the mouse cannot report, so they can be restored.
struct CheckPreflightView: View {
    @Bindable var runner: CheckRunner
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Before you start")
                    .font(.title3.weight(.semibold))
                Text("The mouse can't report its DPI presets or button remaps. Enter them so the check can put them back afterwards. Start with the USB cable connected and keep the dongle nearby.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("I don't know them — restore factory defaults", isOn: $runner.useFactoryDefaults)
                if !runner.useFactoryDefaults {
                    GroupBox("DPI presets") { presetsEditor }
                    if let spec = model.family?.setting("buttons_mapping") {
                        GroupBox("Button remaps") { buttonsEditor(spec) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var presetsEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(runner.enteredPresets.indices, id: \.self) { index in
                HStack {
                    Stepper(value: Binding(
                        get: { runner.enteredPresets.indices.contains(index) ? runner.enteredPresets[index] : 100 },
                        set: { value in
                            guard runner.enteredPresets.indices.contains(index) else { return }
                            runner.enteredPresets[index] = value
                        }
                    ), in: 100...18000, step: 100) {
                        Text("Preset \(index + 1): \(ValueFormat.dpi(runner.enteredPresets.indices.contains(index) ? runner.enteredPresets[index] : 100))")
                            .monospacedDigit()
                    }
                    Button {
                        guard runner.enteredPresets.indices.contains(index) else { return }
                        runner.enteredPresets.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(runner.enteredPresets.count <= 1)
                    .accessibilityLabel("Remove preset \(index + 1)")
                }
            }
            Button {
                runner.enteredPresets.append(min(runner.enteredPresets.last ?? 800, 18000))
            } label: {
                Label("Add preset", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(runner.enteredPresets.count >= 5)
        }
        .padding(Theme.Space.s)
    }

    private func buttonsEditor(_ spec: SettingSpec) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(spec.buttons ?? [], id: \.name) { button in
                HStack {
                    Text(ButtonNames.name(button.name))
                    Spacer()
                    ButtonActionMenu(
                        spec: spec, button: button,
                        token: runner.enteredButtons.assignments[button.name.lowercased()] ?? "default",
                        layouts: model.layouts
                    ) { token in
                        var assignments = runner.enteredButtons.assignments
                        assignments[button.name.lowercased()] = token
                        runner.enteredButtons = ButtonMapping(assignments: assignments)
                    }
                }
            }
        }
        .padding(Theme.Space.s)
    }
}
