import SwiftUI
import MouseCore

struct MenuContent: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let name = model.mouseName {
            Text(name)
        }
        Text(BatteryPresentation.detail(for: model.battery, now: Date()))
        if model.ggWarning {
            Divider()
            Text("SteelSeries GG is running and may fight over the mouse.")
        }
        if let problem = model.problem {
            Divider()
            Text(problem)
        }
        Divider()
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Button("Quit MouseBar") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
