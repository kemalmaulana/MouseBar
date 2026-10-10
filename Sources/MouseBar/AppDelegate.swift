import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let flushTimeout: Duration = .seconds(3)
    private static let restoreTimeout: Duration = .seconds(5)
    private var terminationPending = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        let runner = CheckRunner.shared
        let restoring = runner.needsRestore
        // Restore the owner's settings if a hardware check is mid-way, then send a pending device save,
        // but never hang on a stuck device: whichever finishes first replies, exactly once.
        var replied = false
        let reply = {
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        let timeout = Task {
            try? await Task.sleep(for: restoring ? Self.restoreTimeout : Self.flushTimeout)
            reply()
        }
        Task {
            if restoring { await runner.restoreForQuit() }
            await AppModel.shared.flush()
            timeout.cancel()
            reply()
        }
        return .terminateLater
    }
}
