import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let flushTimeout: Duration = .seconds(3)
    private var terminationPending = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        // Send a pending device save before quitting, but never hang on a stuck device:
        // whichever of the flush and the timeout finishes first replies, exactly once.
        var replied = false
        let reply = {
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        let timeout = Task {
            try? await Task.sleep(for: Self.flushTimeout)
            reply()
        }
        Task {
            await AppModel.shared.flush()
            timeout.cancel()
            reply()
        }
        return .terminateLater
    }
}
