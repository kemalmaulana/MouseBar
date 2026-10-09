import Foundation

public enum GGDetector {
    /// GG's device engine. We only warn when it runs; we never stop it.
    public static let engineProcessName = "SteelSeriesEngine"

    public static func isEngineRunning(pgrep: @Sendable (String) -> Bool = livePgrep) -> Bool {
        pgrep(engineProcessName)
    }

    @Sendable
    public static func livePgrep(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
