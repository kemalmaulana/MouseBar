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
            MenuContent(model: model)
        } label: {
            BatteryLabel(state: model.battery)
        }
        Window("Mouse Settings", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
