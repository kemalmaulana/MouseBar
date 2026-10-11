import Foundation

/// Vendor apps that fight MouseBar over a mouse or its receiver. MouseBar only detects them; it never quits another app.
public enum ConflictDetector {
    public static let steelSeriesGG = "SteelSeries GG"

    /// Process names to look for, and the app each one belongs to.
    private static let watched: [(process: String, app: String)] = [
        (GGDetector.engineProcessName, steelSeriesGG),
        ("SteelSeriesGG", steelSeriesGG),
        ("lghub", "Logitech G HUB"),
        ("lghub_agent", "Logitech G HUB"),
        ("lghub_updater", "Logitech G HUB"),
        ("logioptionsplus_agent", "Logi Options+"),
        ("openlogi-agent", "OpenLogi"),
    ]

    /// Display names of the conflicting apps that run right now, each once, in a fixed order.
    public static func runningApps(pgrep: @Sendable (String) -> Bool = GGDetector.livePgrep) -> [String] {
        var apps: [String] = []
        for entry in watched where !apps.contains(entry.app) && pgrep(entry.process) {
            apps.append(entry.app)
        }
        return apps
    }

    /// The banner text for a running app returned by `runningApps`.
    public static func warning(for app: String) -> String {
        if app == steelSeriesGG {
            return "SteelSeries GG is running and can interfere. Quit it, or uninstall it with “SteelSeries GG Uninstaller”."
        }
        return "\(app) is running. It can fight MouseBar over the Logitech receiver. Quit it while you use MouseBar."
    }
}
