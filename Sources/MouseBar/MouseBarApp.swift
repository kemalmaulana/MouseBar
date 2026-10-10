import SwiftUI
import MouseCore

@main
struct MouseBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    init() {
        AppModel.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: model)
        } label: {
            BatteryLabel(state: model.battery)
        }
        .menuBarExtraStyle(.window)
        Settings {
            SettingsView(model: model)
        }
        Window("Hardware Check", id: "hardware-check") {
            CheckWindow(runner: CheckRunner.shared, model: model)
        }
        .windowResizability(.contentSize)
    }
}
