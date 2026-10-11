import SwiftUI
import MouseCore

/// Settings in toolbar tabs (a `Settings` scene renders `TabView` as toolbar tabs).
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            ForEach(SettingsTab.allCases) { tab in
                SettingsTabPage(model: model, tab: tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .frame(width: 560)
    }
}

struct SettingsTabPage: View {
    let model: AppModel
    let tab: SettingsTab

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if let problem = model.problem {
                    Section {
                        StatusBanner(style: .error, message: problem, onDismiss: { model.problem = nil })
                    }
                }
                if let family = model.family {
                    if tab == .device {
                        DeviceTab(model: model, family: family)
                    } else {
                        ForEach(SettingsLayout.settings(for: tab, in: family)) { spec in
                            SettingSection(
                                title: SettingsLayout.label(for: spec), isDefault: model.isFactoryDefault(spec.key)
                            ) {
                                SettingEditor(model: model, spec: spec)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No mouse connected", systemImage: Theme.Symbol.mouse,
                        description: Text("Plug in the USB cable or the 2.4 GHz dongle.")
                    )
                }
            }
            .formStyle(.grouped)
            .disabled(model.isCheckRunning)
            HStack {
                SaveStatusLine(state: model.saveState)
                Spacer()
                if model.isCheckRunning {
                    Text("Hardware check in progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.windowPadding)
            .padding(.vertical, Theme.Space.s)
        }
        .frame(minHeight: 380)
    }
}
