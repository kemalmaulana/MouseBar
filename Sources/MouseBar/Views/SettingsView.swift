import SwiftUI
import MouseCore

struct SettingsView: View {
    let model: AppModel
    @State private var confirmReset = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            if let problem = model.problem {
                Section {
                    Text(problem)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let family = model.family {
                ForEach(family.settings) { spec in
                    SettingRow(spec: spec, model: model)
                }
                Section {
                    Button("Reset to factory defaults", role: .destructive) { confirmReset = true }
                }
                Section {
                    Button("Hardware Check…") {
                        openWindow(id: "hardware-check")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            } else {
                Text("Connect a supported mouse to edit its settings.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, maxWidth: 540, minHeight: 300, idealHeight: 640, maxHeight: .infinity)
        .confirmationDialog("Reset every setting to the factory default?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.resetAll() }
        }
    }
}
