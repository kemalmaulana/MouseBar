import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Send a pending device save before quitting.
        Task { @MainActor in
            await AppModel.shared.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
