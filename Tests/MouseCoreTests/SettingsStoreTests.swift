import Foundation
import Testing
@testable import MouseCore

@Suite struct SettingsStoreTests {
    func makeStore() -> (SettingsStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mousebar-tests-\(UUID().uuidString)")
        return (SettingsStore(directory: dir), dir)
    }

    @Test func emptyWhenNothingStored() async {
        let (store, _) = makeStore()
        #expect(await store.values(for: "prime_mini_wireless").isEmpty)
    }

    @Test func valuesPersistAcrossStoreInstances() async throws {
        let (store, dir) = makeStore()
        try await store.set(.choice("500"), key: "polling_rate", mouse: "prime_mini_wireless")
        try await store.set(.color(RGBColor(r: 1, g: 2, b: 3)), key: "color", mouse: "prime_mini_wireless")
        let reopened = SettingsStore(directory: dir)
        let values = await reopened.values(for: "prime_mini_wireless")
        #expect(values["polling_rate"] == .choice("500"))
        #expect(values["color"] == .color(RGBColor(r: 1, g: 2, b: 3)))
    }

    @Test func miceDoNotShareValues() async throws {
        let (store, _) = makeStore()
        try await store.set(.int(7), key: "sleep_timer", mouse: "prime_mini_wireless")
        #expect(await store.values(for: "prime_wireless").isEmpty)
    }

    @Test func corruptFileReadsAsEmptyAndIsReplacedOnNextWrite() async throws {
        let (store, dir) = makeStore()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("prime_mini_wireless.json"))
        #expect(await store.values(for: "prime_mini_wireless").isEmpty)
        try await store.set(.int(3), key: "dim_timer", mouse: "prime_mini_wireless")
        let reopened = SettingsStore(directory: dir)
        #expect(await reopened.values(for: "prime_mini_wireless")["dim_timer"] == .int(3))
    }

    @Test func clearRemovesEverythingForOneMouse() async throws {
        let (store, _) = makeStore()
        try await store.set(.int(7), key: "sleep_timer", mouse: "prime_mini_wireless")
        try await store.clear(mouse: "prime_mini_wireless")
        #expect(await store.values(for: "prime_mini_wireless").isEmpty)
    }

    @Test func mouseNamesCannotEscapeTheDirectory() async throws {
        let (store, dir) = makeStore()
        try await store.set(.int(1), key: "k", mouse: "../evil")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.count == 1)
        #expect(!files[0].contains("/"))
    }

    @Test func defaultsForTheWiredFamily() throws {
        func value(_ key: String) throws -> SettingValue? { DefaultSettings.value(for: try spec("prime_wireless_wired", key)) }
        #expect(try value("polling_rate") == .choice("1000"))
        #expect(try value("default_lighting") == .choice("rainbow"))
        #expect(try value("sleep_timer") == .int(5))
        #expect(try value("dim_timer") == .int(30))
        #expect(try value("color") == .color(RGBColor(r: 255, g: 0, b: 0)))
        #expect(try value("sensitivity") == .dpiPresets(presets: [400, 800, 1200, 2400, 3200], selected: nil))
        #expect(try value("buttons_mapping") == .buttons(ButtonMapping()))
    }
}
