import SwiftUI
import MouseCore

struct DeviceTab: View {
    let model: AppModel
    let family: DeviceFamily
    @AppStorage("showPercentage") private var showPercentage = true
    @State private var confirmReset = false
    @State private var confirmForget = false
    @Environment(\.openWindow) private var openWindow

    /// What talks to the mouse, with the version of the data behind it.
    private var protocolDescription: String {
        if model.activeVendorID == AppModel.logitechVendorID {
            return "Logitech HID++ (OpenLogi \(model.logiRevision ?? "—"))"
        }
        return "SteelSeries (rivalcfg profiles \(model.rivalcfgVersion))"
    }

    var body: some View {
        Section("Mouse") {
            LabeledContent("Model", value: model.displayName ?? "—")
            LabeledContent("Connection") {
                if let connection = model.connection {
                    Label(connection.title, systemImage: connection.symbol)
                } else {
                    Text("—")
                }
            }
            LabeledContent("Battery", value: BatteryPresentation.detail(for: model.battery, now: Date()))
            LabeledContent("Protocol", value: protocolDescription)
        }
        Section("Menu bar") {
            Toggle("Show battery percentage", isOn: $showPercentage)
        }
        let others = SettingsLayout.otherSettings(in: family)
        if !others.isEmpty {
            ForEach(others) { spec in
                SettingSection(title: SettingsLayout.label(for: spec), isDefault: model.isFactoryDefault(spec.key)) {
                    SettingEditor(model: model, spec: spec)
                }
            }
        }
        if model.supportsHardwareCheck {
            Section("Diagnostics") {
                Button("Hardware Check…") {
                    openWindow(id: "hardware-check")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        Section {
            if model.activeVendorID == AppModel.logitechVendorID {
                // MouseBar knows no factory reset for a Logitech mouse: it only forgets what it stored, and writes nothing.
                Button("Forget MouseBar's settings for this mouse…", role: .destructive) { confirmForget = true }
                    .confirmationDialog("Forget MouseBar's settings for this mouse?", isPresented: $confirmForget) {
                        Button("Forget", role: .destructive) { model.forgetSettings() }
                    } message: {
                        Text("MouseBar stops re-applying its saved DPI and polling rate to this mouse. "
                            + "The mouse keeps its current settings.")
                    }
            } else {
                Button("Reset to factory defaults…", role: .destructive) { confirmReset = true }
                    .confirmationDialog("Reset every setting to the factory default?", isPresented: $confirmReset) {
                        Button("Reset", role: .destructive) { model.resetAll() }
                    } message: {
                        Text("Rewrites every setting on the mouse and saves it. Your MouseBar settings are cleared.")
                    }
            }
        }
    }
}
