import SwiftUI
import MouseCore

struct SettingsView: View {
    let model: AppModel
    @State private var confirmReset = false

    var body: some View {
        Form {
            if let family = model.family {
                ForEach(family.settings) { spec in
                    SettingRow(spec: spec, model: model)
                }
                Section {
                    if let problem = model.problem {
                        Text(problem).foregroundStyle(.red)
                    }
                    Button("Reset to factory defaults", role: .destructive) { confirmReset = true }
                }
            } else {
                Text("Connect a supported mouse to edit its settings.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .confirmationDialog("Reset every setting to the factory default?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.resetAll() }
        }
    }
}
